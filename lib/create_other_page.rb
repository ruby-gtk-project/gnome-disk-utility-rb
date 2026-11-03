# frozen_string_literal: true

require 'adwaita'
require_relative 'utils'

# CreateOtherPage is the wizard page behind "Other" on the filesystem page: the
# seven less common things a volume can be formatted as, and the same LUKS
# switch the filesystem page offers.
#
# A port of upstream's src/resources/ui/gdu-create-other-page.blp and
# src/disks/gdu-create-other-page.c. Carried over faithfully:
#
#   * The seven rows under "Type", in upstream's order, with upstream's titles
#     and subtitles, each an Adw.ActionRow with a Gtk.CheckButton prefix bound
#     to the page's `update_fs_type` property action with the type's name as
#     target — so the seven act as one radio group — and each row activatable
#     through its check button.
#   * "No Filesystem" (`empty`) being the property's default, so the page opens
#     with nothing selected but that.
#   * The "Password Protect Volume" Adw.SwitchRow below the group.
#   * A type whose mkfs the daemon cannot run: the row goes insensitive and
#     carries "The utility %s is missing." as its tooltip.
#
# Two deliberate differences:
#
#   * Upstream's `fs-type` is a GduOtherFsType enum property whose value nicks
#     are the seven names below; the property here is the nick itself, which is
#     what gdu_create_other_page_get_fs () returns and what the check buttons'
#     action targets already are.
#
#   * Upstream calls UDisksManager.CanFormat once per row and asynchronously,
#     disabling each row from its own callback. There is no libudisks binding
#     here, so the answer comes from Utils.can_format, which reads
#     SupportedFilesystems and calls CanFormat once per supported filesystem
#     and caches the lot — the way gdu_utils_can_format does it upstream.
#
class CreateOtherPage < Adwaita::Bin
  type_register

  XFS = 'xfs'
  SWAP = 'swap'
  BTRFS = 'btrfs'
  F2FS = 'f2fs'
  EXFAT = 'exfat'
  UDF = 'udf'
  EMPTY = 'empty'

  install_property(
    GLib::Param::Boolean.new(
      'complete',
      'complete',
      'Whether the page has everything it needs',
      true,
      GLib::Param::READABLE,
    ),
  )

  install_property(
    GLib::Param::String.new(
      'fs-type',
      'fs-type',
      'The filesystem to create',
      EMPTY,
      GLib::Param::READABLE | GLib::Param::WRITABLE,
    ),
  )

  install_property_action('update_fs_type', 'fs-type')

  # gdu_create_other_page_new ()'s other_fs_title_desc table, in the order
  # GduOtherFsType declares, paired with each type's name.
  TYPE_ROWS = [
    ['XFS', 'Linux Filesystem', XFS],
    ['Linux Swap Partition', nil, SWAP],
    ['Btrfs', 'Copy-on-write Linux Filesystem, for snapshots', BTRFS],
    ['F2FS', 'Flash Storage Linux Filesystem', F2FS],
    ['exFAT', 'Flash Storage Windows Filesystem, used on SDXC cards', EXFAT],
    ['UDF', 'Universal Disk Format, for removable devices on many systems', UDF],
    ['No Filesystem', nil, EMPTY],
  ].freeze

  def initialize
    super()

    @fs_type = EMPTY
  end

  def build
    tap do |page|
      page.child = preferences_page

      preferences_page.tap do |prefs|
        prefs.add(fs_types_group)
        prefs.add(encrypt_group)

        fs_types_group.tap do |group|
          type_rows.each_value { |row| group.add(row) }
        end

        encrypt_group.tap do |group|
          group.add(encrypt_switch)

          encrypt_switch.signal_connect('notify::active') { on_fs_type_changed }
        end
      end

      disable_unavailable_types
    end
  end

  # gdu_create_other_page_get_fs ().
  def fs_type = @fs_type

  def fs_type=(value)
    @fs_type = value
    notify('fs-type')
  end

  # gdu_create_other_page_is_encrypted ().
  def encrypted? = encrypt_switch.active?

  def complete = true

  def complete? = true

  private

    # can_format_cb (): the row, not its check button, is what goes
    # insensitive, so the whole row stops being activatable.
    def disable_unavailable_types
      type_rows.each do |fs_type, row|
        Utils.can_format(fs_type).then do |available, missing_util|
          unless available
            row.sensitive = false
            row.tooltip_text = "The utility #{missing_util} is missing."
          end
        end
      end
    end

    # on_fs_type_changed ().
    def on_fs_type_changed
      notify('complete')
    end

    # Memoized widget methods

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def fs_types_group
      @fs_types_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = 'Type'
      end
    end

    def type_rows
      @type_rows ||= TYPE_ROWS.to_h { |title, subtitle, fs_type| [fs_type, type_row(title, subtitle, fs_type)] }
    end

    def type_row(title, subtitle, fs_type)
      type_check_button(fs_type).then do |check_button|
        Adwaita::ActionRow.new.tap do |row|
          row.title = title
          row.subtitle = subtitle.to_s
          row.add_prefix(check_button)
          row.activatable_widget = check_button
        end
      end
    end

    def type_check_button(fs_type)
      Gtk::CheckButton.new.tap do |button|
        button.action_name = 'update_fs_type'
        button.action_target = GLib::Variant.new(fs_type)
      end
    end

    def encrypt_group = @encrypt_group ||= Adwaita::PreferencesGroup.new

    def encrypt_switch
      @encrypt_switch ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = 'Password Protect Volume'
        row.subtitle = 'Encrypts the volume using LUKS'
      end
    end
end
