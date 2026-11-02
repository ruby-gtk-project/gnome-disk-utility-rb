# frozen_string_literal: true

require 'adwaita'
require_relative 'enums'
require_relative 'local_job'

# JobManager owns every LocalJob the app is running, serialises the jobs that
# touch the same UDisks object, and exposes the list the window's jobs popover
# binds to.
#
# Ported from upstream's src/disks/gdu-job-manager.c. The two structures are the
# same: a GListStore of jobs for the view, and a hash of object path => queue so
# that only the head of each per-object queue runs while the rest wait.
#
# Upstream is a GObject with `jobs` and `n-jobs` properties, and the window
# binds n-jobs to the progress button's `visible`. The Ruby bindings cannot add
# properties to a type_register'd class without a GValue dance, so n_jobs
# changes are reported through #on_n_jobs_changed and the window connects to
# that instead of a property binding.
#
class JobManager
  State = Enums::LocalJobState

  def initialize
    @jobs = Gio::ListStore.new(LocalJob)
    @jobs_by_object_path = {}
    @observers = []
    @state_observers = {}
  end

  # gdu_job_manager_get_jobs (): the model Gtk::ListBox#bind_model takes.
  def jobs = @jobs

  # gdu_job_manager_get_n_jobs ().
  def n_jobs = @jobs.n_items

  def on_n_jobs_changed(&block)
    @observers << block
    block
  end

  def off_n_jobs_changed(observer)
    @observers.delete(observer)
  end

  # gdu_job_manager_enqueue (). Returns false for a job that is already running,
  # has no object path, or is already queued here — the same three refusals
  # upstream makes.
  def enqueue(job)
    if job.state != State::QUEUED
      false
    elsif job.object_path.nil?
      false
    elsif job?(job)
      false
    else
      add(job)
    end
  end

  # gdu_job_manager_cancel_job ().
  def cancel_job(job)
    if job?(job) && job.state != State::FINISHED
      job.request_cancel
    end
  end

  # gdu_job_manager_cancel_all (). Upstream snapshots the list first, because
  # cancelling a job removes it and would otherwise shift the rest.
  def cancel_all
    Array.new(@jobs.n_items) { |i| @jobs.get_item(i) }.each { |job| cancel_job(job) }
  end

  # gdu_job_manager_has_job ().
  def job?(job)
    @jobs_by_object_path[job.object_path].then do |queue|
      !queue.nil? && queue.include?(job)
    end
  end

  def queued_jobs_for(object_path) = (@jobs_by_object_path[object_path] || []).dup

  private

    def add(job)
      @jobs_by_object_path[job.object_path] ||= []
      @jobs_by_object_path[job.object_path] << job
      @jobs.append(job)
      @state_observers[job] = job.on_notify do |notified_job, property|
        if property == :state && notified_job.state == State::FINISHED
          remove_job(notified_job)
        end
      end

      notify_job_count
      start_next_job_for_object_path(job.object_path)

      true
    end

    # start_next_job_for_object_path ().
    def start_next_job_for_object_path(object_path)
      @jobs_by_object_path[object_path].then do |queue|
        queue&.first.then do |job|
          if job && job.state == State::QUEUED
            job.start
          end
        end
      end
    end

    # gdu_job_manager_remove_job ().
    def remove_job(job)
      if job?(job)
        job.object_path.then do |object_path|
          @jobs.find(job).then do |found, position|
            if found
              @jobs.remove(position)
            end
          end

          dequeue(job)
          notify_job_count
          start_next_job_for_object_path(object_path)
        end
      end
    end

    # gdu_job_manager_dequeue ().
    def dequeue(job)
      @state_observers.delete(job).then do |observer|
        if observer
          job.off_notify(observer)
        end
      end

      @jobs_by_object_path[job.object_path].then do |queue|
        if queue
          queue.delete(job)

          if queue.empty?
            @jobs_by_object_path.delete(job.object_path)
          end
        end
      end
    end

    def notify_job_count
      @observers.dup.each { |observer| observer.call(self, n_jobs) }
    end
end
