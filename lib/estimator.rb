# frozen_string_literal: true

# Estimator turns a stream of "bytes done so far" samples into a speed and a
# time remaining, for the progress text in the create/restore image dialogs,
# the benchmark dialog and the job rows.
#
# Ported from upstream's src/disks/gduestimator.c, with src/disks/estimator.rs
# (the in-progress Rust rewrite of the same object) read alongside it. Where
# the two disagree the C file wins, because it is the one the app still uses:
#
#   * estimator.rs guards `add_sample` with `if completed_bytes >=
#     self.completed_bytes { return; }`, which throws away every forward
#     sample and keeps only backward ones. gduestimator.c's
#     g_return_if_fail (completed_bytes >= estimator->completed_bytes) is the
#     intended rule, and that is what #add_sample does here.
#
#   * estimator.rs timestamps samples with `duration_since(UNIX_EPOCH)
#     .as_secs()` but divides the delta by G_USEC_PER_SEC, so its speeds come
#     out a million times too high. gduestimator.c uses g_get_real_time (),
#     i.e. microseconds, which is what #add_sample records.
#
# Upstream is a GObject with target-bytes/completed-bytes/bytes-per-sec/
# usec-remaining properties and freezes notification around the last two.
# Nothing here puts the estimator in a GValue, so it is a plain Ruby object and
# the paired notification is an observer list called once per update.
#
class Estimator
  MAX_SAMPLES = 50
  USEC_PER_SEC = 1_000_000

  # One (time, value) pair. Upstream's `Sample` struct.
  Sample = Data.define(:time_usec, :value)

  attr_reader :target_bytes, :completed_bytes, :bytes_per_sec, :usec_remaining

  def initialize(target_bytes)
    @target_bytes = target_bytes.to_i
    @completed_bytes = 0
    @bytes_per_sec = 0
    @usec_remaining = 0
    @samples = []
    @observers = []
  end

  # Stands in for `g_object_notify` on bytes-per-sec and usec-remaining, which
  # upstream brackets with freeze/thaw so a reader sees both at once. One
  # callback per update gives the same guarantee.
  def on_changed(&block)
    @observers << block
    block
  end

  def off_changed(observer)
    @observers.delete(observer)
  end

  def samples = @samples.dup

  def num_samples = @samples.length

  # gdu_estimator_add_sample (). Samples must not go backwards; upstream
  # asserts on that with g_return_if_fail, which logs and returns, so a
  # backwards sample is ignored here rather than raising.
  def add_sample(completed_bytes)
    completed_bytes.to_i.then do |value|
      if value >= @completed_bytes
        record(value)
      end
    end
  end

  private

    def record(value)
      @completed_bytes = value

      if @samples.length == MAX_SAMPLES
        @samples.shift
      end

      @samples << Sample.new(time_usec: now_usec, value: value)

      update
    end

    # update (), averaging the speed over every consecutive pair of samples.
    def update
      @bytes_per_sec = 0
      @usec_remaining = 0

      speeds.then do |values|
        if values.any?
          apply_speed(values.sum / values.length)
        end
      end

      @observers.dup.each { |observer| observer.call(self) }
    end

    def speeds
      @samples.each_cons(2).filter_map do |a, b|
        seconds = (b.time_usec - a.time_usec).to_f / USEC_PER_SEC
        speed = (b.value - a.value) / seconds
        # Two samples can share a timestamp when a job reports twice inside the
        # same microsecond; in C that pair contributes an infinity to the
        # average, so drop it instead.
        if speed.finite?
          speed
        end
      end
    end

    def apply_speed(speed)
      @bytes_per_sec = speed.to_i

      if @bytes_per_sec.positive?
        remaining_bytes = @target_bytes - @completed_bytes
        @usec_remaining = USEC_PER_SEC * remaining_bytes / @bytes_per_sec
      end
    end

    # g_get_real_time (): wall-clock microseconds since the epoch.
    def now_usec = Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond)
end
