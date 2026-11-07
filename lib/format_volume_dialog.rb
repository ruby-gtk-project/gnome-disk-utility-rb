# frozen_string_literal: true

require 'adwaita'
require 'udisks'
require_relative 'create_confirm_page'
require_relative 'create_filesystem_page'
require_relative 'create_other_page'
require_relative 'create_partition_page'
require_relative 'create_password_page'
require_relative 'utils'

# FormatVolumeDialog is the create/format wizard: a back/forward header bar
# over a Gtk::Stack of up to five pages, used both to format an existing
# volume and — one page earlier — to carve a new partition out of free space
# before formatting it.
#
# A port of upstream's src/resources/ui/gdu-format-volume-dialog.blp and
# src/disks/gdu-format-volume-dialog.c, including:
#
#   * The five named pages (partition/format/other/password/confirm) and
#     #update_stack's table of which page follows which, depending on whether
#     this run is "add a partition" or "format in place", whether the
#     filesystem page's type is "other", and whether encryption is on.
#   * The back button reading "_Previous" once there is a previous page and
#     "_Cancel" on the first one; the forward button reading "N_ext" until the
#     last page, where it becomes "Cre_ate" (suggested-action, add-partition
#     mode) or "Form_at" (destructive-action, format-in-place mode).
#   * Formatting in place closing the dialog immediately and finishing the
#     UDisks call in the background, the way upstream's
#     adw_dialog_close ()-before-the-async-call does; creating a partition
#     keeps the dialog open through both UDisks calls (create then format) and
#     only closes once the second one replies.
#   * The partition-creation options: "partition-type" set to "extended" for a
#     DOS extended partition, "primary"/"logical" otherwise depending on
#     whether the offset falls inside an existing DOS extended partition, and
#     size 0 (let the daemon pick the maximum) when the chosen size is exactly
#     the free span's.
#   * The format options: "label" unless the type is "empty", "take-ownership"
#     unless the type is vfat/ntfs/exfat, "encrypt.passphrase"/"encrypt.type"
#     when encrypted, "erase" when the filesystem page's erase switch is on,
#     and "update-partition-type" always.
#
# One deliberate scope reduction: upstream's #ensure_unused call, before
# formatting in place, offers to unmount/lock whatever is currently using the
# volume first. That confirmation flow is not ported this round — formatting
# in place here calls UDisks.Block.Format directly, so formatting an in-use
# volume fails with whatever error UDisks itself raises instead of upstream's
# friendlier "in use, unmount first?" prompt. See the port's `remaining` list.
#
class FormatVolumeDialog < Adwaita::Dialog
  type_register

  PARTITION_PAGE = 'partition'
  FORMAT_PAGE = 'format'
  OTHER_PAGE = 'other'
  PASSWORD_PAGE = 'password'
  CONFIRM_PAGE = 'confirm'

  # Presents the dialog the way gdu_create_format_show () does: resolves the
  # drive/block/partition-table this object implies, builds the page chain,
  # and shows it over @parent_window.
  def self.show(parent_window, client, object, add_partition: false, add_partition_offset: 0, add_partition_maxsize: 0)
    new(
      client:                 client,
      object:                 object,
      add_partition:          add_partition,
      add_partition_offset:   add_partition_offset,
      add_partition_maxsize:  add_partition_maxsize,
    ).build.tap { |dialog| dialog.present(parent_window) }
  end

  def initialize(client:, object:, add_partition: false, add_partition_offset: 0, add_partition_maxsize: 0)
    super()

    @client = client
    @object = object
    @add_partition = add_partition
    @add_partition_offset = add_partition_offset
    @add_partition_maxsize = add_partition_maxsize

    resolve_targets
    @current = add_partition ? PARTITION_PAGE : FORMAT_PAGE
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = pages_stack

        header_bar.tap do |bar|
          bar.show_start_title_buttons = false
          bar.show_end_title_buttons = false
          bar.pack_start(back_button)
          bar.pack_end(forward_button)
        end
      end

      back_button.signal_connect('clicked') { on_back_clicked }
      forward_button.signal_connect('clicked') { on_forward_clicked }

      if @add_partition
        pages_stack.add_titled(partition_page.build, PARTITION_PAGE, 'Create Partition')
        partition_page.signal_connect('notify::complete') { update_dialog }
      end

      pages_stack.add_titled(filesystem_page.build, FORMAT_PAGE, 'Format Volume')
      filesystem_page.signal_connect('notify::complete') { update_dialog }

      pages_stack.add_titled(other_page.build, OTHER_PAGE, 'Custom Format')
      other_page.signal_connect('notify::complete') { update_dialog }

      pages_stack.add_titled(password_page.build, PASSWORD_PAGE, 'Set Password')
      password_page.signal_connect('notify::complete') { update_dialog }

      pages_stack.add_titled(confirm_page.build, CONFIRM_PAGE, 'Confirm Details')

      update_dialog
    end
  end

  private

    # gdu_create_format_show ()'s target resolution, using UDisks::Block#object
    # (the binding's own back-reference from an interface proxy to its owning
    # UDisksObject) in place of upstream's g_dbus_interface_get_object.
    def resolve_targets
      @udisks_block = @object.block
      if @udisks_block
        @udisks_drive = @client.get_drive_for_block(@udisks_block)
        block_object = @udisks_block.object || @object
      else
        @udisks_drive = @object.drive
        @udisks_block = @udisks_drive && @client.get_block_for_drive(@udisks_drive, false)
        block_object = @udisks_block&.object
      end

      @udisks_table = block_object&.partition_table
    end

    # --- Page transitions (gdu_format_volume_dialog_update_stack ()) --------

    def update_stack
      case @current
      when PARTITION_PAGE then stack_for_partition_page
      when FORMAT_PAGE then stack_for_format_page
      when OTHER_PAGE then stack_for_other_page
      when PASSWORD_PAGE then stack_for_password_page
      when CONFIRM_PAGE then stack_for_confirm_page
      end
    end

    def stack_for_partition_page
      @prev = nil
      @next = partition_page.extended? ? nil : FORMAT_PAGE
      partition_page
    end

    def stack_for_format_page
      @prev = @add_partition ? PARTITION_PAGE : nil
      @next = @add_partition ? nil : CONFIRM_PAGE
      @next = PASSWORD_PAGE if filesystem_page.encrypted?
      @next = OTHER_PAGE if filesystem_page.other?
      filesystem_page
    end

    def stack_for_other_page
      @prev = FORMAT_PAGE
      @next = other_page.encrypted? ? PASSWORD_PAGE : CONFIRM_PAGE
      other_page
    end

    def stack_for_password_page
      @next = CONFIRM_PAGE
      @prev = if filesystem_page.other?
                OTHER_PAGE
              else
                FORMAT_PAGE
              end
      password_page
    end

    def stack_for_confirm_page
      @next = nil
      @prev = filesystem_page.other? ? OTHER_PAGE : FORMAT_PAGE
      @prev = PASSWORD_PAGE if encrypt?
      confirm_page
    end

    def update_dialog
      page = update_stack

      back_button.label = @prev.nil? ? '_Cancel' : '_Previous'

      if @next.nil?
        forward_button.label = @add_partition ? 'Cre_ate' : 'Form_at'
        forward_button.remove_css_class('suggested-action')
        forward_button.remove_css_class('destructive-action')
        forward_button.add_css_class(@add_partition ? 'suggested-action' : 'destructive-action')
      else
        forward_button.label = 'N_ext'
        forward_button.remove_css_class('suggested-action')
        forward_button.remove_css_class('destructive-action')
      end

      forward_button.sensitive = page.respond_to?(:complete?) ? page.complete? : true
      pages_stack.visible_child_name = @current
      self.title = pages_stack.get_page(page).title
    end

    # --- Navigation ----------------------------------------------------------

    def on_back_clicked
      if @prev.nil?
        close
      else
        @current = @prev
        update_dialog
      end
    end

    def on_forward_clicked
      if @next
        @current = @next
        update_dialog
      elsif @add_partition
        create_partition
      else
        format_in_place
      end
    end

    # --- The fs type/erase/encrypt options everything below reads ----------

    def fs_type
      if @add_partition && partition_page.extended?
        'dos_extended'
      elsif filesystem_page.fs_type != 'other'
        filesystem_page.fs_type
      else
        other_page.fs_type
      end
    end

    def encrypt? = filesystem_page.other? ? other_page.encrypted? : filesystem_page.encrypted?

    # --- Formatting in place (ensure_unused_cb () / format_cb ()) ------------

    def format_in_place
      options = {}
      options['label'] = filesystem_page.name unless fs_type == 'empty'
      unless %w[vfat ntfs exfat].include?(fs_type)
        options['take-ownership'] = true
      end
      if encrypt?
        options['encrypt.passphrase'] = password_page.password
        options['encrypt.type'] = 'luks2'
      end
      erase = filesystem_page.erase
      options['erase'] = erase if erase
      options['update-partition-type'] = true

      @udisks_block.call_format(fs_type, options) do |_proxy, result|
        begin
          @udisks_block.call_format_finish(result)
        rescue StandardError => e
          Utils.show_error(window, 'Error formatting volume', e)
        end
      end

      close
    end

    # --- Creating a partition (on_forward_button_clicked_cb ()'s second half,
    # create_partition_cb ()) -------------------------------------------------

    def create_partition
      options = {}
      partition_type = ''

      if fs_type == 'dos_extended'
        partition_type = '0x05'
        options['partition-type'] = 'extended'
      elsif @udisks_table.type == 'dos'
        options['partition-type'] = inside_dos_extended? ? 'logical' : 'primary'
      end

      size = partition_page.size
      size = 0 if size == @add_partition_maxsize

      @udisks_table.call_create_partition(
        @add_partition_offset,
        size,
        partition_type,
        '',
        options,
      ) do |_proxy, result|
        on_partition_created(result)
      end
    end

    def inside_dos_extended?
      partitions = Array(@client.get_partitions(@udisks_table)).map do |p|
        Utils::PartitionInfo.new(offset: p.offset, size: p.size, number: p.number, container: p.container?, contained: p.contained?)
      end
      Utils.inside_dos_extended?(partitions, @add_partition_offset)
    end

    def on_partition_created(result)
      created_path = @udisks_table.call_create_partition_finish(result)
    rescue StandardError => e
      Utils.show_error(window, 'Error creating partition', e)
    else
      @client.settle
      partition_object = @client.get_object(created_path)
      partition_block = partition_object&.block

      if partition_block.nil?
        close
      elsif fs_type == 'dos_extended'
        close
      else
        @add_partition = false
        @udisks_block = partition_block
        @object = partition_object
        format_in_place
      end
    end

    def window = root

    # Memoized widget methods

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new
    def pages_stack = @pages_stack ||= Gtk::Stack.new.tap { |stack| stack.transition_type = :crossfade }

    def back_button = @back_button ||= Gtk::Button.new.tap { |button| button.use_underline = true }
    def forward_button = @forward_button ||= Gtk::Button.new.tap { |button| button.use_underline = true }

    def partition_page
      @partition_page ||= CreatePartitionPage.new(
        partition_table_type: @udisks_table&.type,
        partitions:           table_partitions,
        max_size:              @add_partition_maxsize,
        offset:                @add_partition_offset,
      )
    end

    def table_partitions
      Array(@client.get_partitions(@udisks_table)).map do |p|
        Utils::PartitionInfo.new(offset: p.offset, size: p.size, number: p.number, container: p.container?, contained: p.contained?)
      end
    end

    def filesystem_page
      @filesystem_page ||= CreateFilesystemPage.new(
        removable:           @udisks_drive&.removable? || false,
        media_compatibility: Array(@udisks_drive&.media_compatibility),
        drive_size:          @udisks_drive&.size || 0,
      )
    end

    def other_page = @other_page ||= CreateOtherPage.new
    def password_page = @password_page ||= CreatePasswordPage.new

    def confirm_page
      @confirm_page ||= CreateConfirmPage.new(
        description:      description_for_confirm,
        name:              @udisks_drive && @client.get_object_info(@object)&.name || '',
        id_label:          @udisks_block&.id_label,
        id_type:           @udisks_block&.id_type,
        preferred_device:  @udisks_block&.preferred_device,
        size:              @udisks_block&.size || 0,
        unused_space:      -1,
      )
    end

    def description_for_confirm
      @client.get_object_info(@object)&.description || '—'
    end
end
