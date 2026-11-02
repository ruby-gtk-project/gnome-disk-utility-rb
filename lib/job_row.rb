# frozen_string_literal: true

require 'adwaita'
require_relative 'enums'
require_relative 'local_job'
require_relative 'job_manager'
require_relative 'utils'

# JobRow is one running operation in the window's jobs popover: its name, a
# progress bar, a cancel button and a status line.
#
# Ported from upstream's src/resources/ui/gdu-job-row.blp and
# src/disks/gdu-job-row.c. The layout is the .blp's — a vertical box with 18/24
# start/end and 12 top/bottom margins holding the title label, a 12px-spaced row
# of progress bar and circular raised stop button, and the dimmed status label —
# and the status text is gdu_job_row.c's format_job_status(), including the
# "%u%% - %s left" form and the "Queued"/"Canceling"/"Finished"/"Running"
# fallbacks.
#
# Upstream installs the "job.cancel" action with
# gtk_widget_class_install_action and enables or disables it from
# gdu_job_row_update. The Ruby bindings have no per-class widget action, so the
# row carries a Gio::SimpleActionGroup inserted under the name "job", which the
# button's action-name "job.cancel" resolves against identically.
#
class JobRow < Adwaita::PreferencesRow
  type_register

  State = Enums::LocalJobState

  attr_reader :job, :job_manager

  def initialize(job, job_manager = nil)
    super()

    @job = job
    @job_manager = job_manager

    self.hexpand = true
    self.valign = :center
    self.halign = :center
    self.focusable = false
  end

  def build
    tap do |row|
      row.child = content_box
      row.insert_action_group('job', action_group)

      content_box.tap do |box|
        box.append(title_label)
        box.append(progress_box)
        box.append(status_label)

        progress_box.tap do |inner|
          inner.append(progress_bar)
          inner.append(cancel_button)
        end
      end

      @job_notify = @job.on_notify { update }
      update
    end
  end

  # gdu_job_row_update ().
  def update
    title_label.label = row_title
    self.title = row_title
    progress_bar.fraction = displayed_progress
    cancel_action.enabled = can_cancel?
    set_status_label(format_job_status)
  end

  # gdu_job_row_cancel_clicked_cb (): the job manager is asked first, so a
  # queued job that has not started yet leaves the queue cleanly.
  def cancel
    if @job_manager
      @job_manager.cancel_job(@job)
    else
      @job.request_cancel
    end
  end

  private

    def row_title
      [@job.description, @job.operation].find { |text| !text.to_s.empty? } || 'Disk Operation'
    end

    def displayed_progress
      if @job.progress_valid?
        @job.progress.clamp(0.0, 1.0)
      else
        0.0
      end
    end

    def can_cancel?
      @job.cancelable? && @job.state != State::CANCELING && @job.state != State::FINISHED
    end

    # format_job_status ().
    def format_job_status
      case @job.state
      when State::QUEUED then 'Queued'
      when State::CANCELING then 'Canceling'
      when State::FINISHED then 'Finished'
      else running_status
      end
    end

    def running_status
      if @job.progress_valid?
        progress_status
      else
        'Running'
      end
    end

    def progress_status
      percent = (@job.progress.clamp(0.0, 1.0) * 100.0 + 0.5).to_i
      now = Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond)

      if @job.expected_end_time > now
        remaining = Utils.format_duration_usec(
          @job.expected_end_time - now,
          Enums::FormatDurationFlags::NO_SECONDS,
        )
        "#{percent}% - #{remaining} left"
      else
        "#{percent}%"
      end
    end

    # gdu_job_row_set_status_label (): a job that supplies extra markup gets it
    # appended after an em dash, with the status itself escaped first.
    def set_status_label(status)
      @job.extra_markup.then do |extra_markup|
        if extra_markup.to_s.empty?
          status_label.text = status
        else
          status_label.markup = "#{GLib::Markup.escape_text(status)} — #{extra_markup}"
        end
      end
    end

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(cancel_action)
      end
    end

    def cancel_action
      @cancel_action ||= Gio::SimpleAction.new('cancel').tap do |action|
        action.signal_connect('activate') { cancel }
      end
    end

    # Memoized widget methods

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_start = 18
        box.margin_end = 24
        box.margin_top = 12
        box.margin_bottom = 12
      end
    end

    # The .blp binds this label to `template.title`, which is the
    # AdwPreferencesRow title the row sets in #update.
    def title_label
      @title_label ||= Gtk::Label.new(nil).tap do |label|
        label.halign = :start
      end
    end

    def progress_box = @progress_box ||= Gtk::Box.new(:horizontal, 12)

    def progress_bar
      @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
        bar.valign = :center
        bar.hexpand = true
      end
    end

    def cancel_button
      @cancel_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'process-stop-symbolic'
        button.tooltip_text = 'Cancel'
        button.focusable = false
        button.action_name = 'job.cancel'
        button.add_css_class('circular')
        button.add_css_class('raised')
      end
    end

    def status_label
      @status_label ||= Gtk::Label.new(nil).tap do |label|
        label.halign = :start
        label.add_css_class('dimmed')
      end
    end
end
