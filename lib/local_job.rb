# frozen_string_literal: true

require 'adwaita'
require_relative 'enums'

# LocalJob is one long-running operation the app performs itself — copying a
# disk image out, restoring one back, running a benchmark — as opposed to a job
# UDisks runs on the daemon side.
#
# Ported from upstream's src/disks/gdulocaljob.c and gdulocaljob.h, with
# src/disks/localjob.rs (the Rust rewrite of the same object) read alongside.
#
# Upstream derives from UDisksJobSkeleton, so every running job is also exported
# on the system bus under org.freedesktop.UDisks2.Job and other clients can
# watch and cancel it. libudisks has no Ruby binding, so this port keeps the
# same property set — operation, description, extra_markup, cancelable,
# progress_valid, progress, bytes, rate, expected_end_time, start_time,
# started_by_uid — as plain attributes and does not export them on the bus. The
# D-Bus `Cancel` method, whose handler upstream wires to handle-cancel, is
# therefore reachable only through #request_cancel.
#
# It descends from GLib::Object so JobManager can keep its jobs in a
# Gio::ListStore for the window's jobs popover to bind to.
#
class LocalJob < GLib::Object
  type_register

  State = Enums::LocalJobState
  Result = Enums::LocalJobResult

  attr_reader :object_path, :operation, :description, :extra_markup, :state
  attr_reader :bytes, :rate, :expected_end_time, :start_time, :started_by_uid
  attr_reader :user_data, :cancellable

  # @param object_path the UDisks object path the job acts on. Upstream takes
  #   the UDisksObject itself and derives the path from it; the path is the only
  #   part JobManager and the rows use, and it is what UDisksJob.Objects carries.
  # @param run called on a worker thread; must return one of Result's values.
  # @param update called on the main loop when the worker asks for one.
  # @param completed called on the main loop with (job, result, error).
  def initialize(object_path:, run:, operation: nil, description: nil, update: nil, completed: nil, user_data: nil)
    super()

    @object_path = object_path
    @operation = operation
    @description = description
    @extra_markup = nil
    @run_func = run
    @update_func = update
    @completed_func = completed
    @user_data = user_data

    @state = State::QUEUED
    @cancellable = Gio::Cancellable.new
    @cancelable = false
    @progress_valid = false
    @progress = 0.0
    @bytes = 0
    @rate = 0
    @expected_end_time = 0
    @start_time = 0
    @started_by_uid = Process.uid
    @thread = nil
    @update_queued = false
    @observers = []
    @update_mutex = Mutex.new
  end

  # --- Notification -------------------------------------------------------

  # Upstream's rows connect to GObject's `notify` and re-read everything; the
  # observer gets the property name so a caller can be choosier.
  def on_notify(&block)
    @observers << block
    block
  end

  def off_notify(observer)
    @observers.delete(observer)
  end

  # --- Properties ---------------------------------------------------------

  def description=(value)
    set_property_value(:description, value) { @description = value }
  end

  def extra_markup=(value)
    set_property_value(:extra_markup, value) { @extra_markup = value }
  end

  def operation=(value)
    set_property_value(:operation, value) { @operation = value }
  end

  def cancelable? = @cancelable

  def cancelable=(value)
    set_property_value(:cancelable, !!value) { @cancelable = !!value }
  end

  def progress_valid? = @progress_valid

  def progress_valid=(value)
    set_property_value(:progress_valid, !!value) { @progress_valid = !!value }
  end

  def progress = @progress

  def progress=(value)
    value.to_f.clamp(0.0, 1.0).then do |clamped|
      if clamped != @progress
        notify_after(:progress) { @progress = clamped }
      end
    end
  end

  def bytes=(value)
    set_property_value(:bytes, value.to_i) { @bytes = value.to_i }
  end

  def rate=(value)
    set_property_value(:rate, value.to_i) { @rate = value.to_i }
  end

  def expected_end_time=(value)
    set_property_value(:expected_end_time, value.to_i) { @expected_end_time = value.to_i }
  end

  # --- Running ------------------------------------------------------------

  # gdu_local_job_start (). Upstream hands the run function to a GTask thread;
  # here it is a Ruby thread, and every callback it triggers is marshalled back
  # onto the main loop so GTK is only ever touched from one thread.
  def start
    if @state == State::QUEUED
      notify_after(:start_time) { @start_time = Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond) }
      self.state = State::RUNNING
      @thread = Thread.new { run_on_worker }
    end
  end

  # gdu_local_job_queue_update (). Called from the worker thread; coalesces so
  # at most one update is pending, exactly as upstream's single update_source
  # does.
  def queue_update
    @update_mutex.synchronize do
      if @update_func && !@update_queued && @thread
        @update_queued = true
        GLib::Idle.add do
          deliver_queued_update
          false
        end
      end
    end
  end

  # gdu_local_job_request_cancel ().
  def request_cancel
    if @state != State::CANCELING && @state != State::FINISHED
      @state.then do |previous_state|
        self.state = State::CANCELING
        @cancellable.cancel

        if previous_state == State::QUEUED
          complete(Result::CANCELLED, nil)
        end
      end
    end
  end

  def cancelled? = @cancellable.cancelled?

  def finished? = @state == State::FINISHED

  private

    def state=(value)
      if @state != value
        notify_after(:state) { @state = value }
      end
    end

    def set_property_value(name, value)
      if yield_would_change?(name, value)
        notify_after(name) { yield }
      end
    end

    # The setters above all follow upstream's `if (g_set_str (...)) notify`
    # shape: only notify when the value actually moved.
    def yield_would_change?(name, value)
      current = instance_variable_get(:"@#{name}")
      current != value
    end

    def notify_after(name)
      yield
      @observers.dup.each { |observer| observer.call(self, name) }
    end

    def deliver_queued_update
      update_func = nil
      @update_mutex.synchronize do
        @update_queued = false
        update_func = @update_func
      end
      update_func&.call(self)
    end

    # gdu_local_job_task_thread_func () plus gdu_local_job_task_completed_cb ().
    def run_on_worker
      if @cancellable.cancelled?
        finish_on_main(Result::CANCELLED, nil)
      else
        begin
          finish_on_main(*normalise(@run_func.call(self, @cancellable)))
        rescue StandardError, GLib::Error => e
          finish_on_main(Result::ERROR, e)
        end
      end
    end

    # Upstream turns a run function's result into a GTask return: ERROR without
    # an error becomes "Job failed without setting an error", a result that is
    # neither SUCCESS nor CANCELLED becomes "Job returned an invalid result".
    def normalise(result)
      case result
      when Result::SUCCESS then [Result::SUCCESS, nil]
      when Result::CANCELLED then [Result::CANCELLED, nil]
      when Result::ERROR then [Result::ERROR, RuntimeError.new('Job failed without setting an error')]
      else [Result::ERROR, RuntimeError.new('Job returned an invalid result')]
      end
    end

    def finish_on_main(result, error)
      GLib::Idle.add do
        complete(result, error)
        false
      end
    end

    # gdu_local_job_complete ().
    def complete(result, error)
      if @state != State::FINISHED
        cancel_updates
        @thread = nil
        @completed_func.then do |completed_func|
          @completed_func = nil
          completed_func&.call(self, result, error)
        end
        @user_data = nil
        self.state = State::FINISHED
      end
    end

    def cancel_updates
      @update_mutex.synchronize do
        @update_func = nil
        @update_queued = false
      end
    end
end
