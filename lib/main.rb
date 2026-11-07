# frozen_string_literal: true

require 'adwaita'

require_relative 'drive_view'
require_relative 'enums'
require_relative 'item'
require_relative 'job_manager'
require_relative 'manager'
require_relative 'shortcuts_dialog'
require_relative 'style'
require_relative 'utils'
require_relative 'window'

# App is the application object and the port's entry point.
#
# Ported from upstream's src/disks/main.c and src/disks/gdu-application.c: the
# application id, the GApplication flags, the command-line options, the action
# entries, the accelerator table, the about dialog's contents, and the "cancel
# running operations?" confirmation that guards quitting while jobs are in
# flight.
#
# Upstream derives from AdwApplication, which registers libadwaita's style
# manager and loads the app's GResource bundle. Adwaita::Application is not
# usable from Ruby, so the application is a Gtk::Application and the stylesheet
# is installed by Style.apply on startup, which is the part of AdwApplication
# that matters here.
#
# Two menu items in the main menu — "_New Disk Image…" (app.new_disk_image) and
# "_Attach Disk Image…" (app.attach_disk_image) — have no action registered
# yet, because NewDiskImageDialog and AttachDiskImageDialog are not ported.
# GTK renders a menu item whose action does not exist as insensitive, so the
# items show, greyed, exactly where upstream puts them. Their accelerators are
# still in the table below, as they are upstream.
#
class App
  APP_ID = 'org.rubygtkproject.GnomeDiskUtility'
  VERSION = '0.1.0'
  HELP_URI = 'help:gnome-help/disk'
  WEBSITE = 'https://apps.gnome.org/DiskUtility/'
  ISSUE_URL = 'https://gitlab.gnome.org/GNOME/gnome-disk-utility/-/issues/'

  COPYRIGHT = "© 2009 The GNOME Project\n© 2008-2013 Red Hat, Inc.\n© 2008-2013 David Zeuthen"

  # gdu_application_startup ()'s action_accels table, verbatim.
  ACTION_ACCELS = {
    'win.go-back'            => ['Escape'],
    'win.open-drive-menu'    => ['F9'],
    'win.open-volume-menu'   => ['<Shift>F9'],
    'win.open-app-menu'      => ['F10'],
    'win.format-disk'        => ['<Primary>D'],
    'win.restore-disk-image' => ['<Primary>R'],
    'win.view-smart'         => ['<Primary>S'],
    'win.disk-settings'      => ['<Primary>E'],
    'win.format-partition'   => ['<Primary>P'],
    'app.new_disk_image'     => ['<Primary>N'],
    'app.attach_disk_image'  => ['<Primary>A'],
    'app.help'               => ['F1'],
    'app.quit'               => ['<Primary>Q'],
  }.freeze

  # gdu_application_set_options ()'s opt_entries.
  OPTIONS = {
    'block-device'       => [:string, 'Select device', 'DEVICE'],
    'format-device'      => [:none, 'Format selected device', nil],
    'verbose'            => [:none, 'Show verbose logs, specify up to four times to increase log level', nil],
    'xid'                => [:int, 'Ignored, kept for compatibility', 'ID'],
    'restore-disk-image' => [:filename, 'Restore disk image', 'FILE'],
  }.freeze

  attr_reader :job_manager, :manager

  # @param manager the Manager (gdu_manager_get_default ()) whose #drives the
  #   sidebar binds to. Defaults to Manager.default, which opens the real
  #   UDisksClient; a caller that wants to run without a live UDisks daemon
  #   (a spec, or a drive script) passes its own Manager instead.
  def initialize(manager: nil, job_manager: nil)
    @manager = manager || Manager.default
    @drives = @manager.drives
    @job_manager = job_manager || JobManager.new
  end

  # Returns self, not the Gtk::Application, so that the launcher's
  # `App.new.build.run` reaches #run below and the command-line options reach
  # GApplication with the program name in argv[0] where it expects it.
  def build
    tap do
      app.signal_connect('startup') do
        Style.apply
        register_actions
        register_accels
      end

      app.signal_connect('activate') do
        window.build
        window.present
      end
    end
  end

  def run(argv = ARGV) = app.run([$PROGRAM_NAME] + argv)

  def app
    @app ||= Gtk::Application.new(APP_ID, :handles_command_line).tap do |application|
      add_options(application)

      application.signal_connect('command-line') { |_app, command_line| on_command_line(command_line) }
    end
  end

  def window
    @window ||= Window.new(
      app,
      drives:      @drives,
      job_manager: @job_manager,
      drive_view:  drive_view.build,
    ).tap do |win|
      win.signal_connect('close-request') { on_close_request }
      win.insert_action_group('win', window_actions)
    end
  end

  def drive_view = @drive_view ||= DriveView.new

  # --- Actions ------------------------------------------------------------

  private

    # gdu_application_startup ()'s g_action_map_add_action_entries. The two
    # disk-image actions are deliberately absent — see the class comment.
    def register_actions
      {
        'shortcuts' => -> { show_shortcuts },
        'help'      => -> { show_help },
        'about'     => -> { show_about },
        'quit'      => -> { quit },
      }.each do |name, handler|
        app.add_action(Gio::SimpleAction.new(name).tap { |action| action.signal_connect('activate') { handler.call } })
      end
    end

    # "win.go-back" is what the Escape accelerator above is bound to, and what
    # the shortcuts dialog calls "Unselect current disk".
    def window_actions
      @window_actions ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(
          Gio::SimpleAction.new('go-back').tap do |action|
            action.signal_connect('activate') { window.unselect_drive }
          end,
        )
        group.add_action(
          Gio::SimpleAction.new('open-app-menu').tap do |action|
            action.signal_connect('activate') { window.send(:sidebar_menu).popup }
          end,
        )
      end
    end

    def register_accels
      ACTION_ACCELS.each { |action, accels| app.set_accels_for_action(action, accels) }
    end

    def add_options(application)
      OPTIONS.each do |long_name, (arg, description, arg_description)|
        application.add_main_option(
          long_name,
          option_short_name(long_name),
          :none,
          arg,
          description,
          arg_description,
        )
      end
    end

    # Only -v has a short name upstream.
    def option_short_name(long_name)
      if long_name == 'verbose'
        'v'.ord
      else
        0
      end
    end

    # --- The command line -------------------------------------------------

    # gdu_application_command_line (). The two option combinations upstream
    # rejects are rejected here with the same messages; the options that need a
    # UDisks client to act on are reported as not yet reachable rather than
    # silently ignored.
    def on_command_line(command_line)
      command_line.options_dict.then do |options|
        block_device = lookup_option(options, 'block-device')
        format_device = !lookup_option(options, 'format-device').nil?
        restore_disk_image = lookup_option(options, 'restore-disk-image')

        if format_device && block_device.nil?
          command_line.printerr_literal("--format-device must be used together with --block-device\n")
          1
        elsif format_device && !restore_disk_image.nil?
          command_line.printerr_literal("--format-device must not be used together with --restore-disk-image\n")
          1
        else
          activate_for(command_line, restore_disk_image)
        end
      end
    end

    def activate_for(command_line, restore_disk_image)
      if !restore_disk_image.nil? && !File.file?(restore_disk_image)
        command_line.printerr_literal("#{restore_disk_image} does not appear to be a regular file\n")
        1
      else
        app.activate
        0
      end
    end

    # g_variant_dict_lookup (). GLib::VariantDict#lookup wants the type string
    # the value was stored with; a filename option ("^&ay" upstream) comes back
    # as a byte string, so it is decoded the same way as a UDisks path.
    def lookup_option(options, name)
      if options.contains?(name)
        Utils.byte_string(options.lookup(name, option_type(name)))
      end
    end

    def option_type(name)
      case OPTIONS.fetch(name).first
      when :none then 'b'
      when :int then 'i'
      when :filename then 'ay'
      else 's'
      end
    end

    # --- Menu actions -----------------------------------------------------

    def show_shortcuts
      ShortcutsDialog.new.build.present(window)
    end

    # help_activated ().
    def show_help
      Gtk::UriLauncher.new(HELP_URI).launch(window, nil) { }
    end

    # about_activated ()'s adw_show_about_dialog call.
    def show_about
      Adwaita::AboutDialog.new.tap do |dialog|
        dialog.application_name = 'Disks'
        dialog.application_icon = 'drive-multidisk-symbolic'
        dialog.developer_name = 'The GNOME Project'
        dialog.version = VERSION
        dialog.copyright = COPYRIGHT
        dialog.website = WEBSITE
        dialog.issue_url = ISSUE_URL
        dialog.license_type = Gtk::License::GPL_2_0
        dialog.present(window)
      end
    end

    # --- Quitting ---------------------------------------------------------

    # application_window_close_request_cb (): returning true keeps the window
    # open while the confirmation is up.
    def on_close_request
      if jobs?
        show_close_confirmation
        true
      else
        false
      end
    end

    # gdu_application_quit ().
    def quit
      if jobs?
        show_close_confirmation
      else
        window.close
      end
    end

    def jobs? = @job_manager.n_jobs.positive?

    # application_show_close_confirmation () and
    # application_quit_response_cb ().
    def show_close_confirmation
      Utils.show_confirmation(window, close_confirmation_data) do |response|
        unless response == 'cancel'
          @job_manager.cancel_all
          app.quit
        end
      end
    end

    def close_confirmation_data
      Utils::ConfirmationDialogData.new(
        message:             'Cancel running operations?',
        description:         'Disks is performing one or more operations. Closing the app will cancel them.',
        response_verb:       'Close',
        response_appearance: :destructive,
      )
    end
end
