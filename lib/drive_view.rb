# frozen_string_literal: true

require 'adwaita'
require_relative 'block_row'
require_relative 'drive_header'
require_relative 'enums'
require_relative 'format_volume_dialog'
require_relative 'space_allocation_bar'
require_relative 'utils'

# DriveView is the main window's content once a drive is selected: the
# DriveHeader banner, the space-allocation bar, the "Volumes" list of
# BlockRows, and the "Drive Information" dialog the header's info button
# opens.
#
# A port of upstream's src/resources/ui/gdu-drive-view.blp and
# src/disks/gdu-drive-view.c. Carried over faithfully:
#
#   * The three Adw.PreferencesGroups (bare, "Space Allocation", "Volumes")
#     and the drive_partitions_listbox's "boxed-list" class.
#   * The separate drive_info_dialog — an Adw.Dialog with its own
#     Adw.ToastOverlay — and its four "property" rows (Model, Serial,
#     Partitioning, Size), the first two with a copy button that toasts
#     "Copied drive … to clipboard".
#   * #mobile, which Window's breakpoint flips to switch DriveHeader between
#     its horizontal and vertical layouts.
#   * Re-reading every field from #drive on its own `changed` signal, not
#     just when #drive= is called, so a partition-table interface appearing
#     or a filesystem mounting updates the view in place.
#
# One scope reduction: of the eleven `view.*` actions upstream's drive_menu
# and DriveHeader's info button install, only `view.format` and
# `view.show-drive-dialog` are installed this round. The rest —
# create-image, restore-image, benchmark, smart, settings, standby, wakeup,
# detach, eject, poweroff — each need either a dialog this port has not built
# yet or a Drive method (standby/wakeup/detach/eject/power-off) the model
# deliberately left out this round (see drive.rb's class comment); GTK
# renders their menu items disabled, same as the rest of this port's unbuilt
# actions. See the port's `remaining` list.
#
class DriveView < Adwaita::Bin
  type_register

  install_property(
    GLib::Param::Boolean.new(
      'mobile',
      'mobile',
      'Whether DriveHeader should use its vertical layout',
      false,
      GLib::Param::READWRITE,
    ),
  )

  attr_reader :drive

  def initialize
    super()

    @drive = nil
  end

  def build
    tap do |view|
      view.child = preferences_page
      view.insert_action_group('view', action_group)

      preferences_page.tap do |page|
        page.add(header_group)
        page.add(space_group)
        page.add(volumes_group)

        header_group.add(drive_header.build)
        space_group.add(space_allocation_bar)
        volumes_group.add(drive_partitions_listbox)
      end
    end
  end

  # gdu_drive_view_set_mobile (): routed here automatically by GObject's
  # property dispatch, the same way CreateFilesystemPage's "fs-type" routes
  # to #fs_type= — this is what Window's breakpoint setter calls.
  def mobile = @mobile || false

  def mobile=(value)
    @mobile = value
    drive_header.layout_name = value ? 'vertical' : 'horizontal'
  end

  def drive=(drive)
    return if @drive.equal?(drive)

    @changed_observer.then { |observer| @drive&.off_changed(observer) }
    @drive = drive
    @changed_observer = @drive&.on_changed { update }
    update if @drive
  end

  private

    # update_drive_view ().
    def update
      drive_header.drive_name = @drive.description.to_s
      drive_header.drive_path = @drive.name.to_s
      drive_header.icon = @drive.icon

      drive_part_type_row.subtitle = @drive.partition_type || '—'
      drive_model_row.subtitle = @drive.model.to_s
      drive_serial_row.subtitle = @drive.serial.to_s
      drive_size_row.subtitle = @drive.size.positive? ? Utils.format_size(@drive.size) : '—'

      drive_partitions_listbox.bind_model(@drive.partitions) { |block| BlockRow.new(block).build }
      space_allocation_bar.drive = @drive

      update_action_enabled
    end

    def update_action_enabled
      action_group.lookup('format').enabled = @drive.feature?(Enums::Feature::FORMAT)
    end

    def window = root

    # --- Actions ---------------------------------------------------------

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        add_action(group, 'format', enabled: false) { format_disk }
        add_action(group, 'show-drive-dialog', enabled: true) { show_drive_dialog }
      end
    end

    def add_action(group, name, enabled:, &handler)
      Gio::SimpleAction.new(name).tap do |action|
        action.enabled = enabled
        action.signal_connect('activate') { handler.call }
        group.add_action(action)
      end
    end

    # format_disk_clicked_cb ().
    def format_disk
      FormatVolumeDialog.show(window, @drive.client, @drive.object_for_format, add_partition: false)
    end

    # show_drive_dialog_clicked_cb ().
    def show_drive_dialog
      drive_info_dialog.present(window)
    end

    # on_copy_drive_model_clicked ().
    def copy_drive_model
      clipboard.set(drive_model_row.subtitle)
      drive_info_dialog_toast_overlay.add_toast(Adwaita::Toast.new('Copied drive model to clipboard'))
    end

    # on_copy_drive_serial_clicked ().
    def copy_drive_serial
      clipboard.set(drive_serial_row.subtitle)
      drive_info_dialog_toast_overlay.add_toast(Adwaita::Toast.new('Copied drive serial to clipboard'))
    end

    # Memoized widget methods

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new
    def header_group = @header_group ||= Adwaita::PreferencesGroup.new

    def space_group
      @space_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Space Allocation' }
    end

    def volumes_group
      @volumes_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Volumes' }
    end

    def drive_header = @drive_header ||= DriveHeader.new

    def space_allocation_bar = @space_allocation_bar ||= SpaceAllocationBar.new

    def drive_partitions_listbox
      @drive_partitions_listbox ||= Gtk::ListBox.new.tap do |listbox|
        listbox.selection_mode = :none
        listbox.add_css_class('boxed-list')
      end
    end

    def drive_info_dialog
      @drive_info_dialog ||= Adwaita::Dialog.new.tap do |dialog|
        dialog.title = 'Drive Information'
        dialog.content_width = 480
        dialog.child = drive_info_toolbar_view

        drive_info_toolbar_view.tap do |view|
          view.add_top_bar(Adwaita::HeaderBar.new)
          view.content = drive_info_dialog_toast_overlay
        end

        drive_info_dialog_toast_overlay.child = drive_info_preferences_page

        drive_info_preferences_page.add(drive_info_group)

        drive_info_group.tap do |group|
          group.add(drive_model_row)
          group.add(drive_serial_row)
          group.add(drive_part_type_row)
          group.add(drive_size_row)
        end

        drive_model_row.add_suffix(copy_model_button)
        drive_serial_row.add_suffix(copy_serial_button)

        copy_model_button.signal_connect('clicked') { copy_drive_model }
        copy_serial_button.signal_connect('clicked') { copy_drive_serial }
      end
    end

    def drive_info_toolbar_view = @drive_info_toolbar_view ||= Adwaita::ToolbarView.new
    def drive_info_dialog_toast_overlay = @drive_info_dialog_toast_overlay ||= Adwaita::ToastOverlay.new
    def drive_info_preferences_page = @drive_info_preferences_page ||= Adwaita::PreferencesPage.new
    def drive_info_group = @drive_info_group ||= Adwaita::PreferencesGroup.new

    def drive_model_row
      @drive_model_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Model'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def drive_serial_row
      @drive_serial_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Serial'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def drive_part_type_row
      @drive_part_type_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Partitioning'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def drive_size_row
      @drive_size_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Size'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def copy_model_button
      @copy_model_button ||= Gtk::Button.new.tap do |button|
        button.tooltip_text = 'Copy'
        button.icon_name = 'edit-copy-symbolic'
        button.valign = :center
        button.add_css_class('flat')
      end
    end

    def copy_serial_button
      @copy_serial_button ||= Gtk::Button.new.tap do |button|
        button.tooltip_text = 'Copy'
        button.icon_name = 'edit-copy-symbolic'
        button.valign = :center
        button.add_css_class('flat')
      end
    end
end
