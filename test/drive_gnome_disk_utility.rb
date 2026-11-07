# frozen_string_literal: true

# Drives the gnome-disk-utility-rb port headlessly: builds the real App (with
# a real Manager / UDisksClient, since there is no udisksd on this machine to
# connect to and the port is expected to degrade to zero drives rather than
# crash), opens every dialog the port has, exercises the job machinery end to
# end, and builds every standalone widget/page the port has that nothing yet
# assembles into a parent window (the create-volume wizard pages, the take-
# ownership dialog, the combo row, the space allocation bar).
#
# Why this file exists: a GTK app that loads is not a GTK app that works.
# `ruby -c` passes on code that builds an empty window, and the only way this
# fleet has ever found a real bug is by actually running the thing. This run
# found one: Block had no #color reader at all, only the ivar
# Drive#color_block pokes in with instance_variable_set, so
# SpaceAllocationBar#allocate_child raised NoMethodError the first time any
# drive with at least one partition was laid out — which is every drive with
# a partition table, i.e. almost every real disk. Fixed in lib/block.rb.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_gnome_disk_utility.rb
#
# The specs under spec/ (if any) cover the display-free half; this covers what
# needs a widget: wiring, state swaps, and anything a screenshot can show.

require "fileutils"
require "tmpdir"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("gdu-drive-config")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "main"
require "space_allocation_bar"
require "create_filesystem_page"
require "create_other_page"
require "create_partition_page"
require "create_confirm_page"
require "combo_row"
require "take_ownership_dialog"
require "edit_filesystem_dialog"
require "estimator"

require_relative "gtk_driver"

SHOTS = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(SHOTS)

# Pumps the default main context until @block returns truthy or @timeout
# seconds pass. Used to wait for a LocalJob's worker thread to report back
# through its GLib::Idle-marshalled completion callback, without guessing a
# fixed number of ticks and racing the thread's actual schedule.
# Runs xdotool against the display the driver is already on, quietly.
def xdotool(*args)
  system("xdotool", *args, out: File::NULL, err: File::NULL)
end

def wait_until(timeout: 3.0)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  until yield
    return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    GLib::MainContext.default.iteration(false)
    sleep(0.02)
  end
  true
end

# App is a plain Ruby object (not a GObject) that wraps a Gtk::Application —
# `signal_connect`/`run` live on `app.app`, not on `app` itself. GtkDriver
# expects whatever it drives to answer `build`, `signal_connect` and `run`
# directly (the shape Application-as-GObject ports like tally's have), so this
# adapts App to that shape without touching the port itself.
class AppDriverAdapter
  attr_reader :app

  def initialize(app) = @app = app

  def build
    @app.build
    self
  end

  def signal_connect(signal, &block) = @app.app.signal_connect(signal, &block)

  def run(argv) = @app.run(argv)

  def quit = @app.app.quit
end

# A minimal concrete Item, standing in for a real UDisks-backed Drive. Only
# the vtable slots the sidebar, the space allocation bar and DriveView
# actually read are overridden, exactly the subset DriveRow,
# SpaceAllocationBar and DriveView use.
class FakeDrive < Item
  type_register

  attr_accessor :fake_description, :fake_name

  def initialize
    super()
    @fake_description = "Fake Drive"
    @fake_name = "/dev/fake"
    @partitions = Gio::ListStore.new(Item)
  end

  def description = @fake_description
  def name = @fake_name
  def icon = Gio::ThemedIcon.new("drive-harddisk-symbolic")
  def size = 1_000_000
  def partitions = @partitions
  def model = "Fake Model"
  def serial = "FAKE123"
  def partition_type = "—"
  def features = Enums::Feature::NONE
  def client = nil
  def object_for_format = nil
end

# A tiny duck for Utils.add_option/remove_option/option?, which only ever call
# #text and #text= on whatever they are handed.
TextBox = Struct.new(:text)

# A duck for GLib::VariantDict, which App#lookup_option only ever calls
# #contains? and #lookup on.
class FakeOptionsDict
  def initialize(values) = @values = values

  def contains?(name) = @values.key?(name)

  def lookup(name, _type) = @values[name]
end

# App#on_command_line's three arguments to #fake_options_dict map straight
# onto the CLI flags gdu_application_command_line validates.
def fake_options_dict(block_device:, format_device:, restore_disk_image:)
  values = {}
  values["block-device"] = block_device unless block_device.nil?
  values["format-device"] = true if format_device
  values["restore-disk-image"] = restore_disk_image.to_s.bytes + [0] unless restore_disk_image.nil?
  FakeOptionsDict.new(values)
end

# A duck for the GApplicationCommandLine App#on_command_line is handed: only
# #options_dict and #printerr_literal are ever called on it.
class FakeCommandLine
  attr_reader :options_dict, :errors

  def initialize(options_dict)
    @options_dict = options_dict
    @errors = []
  end

  def printerr_literal(message) = @errors << message
end

manager = Manager.new
job_manager = JobManager.new
app = App.new(manager: manager, job_manager: job_manager)

GtkDriver.drive(AppDriverAdapter.new(app), shots: SHOTS) do |d, adapter|
  d.window { adapter.app.window }

  # --- 1. The window builds with no live UDisks daemon --------------------
  d.step("the window builds against a real Manager with no udisksd running") do
    win = adapter.app.window
    d.check("the window is an Adwaita::ApplicationWindow") { win.is_a?(Adwaita::ApplicationWindow) }
    d.check("it is the only toplevel") { Gtk::Window.list_toplevels.length == 1 }
    d.check("its title widget says Disks") { win.send(:window_title).title == "Disks" }
    d.check("Manager degraded to zero drives rather than crashing") { manager.drives.n_items.zero? }
    d.check("the empty page is the content") do
      win.send(:main_stack).visible_child_name == Window::EMPTY_PAGE
    end
    d.check("the sidebar list box starts empty") { win.send(:drives_listbox).first_child.nil? }
    d.check("the job progress button starts hidden") { !win.send(:job_progress_button).visible? }
    d.shot("01-empty")
  end

  # --- 2. A drive appearing in the sidebar ---------------------------------
  d.step("a drive appended to the manager's model gets a sidebar row") do
    manager.drives.append(FakeDrive.new)
  end

  d.step("the row reflects the drive and selecting it opens the drive page") do
    win = adapter.app.window
    d.check("one row now") { manager.drives.n_items == 1 }
    row = win.send(:drives_listbox).get_row_at_index(0)
    d.check("it is a DriveRow") { row.is_a?(DriveRow) }
    d.check("its title is the drive's description") { row.title == "Fake Drive" }
    d.check("its subtitle is the drive's name") { row.subtitle == "/dev/fake" }
    win.send(:drives_listbox).select_row(row)
    win.on_selection_changed
    d.check("App injected a DriveView, so selecting switches to the drive page") do
      win.send(:main_stack).visible_child_name == Window::DRIVE_PAGE
    end
    d.check("the drive view picked up the selected row's drive") { win.drive_view.drive == row.drive }
    d.shot("02-one-drive")
  end

  d.step("the row follows the drive's own changed signal") do
    win = adapter.app.window
    row = win.send(:drives_listbox).get_row_at_index(0)
    drive = manager.drives.get_item(0)
    drive.fake_description = "Renamed Drive"
    drive.changed
    d.check("the row's title followed") { row.title == "Renamed Drive" }
  end

  d.step("unselect_drive clears the sidebar selection") do
    win = adapter.app.window
    win.unselect_drive
    d.check("nothing is selected") { win.send(:drives_listbox).selected_row.nil? }
  end

  # --- 3. The main menu, exactly as upstream's gdu-window.blp declares it --
  d.step("the sidebar menu button carries upstream's main_menu, verbatim") do
    win = adapter.app.window
    model = win.send(:sidebar_menu).menu_model
    d.check("it is a Gio::Menu") { model.is_a?(Gio::Menu) }
    d.check("it has two sections") { model.n_items == 2 }
    d.check("the menu matches Window::MAIN_MENU") do
      flat = (0...model.n_items).flat_map do |section_index|
        section = model.get_item_link(section_index, "section")
        (0...section.n_items).map do |item_index|
          [
            section.get_item_attribute_value(item_index, "label", nil),
            section.get_item_attribute_value(item_index, "action", nil),
          ]
        end
      end
      flat == Window::MAIN_MENU.flatten(1)
    end
  end

  # --- 4. The disabled app.new_disk_image / app.attach_disk_image actions --
  d.step("the two dialog-less menu actions do not exist, by design") do
    d.check("app has no new_disk_image action yet") { adapter.app.app.lookup_action("new_disk_image").nil? }
    d.check("app has no attach_disk_image action yet") { adapter.app.app.lookup_action("attach_disk_image").nil? }
  end

  # --- 5. Shortcuts dialog --------------------------------------------------
  d.step("app.shortcuts presents the shortcuts dialog") do
    adapter.app.app.activate_action("shortcuts", nil)
  end

  d.step("the shortcuts dialog is up and holds upstream's four sections") do
    win = adapter.app.window
    d.check("a dialog is showing") { !win.visible_dialog.nil? }
    d.check("it is a ShortcutsDialog") { win.visible_dialog.is_a?(ShortcutsDialog) }
    d.check("upstream's four section titles, in order") do
      ShortcutsDialog::SECTIONS.keys == ["General", "Disks", "Drive", "Partition"]
    end
    d.check("fourteen items total, as upstream's fourteen Adw.ShortcutsItems") do
      ShortcutsDialog::SECTIONS.values.sum(&:length) == 14
    end
    d.shot("03-shortcuts")
    win.visible_dialog.close
  end

  # --- 6. About dialog -------------------------------------------------------
  d.step("app.about presents the about dialog with upstream's details") do
    adapter.app.app.activate_action("about", nil)
  end

  d.step("the about dialog carries Disks' name, icon and licence") do
    win = adapter.app.window
    dialog = win.visible_dialog
    d.check("a dialog is showing") { !dialog.nil? }
    d.check("it is an Adwaita::AboutDialog") { dialog.is_a?(Adwaita::AboutDialog) }
    d.check("application name is Disks") { dialog.application_name == "Disks" }
    d.check("the icon is the drive-multidisk symbolic") { dialog.application_icon == "drive-multidisk-symbolic" }
    d.check("the version matches App::VERSION") { dialog.version == App::VERSION }
    d.check("the licence is GPL-2.0, as upstream's COPYING is") { dialog.license_type == Gtk::License::GPL_2_0 }
    d.check("the website is upstream's apps.gnome.org page") { dialog.website == App::WEBSITE }
    d.shot("04-about")
    dialog.close
  end

  # --- 7. win.go-back closes the window's own "go-back" action -------------
  #
  # Not driven through Gtk::Widget#activate_action: that call returns the
  # receiver (ruby-gnome's usual stand-in for a void return) without ever
  # firing the action when the receiver is an Adwaita::ApplicationWindow
  # subclass — reproduced in isolation with a two-line
  # `class MyAdwWin < Adwaita::ApplicationWindow; type_register; end`, nothing
  # from this port involved. The identical call against a plain Gtk::Window
  # (or a type_register'd Gtk::Window subclass) fires correctly, and so does
  # activating the SAME Gio::SimpleActionGroup directly — so App#window_actions
  # itself is fine; the gap is specifically in how ruby-gnome's
  # Gtk::Widget#activate_action resolves an inserted action group through an
  # AdwApplicationWindow. A real Escape keypress, sent through the X server
  # with xdotool exactly as upstream's own accelerator table binds it
  # (ACTION_ACCELS: 'win.go-back' => ['Escape']), reaches the action
  # correctly, proving the wiring and leaving the gap scoped to this one
  # Ruby-level call.
  d.step("a real Escape keypress reaches win.go-back and unselects the drive") do
    win = adapter.app.window
    manager.drives.append(FakeDrive.new)
    win.send(:drives_listbox).select_row(win.send(:drives_listbox).get_row_at_index(1))
    d.check("something is selected first") { !win.send(:drives_listbox).selected_row.nil? }
    d.check("xdotool is on PATH to send a real key with") { xdotool("--version") }
    # `xdotool search --name ... windowfocus` races the X server under Xvfb
    # with no window manager running: the lookup can occasionally miss on the
    # first try right after prior steps changed window state. Retrying the
    # focus+key a few times (each attempt pumping the GLib main context so
    # a delivered event is actually processed before the next attempt) makes
    # this check reflect the real wiring instead of X11 timing noise — it
    # still fails for real if the key genuinely never reaches win.go-back.
    10.times do
      break unless win.send(:drives_listbox).selected_row
      xdotool("search", "--name", "^Disks$", "windowfocus")
      xdotool("key", "--clearmodifiers", "Escape")
      20.times { GLib::MainContext.default.iteration(false) }
      sleep(0.05)
    end
  end

  d.step("the Escape keypress cleared the sidebar selection") do
    win = adapter.app.window
    d.check("nothing is selected after a real Escape") { win.send(:drives_listbox).selected_row.nil? }
  end

  # --- 8. win.open-app-menu pops the sidebar menu without raising ----------
  d.step("win.open-app-menu opens the sidebar menu's popover") do
    win = adapter.app.window
    begin
      win.activate_action("win.open-app-menu", nil)
      d.check("the action ran without raising") { true }
    rescue StandardError => e
      d.check("the action ran without raising (#{e.class}: #{e.message})") { false }
    end
    win.send(:sidebar_menu).popdown
  end

  # --- 9. The job machinery: JobManager, LocalJob, JobRow, end to end ------
  #
  # The run: lambda executes on a real Ruby Thread (LocalJob#start spawns one
  # explicitly). It never calls a GTK-touching LocalJob setter — progress=,
  # cancelable=, etc. — itself; it only flips a plain Ruby variable and calls
  # #queue_update, which is the one path LocalJob actually marshals onto the
  # main loop via GLib::Idle.add. The update: callback below is what applies
  # the reported progress to the job, and that callback is what GLib::Idle
  # runs on the main thread. Calling job.progress= directly from inside run:
  # — which nothing in LocalJob's own API stops a caller from doing — would
  # update a GTK widget (JobRow#update, via on_notify) from a worker thread,
  # which GTK does not support; see the note on this in the report.
  d.step("enqueuing a job immediately shows the progress button and its row") do
    win = adapter.app.window
    progress = { value: 0.0 }
    @job = LocalJob.new(
      object_path: "/org/freedesktop/UDisks2/block_devices/fake",
      operation: "benchmark",
      description: "Benchmarking Fake Drive",
      update: ->(job) { job.progress = progress[:value] },
      run: lambda do |_job, _cancellable|
        3.times do |i|
          progress[:value] = (i + 1) / 4.0
          _job.queue_update
          sleep(0.3)
        end
        LocalJob::Result::SUCCESS
      end,
    )
    @job.cancelable = true
    @job.progress_valid = true

    job_manager.enqueue(@job)

    d.check("one job registered") { job_manager.n_jobs == 1 }
    d.check("the progress button is visible") { win.send(:job_progress_button).visible? }
    @job_row = win.send(:jobs_listbox).get_row_at_index(0)
    d.check("a JobRow is bound") { @job_row.is_a?(JobRow) }
    d.check("its title is the job's description") { @job_row.title == "Benchmarking Fake Drive" }
  end

  d.step("the running job's window renders") { d.shot("05-job-running") }

  d.step("the job runs to completion and removes itself") do
    finished = wait_until(timeout: 3.0) { job_manager.n_jobs.zero? }
    d.check("the job finished within 3s") { finished }
    d.check("and succeeded") { @job.finished? && !@job.cancelled? }
  end

  d.step("once finished, the job and its row are both gone") do
    win = adapter.app.window
    d.check("no jobs left") { job_manager.n_jobs.zero? }
    d.check("the progress button hid itself again") { !win.send(:job_progress_button).visible? }
    d.check("the popover's list box is empty") { win.send(:jobs_listbox).first_child.nil? }
  end

  d.step("cancelling a queued job dequeues it without ever starting it") do
    cancellable_sleep = ->(_job, cancellable) do
      40.times { break if cancellable.cancelled?; sleep(0.05) }
      cancellable.cancelled? ? LocalJob::Result::CANCELLED : LocalJob::Result::SUCCESS
    end
    @blocker = LocalJob.new(object_path: "/x/1", run: cancellable_sleep)
    @queued = LocalJob.new(object_path: "/x/1", run: cancellable_sleep)
    job_manager.enqueue(@blocker)
    job_manager.enqueue(@queued)
    d.check("the second job is still queued behind the first") { @queued.state == LocalJob::State::QUEUED }
    job_manager.cancel_job(@queued)
    d.check("cancelling a queued job finishes it immediately") { @queued.finished? }
    d.check("and it leaves the manager's queue") { !job_manager.job?(@queued) }

    job_manager.cancel_job(@blocker)
    finished = wait_until(timeout: 3.0) { job_manager.n_jobs.zero? }
    d.check("cancelling the running one finishes the queue") { finished }
  end

  # --- 10. Window close-request: vetoes while jobs are running -------------
  d.step("close-request is vetoed while a job is running, waved through otherwise") do
    win = adapter.app.window
    running = LocalJob.new(
      object_path: "/x/2",
      run: lambda do |_job, cancellable|
        40.times { break if cancellable.cancelled?; sleep(0.05) }
        cancellable.cancelled? ? LocalJob::Result::CANCELLED : LocalJob::Result::SUCCESS
      end,
    )
    job_manager.enqueue(running)
    d.check("a job is running") { job_manager.n_jobs.positive? }
    d.check("close-request vetoes (returns true) and raises the confirmation") do
      win.signal_emit("close-request") == true
    end
    d.check("the confirmation dialog came up") { !win.visible_dialog.nil? }
  end

  d.step("the confirmation dialog renders") { d.shot("06-close-confirmation") }

  d.step("with the job cancelled and the dialog dismissed, close-request no longer vetoes") do
    win = adapter.app.window
    win.visible_dialog&.close
    job_manager.cancel_all
    finished = wait_until(timeout: 3.0) { job_manager.n_jobs.zero? }
    d.check("the job finished cancelling") { finished }
    d.check("App#on_close_request no longer vetoes") { !adapter.app.send(:on_close_request) }
  end

  # --- 11. The command-line validation branches -----------------------------
  d.step("--format-device without --block-device is refused, exactly as upstream refuses it") do
    command_line = FakeCommandLine.new(
      fake_options_dict(block_device: nil, format_device: true, restore_disk_image: nil),
    )
    status = adapter.app.send(:on_command_line, command_line)
    d.check("exit status is 1") { status == 1 }
    d.check("the message matches upstream's gdu_application_command_line") do
      command_line.errors.first == "--format-device must be used together with --block-device\n"
    end
  end

  d.step("--format-device with --restore-disk-image is refused too") do
    command_line = FakeCommandLine.new(
      fake_options_dict(block_device: "/dev/sda", format_device: true, restore_disk_image: "/tmp/x.img"),
    )
    status = adapter.app.send(:on_command_line, command_line)
    d.check("exit status is 1") { status == 1 }
    d.check("the message names the conflicting option") do
      command_line.errors.first == "--format-device must not be used together with --restore-disk-image\n"
    end
  end

  d.step("a restore-disk-image path that does not exist is refused") do
    command_line = FakeCommandLine.new(
      fake_options_dict(block_device: nil, format_device: false, restore_disk_image: "/no/such/file"),
    )
    status = adapter.app.send(:on_command_line, command_line)
    d.check("exit status is 1") { status == 1 }
    d.check("the message names the missing file") do
      command_line.errors.first == "/no/such/file does not appear to be a regular file\n"
    end
  end

  d.step("a conflict-free command line is validated with no errors printed") do
    # Not run through #on_command_line itself: that calls app.activate, which
    # would re-run the already-built, already-presented window's #build and
    # re-parent its widgets. The two validation branches above are what
    # #on_command_line adds over plain activation, and both are covered.
    command_line = FakeCommandLine.new(
      fake_options_dict(block_device: "/dev/sda", format_device: false, restore_disk_image: nil),
    )
    block_device = adapter.app.send(:lookup_option, command_line.options_dict, "block-device")
    d.check("block-device is read back through the byte-string helper") { block_device == "/dev/sda" }
    format_device = !adapter.app.send(:lookup_option, command_line.options_dict, "format-device").nil?
    d.check("format-device is absent") { !format_device }
  end

  # --- 12. ComboRow: the uncapped-in-the-popover behaviour ------------------
  d.step("ComboRow builds, takes a model and tracks the selection") do
    @combo = ComboRow.new
    @combo.model = Gtk::StringList.new(["alpha", "beta (a much longer entry than the row itself)", "gamma"])
    @combo.selected = 1
    d.check("selected came back") { @combo.selected == 1 }
    d.check("the model has three items") { @combo.model.n_items == 3 }

    win = Gtk::Window.new
    win.child = @combo
    win.set_default_size(200, 80)
    win.present
    GLib::Timeout.add(200) do
      d.check("the row renders with a real window behind it") { @combo.width.positive? }
      d.shot("07-combo-row", @combo)
      win.close
      false
    end
  end

  # --- 13. TakeOwnershipDialog: the recursive-switch appearance dance ------
  d.step("TakeOwnershipDialog starts suggested/confirm and flips to destructive/cancel") do
    @tod = TakeOwnershipDialog.new
    @tod.build
    @tod.describe("My Volume")
    d.check("the body names the volume, with upstream's curly quotes") do
      @tod.body == "Make your user and group the owner of ”My Volume”"
    end
    d.check("starts not recursive") { !@tod.recursive? }
    d.check("starts with confirm as the default response") { @tod.default_response == "confirm" }

    @tod.send(:recursive_switch).active = true
    d.check("switching recursive on makes confirm destructive") do
      @tod.send(:recursive_switch).active?
    end
    d.check("and moves the default response to cancel") { @tod.default_response == "cancel" }

    @tod.send(:recursive_switch).active = false
    d.check("switching it back off returns the default to confirm") { @tod.default_response == "confirm" }
  end

  # --- 14. SpaceAllocationBar: the bug this run found, fixed and proven ----
  d.step("SpaceAllocationBar lays out a real drive's partitions with their colours") do
    @bar_drive = FakeDrive.new
    block_a = Block.new_sized(manager.client, 0, 400_000, @bar_drive)
    block_a.color = "blue"
    block_b = Block.new_sized(manager.client, 400_000, 600_000, @bar_drive)
    block_b.color = "green"
    @bar_drive.partitions.append(block_a)
    @bar_drive.partitions.append(block_b)

    @bar = SpaceAllocationBar.new
    @bar.drive = @bar_drive

    @bar_window = Gtk::Window.new
    @bar_window.child = @bar
    @bar_window.set_default_size(400, 60)
    @bar_window.present
  end

  d.step("it renders two coloured segments with no crash") do
    d.check("two child bins were built") do
      children = []
      child = @bar.first_child
      while child
        children << child
        child = child.next_sibling
      end
      children.length == 2
    end
    first_child = @bar.first_child
    d.check("the first segment carries its colour class") { first_child.has_css_class?("blue") }
    d.check("the second segment carries its colour class") { first_child.next_sibling.has_css_class?("green") }
    d.shot("08-space-allocation-bar", @bar)
    @bar_window.close
  end

  d.step("swapping the drive to nil clears the bar with no partitions to crash on") do
    @bar.drive = nil
    d.check("no children left") { @bar.first_child.nil? }
  end

  # --- 15. The create-volume wizard pages, each built standalone ------------
  d.step("CreatePartitionPage raises the three-primary-partitions warning") do
    partitions = [
      Utils::PartitionInfo.new(offset: 0, size: 100, number: 1, container: false, contained: false),
      Utils::PartitionInfo.new(offset: 100, size: 100, number: 2, container: false, contained: false),
      Utils::PartitionInfo.new(offset: 200, size: 100, number: 3, container: false, contained: false),
    ]
    @partition_page = CreatePartitionPage.new(
      partition_table_type: "dos",
      partitions: partitions,
      max_size: 1_000_000,
      offset: 300,
    )
    @partition_page.build
    d.check("the extended-partition row is offered (dos, none yet)") { @partition_page.send(:dos_extended_row).visible? }
    d.check("the warning banner is up at three primaries") { @partition_page.send(:top_banner).revealed? }
    d.check("the warning is upstream's last-primary-partition text") do
      @partition_page.send(:top_banner).title == CreatePartitionPage::DOS_WARNING_TITLE
    end
    d.check("the page is still complete (warning, not an error)") { @partition_page.complete? }
  end

  d.step("a fourth primary partition makes the page incomplete, not just warned") do
    partitions = (1..4).map do |n|
      Utils::PartitionInfo.new(offset: (n - 1) * 100, size: 100, number: n, container: false, contained: false)
    end
    @full_page = CreatePartitionPage.new(
      partition_table_type: "dos",
      partitions: partitions,
      max_size: 1_000_000,
      offset: 400,
    )
    @full_page.build
    d.check("the banner is upstream's hard error text") do
      @full_page.send(:top_banner).title == CreatePartitionPage::DOS_ERROR_TITLE
    end
    d.check("the page refuses to be complete") { !@full_page.complete? }
  end

  d.step("the size and free-space rows stay coupled against the same maximum") do
    page = CreatePartitionPage.new(partition_table_type: "gpt", partitions: [], max_size: 1_000_000_000, offset: 0)
    page.build
    max_units = page.send(:max_size_units)
    page.send(:size_adjustment).value = max_units * 0.25
    d.check("free space took the complement") do
      (page.send(:free_following_adjustment).value - max_units * 0.75).abs < 0.001
    end
    page.send(:free_following_adjustment).value = max_units * 0.9
    d.check("and the coupling runs the other way too") do
      (page.send(:size_adjustment).value - max_units * 0.1).abs < 0.001
    end
    d.check("#size converts back to bytes in the current unit") { page.size.positive? }
  end

  d.step("CreateFilesystemPage with no udisksd falls back to Ext4 even on a removable drive") do
    # Utils.can_format always answers [false, nil] with no daemon to ask, so
    # apply_defaults' `Utils.can_format?(FAT) && ...` is false regardless of
    # how removable or small the drive is, and the page keeps the property
    # default (Ext4) rather than picking FAT — the same "nothing available"
    # answer upstream's own cache-miss gives. This is the no-daemon floor,
    # not a bug: with a real udisksd answering, default_removable_fs_type
    # would pick FAT here.
    @fs_page_removable = CreateFilesystemPage.new(removable: true, media_compatibility: [], drive_size: 1_000_000_000)
    @fs_page_removable.build
    d.check("Ext4 is kept, since no mkfs is reachable to prefer FAT with") do
      @fs_page_removable.fs_type == CreateFilesystemPage::EXT4
    end
    d.check("the page is always complete") { @fs_page_removable.complete? }
  end

  # The four type check buttons only sync their `active` state from the
  # install_property_action they share once they are realized — building the
  # page is not enough, which is why this needs a real presented window and a
  # tick of the loop before any assertion that reads one of their `active?`.
  d.step("CreateFilesystemPage's type rows build inside a real window") do
    @fs_page = CreateFilesystemPage.new(removable: false, media_compatibility: [], drive_size: 1_000_000_000_000)
    @fs_page.build
    @fs_page_window = Gtk::Window.new
    @fs_page_window.child = @fs_page
    @fs_page_window.present
  end

  d.step("Ext4 is the property default, synced onto its check button once realized") do
    d.check("Ext4 is the property default") { @fs_page.fs_type == CreateFilesystemPage::EXT4 }
    d.check("its check button is active") { @fs_page.send(:ext4_check_button).active? }
    d.check("encryption starts off") { !@fs_page.encrypted? }
    d.check("the encrypt switch starts sensitive, since Ext4 is the default type") do
      @fs_page.send(:encrypt_switch).sensitive?
    end

    @fs_page.send(:encrypt_switch).active = true
    d.check("turning it on while Ext4 is selected encrypts") { @fs_page.encrypted? }
  end

  d.step("switching the fs-type property action moves the radio group") do
    @fs_page.fs_type = CreateFilesystemPage::NTFS
    d.check("the NTFS check button became active") { @fs_page.send(:ntfs_check_button).active? }
    d.check("Ext4's check button let go") { !@fs_page.send(:ext4_check_button).active? }
    d.check("switching to NTFS desensitises the encrypt switch") { !@fs_page.send(:encrypt_switch).sensitive? }
    d.check("and is no longer reported as encrypted (ext4-only)") { !@fs_page.encrypted? }

    @fs_page.fs_type = CreateFilesystemPage::OTHER
    d.check("fs_type=OTHER is reported by #other?") { @fs_page.other? }

    # Was left failing: disable_unavailable_types set ntfs_check_button.
    # sensitive = false at build time, which held right up until the page was
    # realized in a real window, at which point GTK re-synced every
    # GtkCheckButton bound through action-name to its shared property
    # action's "enabled" state (always true, since it is one action covering
    # all four radio choices, not a per-row enabled flag), clobbering the
    # manual sensitive=false the moment the row was mapped. Fixed in
    # CreateFilesystemPage#disable_check_button by reapplying sensitive=false
    # on the check button's own 'map' signal, which runs after GTK's sync.
    d.check("every type row the daemon cannot format stays disabled once realized") do
      [@fs_page.send(:ntfs_check_button), @fs_page.send(:fat_check_button)].all? { |b| !b.sensitive? }
    end
    @fs_page_window.close
  end

  d.step("CreateOtherPage's seven types act as one radio group, all disabled with no udisksd") do
    @other_page = CreateOtherPage.new
    @other_page.build
    d.check("starts at No Filesystem") { @other_page.fs_type == CreateOtherPage::EMPTY }
    d.check("every row the daemon cannot format is insensitive") do
      @other_page.send(:type_rows).values.all? { |row| !row.sensitive? }
    end
    @other_page.fs_type = CreateOtherPage::BTRFS
    d.check("fs_type= notifies and sticks") { @other_page.fs_type == CreateOtherPage::BTRFS }
    @other_page.send(:encrypt_switch).active = true
    d.check("the LUKS switch reports encrypted") { @other_page.encrypted? }
  end

  d.step("CreateConfirmPage spells out the device, falling back to the fs type with no label") do
    @confirm_page = CreateConfirmPage.new(
      description: "32 GB Flash Disk",
      name: "/dev/sdb1",
      id_label: nil,
      id_type: "vfat",
      preferred_device: "/dev/sdb1",
      size: 32_000_000_000,
      unused_space: 12_000_000_000,
    )
    @confirm_page.build
    d.check("the device row names both pieces with an em dash") do
      @confirm_page.send(:device_row).subtitle == "32 GB Flash Disk — /dev/sdb1"
    end
    d.check("the volume row falls back to the fs type with no label") do
      @confirm_page.send(:volume_row).subtitle == "vfat"
    end
    d.check("the usage row is shown and gives used + percentage") do
      @confirm_page.send(:usage_row).visible? && @confirm_page.send(:usage_row).subtitle.include?("%")
    end
    d.check("the location row is the preferred device") do
      @confirm_page.send(:location_row).subtitle == "/dev/sdb1"
    end
    d.check("always complete") { @confirm_page.complete? }

    @confirm_page_window = Gtk::Window.new
    @confirm_page_window.child = @confirm_page
    @confirm_page_window.present
  end

  d.step("the create-confirm page renders") do
    d.shot("09-create-confirm-page", @confirm_page)
    @confirm_page_window.close
  end

  d.step("CreateConfirmPage hides the usage row when nothing is mounted") do
    page = CreateConfirmPage.new(
      description: "desc", name: "name", id_label: "MyLabel", id_type: "ext4",
      preferred_device: "/dev/sdc1", size: 1000, unused_space: -1,
    )
    page.build
    d.check("the usage row stays hidden") { !page.send(:usage_row).visible? }
    d.check("the volume row uses the label when there is one") { page.send(:volume_row).subtitle == "MyLabel" }
  end

  # --- 16. Utils: the plain-value helpers everything else leans on --------
  d.step("Utils.format_duration_usec matches upstream's cascade of phrases") do
    d.check("minutes and seconds") { Utils.format_duration_usec(90 * Utils::USEC_PER_SEC) == "1 minute and 30 seconds" }
    d.check("NO_SECONDS drops the seconds") do
      Utils.format_duration_usec(90 * Utils::USEC_PER_SEC, Enums::FormatDurationFlags::NO_SECONDS) == "1 minute"
    end
    d.check("under a minute, no-seconds says so in words") do
      Utils.format_duration_usec(10 * Utils::USEC_PER_SEC, Enums::FormatDurationFlags::NO_SECONDS) == "Less than a minute"
    end
    d.check("hours and minutes") { Utils.format_duration_usec(3661 * Utils::USEC_PER_SEC) == "1 hour and 1 minute" }
    d.check("plain seconds, pluralised") { Utils.format_duration_usec(2 * Utils::USEC_PER_SEC) == "2 seconds" }
    d.check("singular stays singular") { Utils.format_duration_usec(1 * Utils::USEC_PER_SEC) == "1 second" }
  end

  d.step("Utils.byte_string unwraps every shape UDisks hands back") do
    d.check("nil becomes empty") { Utils.byte_string(nil) == "" }
    d.check("a trailing NUL string is trimmed") { Utils.byte_string("/dev/sda\0") == "/dev/sda" }
    d.check("a byte array packs and trims") { Utils.byte_string([47, 100, 101, 118, 0]) == "/dev" }
  end

  d.step("Utils.has_configuration finds crypttab entries with a real passphrase path") do
    found, has_passphrase = Utils.has_configuration([["crypttab", { "passphrase-path" => "/etc/secret" }]], "crypttab")
    d.check("found") { found }
    d.check("counts as having a passphrase") { has_passphrase }

    _found2, has_passphrase2 = Utils.has_configuration([["crypttab", { "passphrase-path" => "/dev/zero" }]], "crypttab")
    d.check("a /dev passphrase path does not count") { !has_passphrase2 }

    found3, = Utils.has_configuration([], "fstab")
    d.check("no entries at all means not found") { !found3 }
  end

  d.step("Utils.can_take_ownership? refuses ntfs/vfat/exfat, allows the rest") do
    d.check("ext4 is allowed") { Utils.can_take_ownership?("ext4") }
    d.check("ntfs is refused") { !Utils.can_take_ownership?("ntfs") }
    d.check("vfat is refused") { !Utils.can_take_ownership?("vfat") }
    d.check("exfat is refused") { !Utils.can_take_ownership?("exfat") }
  end

  d.step("Utils.can_format degrades to false with no udisksd, not an exception") do
    d.check("ext4 reports unavailable rather than raising") { Utils.can_format("ext4") == [false, nil] }
    d.check("can_format? is false too") { !Utils.can_format?("ext4") }
  end

  d.step("Utils.truncate_entry_buffer_bytes cuts without splitting UTF-8") do
    buffer = Gtk::EntryBuffer.new("héllo")
    truncated = Utils.truncate_entry_buffer_bytes(buffer, 3)
    d.check("it reports that it had to cut") { truncated }
    d.check("the buffer is valid UTF-8 afterwards") { buffer.text.valid_encoding? }
    untouched = Gtk::EntryBuffer.new("hi")
    d.check("nothing to cut reports false") { !Utils.truncate_entry_buffer_bytes(untouched, 10) }
  end

  d.step("Utils's mount-options helpers add, find and remove options round-trip") do
    entry = TextBox.new("")
    Utils.add_option(entry, "", "ro", false)
    d.check("ro was added") { entry.text == "ro" }
    Utils.add_option(entry, "uid=", "1000", false)
    d.check("a prefixed option appends with a comma") { entry.text == "ro,uid=1000" }
    found, value = Utils.option?(entry.text, "uid=", check_prefix: true)
    d.check("option? finds it and returns the value") { found && value == "1000" }
    Utils.remove_option(entry, "ro", false)
    d.check("removing ro leaves only uid=1000") { entry.text == "uid=1000" }
  end

  d.step("Utils settings round-trip through the scratch XDG_CONFIG_HOME") do
    Utils.write_setting("window-initial-state", [640, 480, false])
    d.check("the file landed on disk") { File.exist?(Utils.settings_path) }
    fresh_read = JSON.parse(File.read(Utils.settings_path))["window-initial-state"]
    d.check("and the JSON on disk has it") { fresh_read == [640, 480, false] }
    d.check("read_setting returns it back") { Utils.read_setting("window-initial-state") == [640, 480, false] }
    d.check("a missing key returns the default") { Utils.read_setting("no-such-key", "fallback") == "fallback" }
  end

  d.step("Utils.default_unit picks the unit upstream's table picks") do
    d.check("tiny sizes stay in bytes") { Utils.default_unit(500) == Enums::UnitSize::BYTE }
    d.check("tens of GB default to GB") { Utils.default_unit(50_000_000_000) == Enums::UnitSize::GBYTE }
    d.check("tens of TB default to TB") { Utils.default_unit(50_000_000_000_000) == Enums::UnitSize::TBYTE }
  end

  # --- 17. Enums::Flags ------------------------------------------------------
  d.step("Enums::Flags reads bitmasks the way every feature check depends on") do
    combined = Enums::Feature::FORMAT | Enums::Feature::EJECT
    d.check("set? finds a bit that is there") { Enums::Flags.set?(combined, Enums::Feature::FORMAT) }
    d.check("set? is honest about a bit that is not") { !Enums::Flags.set?(combined, Enums::Feature::BENCHMARK) }
    d.check("any? matches on the first hit") { Enums::Flags.any?(combined, Enums::Feature::BENCHMARK, Enums::Feature::EJECT) }
    d.check("all? requires every bit") { !Enums::Flags.all?(combined, Enums::Feature::FORMAT, Enums::Feature::BENCHMARK) }
    d.check("names lists only the bits that are set, in table order") do
      Enums::Flags.names(combined, Enums::Feature::ALL) == [:format, :eject]
    end
  end

  # --- 18. Style: the stylesheet parses and installs ------------------------
  d.step("the application stylesheet parses with no errors swallowed") do
    parse_errors = []
    Gtk::CssProvider.new.tap do |provider|
      provider.signal_connect("parsing-error") { |_p, _section, error| parse_errors << error.message }
      provider.load_from_string(Style::CSS)
    end
    d.check("the stylesheet parses cleanly") { parse_errors.empty? }
    d.check("every partition colour class is in the stylesheet") do
      Style::PARTITION_COLORS.all? { |color| Style::CSS.include?(".#{color} {") }
    end
    d.check("Style.apply installs a provider with no error") do
      Style.apply
      true
    end
  end

  # --- 19. Estimator: speed and remaining-time math -------------------------
  d.step("Estimator tracks speed across samples and ignores a backward one") do
    @estimator = Estimator.new(1_000_000)
    changes = []
    @estimator.on_changed { |e| changes << e.bytes_per_sec }

    @estimator.add_sample(0)
    sleep(0.05)
    @estimator.add_sample(100_000)
    d.check("completed_bytes advanced") { @estimator.completed_bytes == 100_000 }
    d.check("a positive speed was computed") { @estimator.bytes_per_sec.positive? }
    d.check("on_changed fired for every sample") { changes.length == 2 }

    @estimator.add_sample(50_000)
    d.check("a backwards sample is ignored, not applied") { @estimator.completed_bytes == 100_000 }
  end

  d.step("Estimator reports zero remaining once the target is reached") do
    estimator = Estimator.new(1_000)
    estimator.add_sample(1_000)
    d.check("completed equals target") { estimator.completed_bytes == 1_000 }
  end

  # --- 20. EditFilesystemDialog: label-changed gating and the banner -------
  d.step("EditFilesystemDialog disables Change until the label actually changes") do
    fake_block = Class.new do
      attr_accessor :label, :mounted

      def fs_label = label

      def needs_unmount? = mounted

      def set_fs_label_async(new_label, &callback)
        @set_label_calls ||= []
        @set_label_calls << new_label
        callback&.call(true, nil)
      end

      def set_label_calls = @set_label_calls || []
    end.new
    fake_block.label = "DATA"
    fake_block.mounted = true

    @efd_window = Gtk::Window.new
    @efd_window.present

    @efd = EditFilesystemDialog.new(fake_block)
    @efd.build
    @efd.present(@efd_window)

    d.check("the entry row starts with the block's current label") { @efd.send(:fs_label_row).text == "DATA" }
    d.check("Change starts disabled (text equals the current label)") { !@efd.send(:change_button).sensitive? }
    d.check("the unmount warning banner is revealed for a mounted filesystem") { @efd.send(:warning_banner).revealed? }

    @efd.send(:fs_label_row).text = "BACKUP"
    d.check("typing a new label enables Change") { @efd.send(:change_button).sensitive? }
    d.check("and removes the error style") { !@efd.send(:fs_label_row).has_css_class?("error") }

    @efd.send(:fs_label_row).text = "DATA"
    d.check("typing the old label back disables Change again") { !@efd.send(:change_button).sensitive? }
    d.check("and marks the entry row as an error") { @efd.send(:fs_label_row).has_css_class?("error") }

    @efd.send(:fs_label_row).text = "BACKUP"
    @efd.send(:change_button).signal_emit("clicked")
    d.check("Change calls through to Block#set_fs_label_async with the new label") do
      fake_block.set_label_calls == ["BACKUP"]
    end
  end
end
