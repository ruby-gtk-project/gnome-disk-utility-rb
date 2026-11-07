# frozen_string_literal: true

require 'adwaita'
require 'udisks'
require_relative 'edit_filesystem_dialog'
require_relative 'enums'
require_relative 'format_volume_dialog'
require_relative 'take_ownership_dialog'
require_relative 'utils'

# BlockRow is one row in the drive view's "Volumes" list: a partition, a
# free-space span, or (for a device UDisks shows with no partition table) the
# whole device as one span.
#
# A port of upstream's src/resources/ui/gdu-block-row.blp and
# src/disks/gdu-block-row.c. Carried over faithfully:
#
#   * The Adw.ExpanderRow with the partition image/depth-label prefix, the
#     job-indicator spinner, the mount-usage LevelBar inside an Adw.Clamp, the
#     "Create Partition" button and the options MenuButton as suffixes, and
#     the four "property"-styled detail rows (Size, Device ID, UUID,
#     Partition Type).
#   * #update's four parts: the expander's own title (the block's
#     description) and subtitle (the first mount point, or an em dash),
#     the four detail rows' subtitles, the "┗━╸"-style depth label for a
#     block nested under another (a decrypted LUKS volume under its locked
#     container), and the CSS colour class Drive#color_block already chose.
#   * #block_menu_button hidden while #create_partition_button is showing (a
#     `visible: bind …inverted`), and the menu's "Mount"/"Unmount" entry
#     swapping with the feature bits, both the way upstream's
#     update_features does it.
#
# Two scope reductions, both because their upstream dependencies are not
# ported yet:
#
#   * Of the menu's thirteen `row.*` actions, only mount, unmount,
#     take-ownership, format-partition, edit-filesystem and create-partition
#     are installed. The rest — resize, edit-partition, change-passphrase,
#     configure-fstab, configure-crypttab, lock, unlock, check-fs, repair-fs,
#     benchmark-partition and the two partition-image actions — each open a
#     dialog this port has not built yet; GTK renders their menu items
#     disabled, the same as the app menu's two unported disk-image items.
#     See the port's `remaining` list.
#
#   * #delete skips gdu_utils_ensure_unused (confirm, then unmount/lock
#     whatever is using the partition first) and the affected-devices list in
#     its confirmation dialog, and calls UDisks.Partition.Delete directly once
#     the user confirms. Deleting a mounted partition fails with whatever
#     error UDisks itself raises instead of upstream's "in use" prompt.
#
#   * The job-indicator spinner is present but never set spinning: it would
#     need JobManager to report jobs by the object path they act on, which it
#     does not do yet.
#
class BlockRow < Adwaita::ExpanderRow
  type_register

  def initialize(block)
    super()

    @block = block
  end

  def build
    tap do |row|
      row.add_prefix(prefix_box)
      row.add_suffix(suffix_box)
      row.add_row(size_row)
      row.add_row(device_id_row)
      row.add_row(uuid_row)
      row.add_row(partition_type_row)

      row.insert_action_group('row', action_group)

      if @block.color
        row.add_css_class(@block.color)
      end

      @changed_observer = @block.on_changed { update }
      update
    end
  end

  # gdu_block_row_update ().
  def update
    self.title = @block.description.to_s
    update_information
    update_depth_label
    update_mount_point
    update_features
  end

  def unbind
    if @changed_observer
      @block.off_changed(@changed_observer)
      @changed_observer = nil
    end
  end

  private

    def update_information
      partition_type_row.subtitle = @block.partition_type || '—'
      uuid_row.subtitle = @block.uuid.to_s
      device_id_row.subtitle = @block.device_id.to_s
      size_row.subtitle = @block.size_str
    end

    # gdu_block_row_update_depth_label (): "┗━╸" with one extra "━" per level
    # of nesting below the block's own drive (a decrypted volume nested under
    # its locked container is one level deep).
    def update_depth_label
      depth = 0
      parent = @block.parent
      while (parent = parent&.parent)
        depth += 1
      end

      if depth.positive?
        depth_label.label = "┗#{'━' * (depth - 1)}╸"
        depth_label.visible = true
      else
        depth_label.visible = false
      end
    end

    def update_mount_point
      mount_points = @block.mount_points
      mounted = !mount_points.empty?
      space_level_bar.visible = mounted

      unless mounted
        self.subtitle = '—'
        return
      end

      size = @block.size
      free_space = @block.unused_size
      space_level_bar.max_value = size / 1000.0
      space_level_bar.value = (size - free_space) / 1000.0
      self.subtitle = mount_points.first
    end

    def update_features
      features = @block.features

      block_menu_button.visible = features != Enums::Feature::NONE
      if Enums::Flags.set?(features, Enums::Feature::CREATE_PARTITION)
        create_partition_button.visible = true
      end

      update_mount_menu_item(features)

      action_group.lookup('create_partition').enabled = Enums::Flags.set?(features, Enums::Feature::CREATE_PARTITION)
      action_group.lookup('mount').enabled = Enums::Flags.set?(features, Enums::Feature::CAN_MOUNT)
      action_group.lookup('unmount').enabled = Enums::Flags.set?(features, Enums::Feature::CAN_UNMOUNT)
      action_group.lookup('take_ownership').enabled = Enums::Flags.set?(features, Enums::Feature::TAKE_OWNERSHIP)
      action_group.lookup('format_partition').enabled = Enums::Flags.set?(features, Enums::Feature::FORMAT)
      action_group.lookup('edit_filesystem').enabled = Enums::Flags.set?(features, Enums::Feature::EDIT_LABEL)
      action_group.lookup('delete').enabled = Enums::Flags.set?(features, Enums::Feature::DELETE_PARTITION)
    end

    # gdu_block_row_update_features ()'s "Mount"/"Unmount" swap at the top of
    # the volume-actions submenu.
    def update_mount_menu_item(features)
      label, action =
        if Enums::Flags.set?(features, Enums::Feature::CAN_MOUNT)
          ['Mount', 'row.mount']
        elsif Enums::Flags.set?(features, Enums::Feature::CAN_UNMOUNT)
          ['Unmount', 'row.unmount']
        end

      volume_actions_submenu.remove(0) if volume_actions_submenu.n_items.positive?
      if label
        volume_actions_submenu.prepend(label, action)
      end
    end

    # --- Actions --------------------------------------------------------------

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        add_action(group, 'create_partition') { create_partition }
        add_action(group, 'mount') { mount }
        add_action(group, 'unmount') { unmount }
        add_action(group, 'take_ownership') { take_ownership }
        add_action(group, 'format_partition') { format_partition }
        add_action(group, 'edit_filesystem') { edit_filesystem }
        add_action(group, 'delete') { delete_partition }
      end
    end

    def add_action(group, name, &handler)
      Gio::SimpleAction.new(name).tap do |action|
        action.signal_connect('activate') { handler.call }
        group.add_action(action)
      end
    end

    # format_partition_cb ().
    def format_partition
      FormatVolumeDialog.show(window, client, @block.object, add_partition: false)
    end

    # edit_filesystem_cb ().
    def edit_filesystem
      EditFilesystemDialog.show(window, @block)
    end

    # create_partition_cb (): walks up to the owning Drive for its client and
    # UDisksObject, the way upstream walks GduItem#parent until it finds one.
    def create_partition
      drive = @block.parent
      drive = drive.parent until drive.respond_to?(:object_for_format)

      FormatVolumeDialog.show(
        window,
        drive.client,
        drive.object_for_format,
        add_partition:        true,
        add_partition_offset: @block.offset,
        add_partition_maxsize: @block.size,
      )
    end

    # mount_cb ().
    def mount
      @block.object.filesystem.call_mount({}) do |_proxy, result|
        begin
          @block.object.filesystem.call_mount_finish(result)
        rescue StandardError => e
          Utils.show_error(window, 'Error mounting filesystem', e)
        end
      end
    end

    # unmount_cb (), minus gdu_utils_ensure_unused — see the class comment.
    def unmount
      @block.object.filesystem.call_unmount({}) do |_proxy, result|
        begin
          @block.object.filesystem.call_unmount_finish(result)
        rescue StandardError => e
          Utils.show_error(window, 'Error unmounting filesystem', e)
        end
      end
    end

    # take_ownership_cb () and on_take_ownership_dialog_response_cb ().
    def take_ownership
      TakeOwnershipDialog.new.build.tap do |dialog|
        dialog.describe(@block.description.to_s)
        dialog.choose_response(window) do |confirmed, recursive|
          next unless confirmed

          options = recursive ? { 'recursive' => true } : {}
          @block.object.filesystem.call_take_ownership(options) do |_proxy, result|
            begin
              @block.object.filesystem.call_take_ownership_finish(result)
            rescue StandardError => e
              Utils.show_error(window, 'Error while taking filesystem ownership', e)
            end
          end
        end
      end
    end

    # delete_cb () and delete_response_cb (), minus ensure_unused and the
    # affected-devices list — see the class comment.
    def delete_partition
      data = Utils::ConfirmationDialogData.new(
        message:             'Delete Partition?',
        description:         'All data on the partition will be lost',
        response_verb:       'Delete',
        response_appearance: :destructive,
      )

      Utils.show_confirmation(window, data) do |response|
        next if response == 'cancel'

        @block.object.partition.call_delete({}) do |_proxy, result|
          begin
            @block.object.partition.call_delete_finish(result)
          rescue StandardError => e
            Utils.show_error(window, 'Error deleting partition', e)
          end
        end
      end
    end

    def client = Utils.udisks_client

    def window = root

    # Memoized widget methods

    def prefix_box
      @prefix_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.append(depth_label)
        box.append(partition_image)
      end
    end

    def depth_label = @depth_label ||= Gtk::Label.new.tap { |label| label.visible = false }

    def partition_image
      @partition_image ||= Gtk::Image.new.tap do |image|
        image.halign = :center
        image.valign = :center
        image.margin_start = 6
        image.margin_end = 6
        image.width_request = 20
        image.height_request = 20
        image.add_css_class('partition-row')
        image.icon_name = 'drive-harddisk-symbolic'
      end
    end

    def suffix_box
      @suffix_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.append(job_indicator_spinner)
        box.append(level_bar_clamp)
        box.append(create_partition_button)
        box.append(block_menu_button)

        block_menu_button.bind_property('visible', create_partition_button, 'visible', :invert_boolean)
      end
    end

    def job_indicator_spinner = @job_indicator_spinner ||= Gtk::Spinner.new

    def level_bar_clamp
      @level_bar_clamp ||= Adwaita::Clamp.new.tap do |clamp|
        clamp.halign = :end
        clamp.maximum_size = 160
        clamp.tightening_threshold = 160
        clamp.child = space_level_bar
      end
    end

    def space_level_bar
      @space_level_bar ||= Gtk::LevelBar.new.tap do |bar|
        bar.visible = false
        bar.valign = :center
        bar.hexpand = true
        bar.width_request = 80
        bar.height_request = 18
      end
    end

    def create_partition_button
      @create_partition_button ||= Gtk::Button.new.tap do |button|
        button.tooltip_text = 'Create Partition'
        button.valign = :center
        button.icon_name = 'list-add-symbolic'
        button.action_name = 'row.create_partition'
        button.visible = false
        button.add_css_class('flat')
      end
    end

    def block_menu_button
      @block_menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.tooltip_text = 'Partition Options'
        button.valign = :center
        button.menu_model = block_menu
        button.icon_name = 'view-more-symbolic'
        button.add_css_class('flat')
      end
    end

    def block_menu
      @block_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, volume_actions_submenu)
        menu.append_section(nil, filesystem_actions_section)
        menu.append_section(nil, image_actions_section)
      end
    end

    # The menu's first section: the mutable mount/unmount/lock/unlock entry
    # this class prepends to and removes from, then the thirteen fixed
    # entries from upstream's `section volume_actions_submenu`.
    def volume_actions_submenu
      @volume_actions_submenu ||= Gio::Menu.new.tap do |menu|
        menu.append('Resize…', 'row.resize')
        menu.append_submenu('Edit', edit_submenu)
        menu.append('Format Partition…', 'row.format_partition')
        menu.append('Delete…', 'row.delete')
      end
    end

    def edit_submenu
      Gio::Menu.new.tap do |menu|
        menu.append('Partition…', 'row.edit_partition')
        menu.append('Filesystem…', 'row.edit_filesystem')
        menu.append('Change Passphrase…', 'row.change_passphrase')
        menu.append('Mount Options…', 'row.configure_fstab')
        menu.append('Encryption Options…', 'row.configure_crypttab')
        menu.append('Take Ownership…', 'row.take_ownership')
      end
    end

    def filesystem_actions_section
      Gio::Menu.new.tap do |menu|
        menu.append('Check Filesystem…', 'row.check_fs')
        menu.append('Repair Filesystem…', 'row.repair_fs')
        menu.append('Benchmark Partition…', 'row.benchmark_partition')
      end
    end

    def image_actions_section
      Gio::Menu.new.tap do |menu|
        menu.append('Create Partition Image…', 'row.create_partition_image')
        menu.append('Restore Partition Image…', 'row.restore_partition_image')
      end
    end

    def size_row
      @size_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Size'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def device_id_row
      @device_id_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Device ID'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def uuid_row
      @uuid_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'UUID'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end

    def partition_type_row
      @partition_type_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Partition Type'
        row.subtitle_selectable = true
        row.add_css_class('property')
      end
    end
end
