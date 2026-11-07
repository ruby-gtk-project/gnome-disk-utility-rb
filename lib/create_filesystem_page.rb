# frozen_string_literal: true

require 'adwaita'
require_relative 'utils'

# CreateFilesystemPage is the wizard page that names the new volume and picks
# what to put on it: Ext4, NTFS, FAT, or "Other", with the option to overwrite
# the existing data first and to put the whole thing inside LUKS.
#
# A port of upstream's src/resources/ui/gdu-create-filesystem-page.blp and
# src/disks/gdu-create-filesystem-page.c. Carried over faithfully:
#
#   * The "_Volume Name" Adw.EntryRow, whose `apply` truncates the text to the
#     filesystem's maximum label length — 11 bytes on FAT, 15 on exFAT, no
#     limit elsewhere — and which is re-truncated whenever the type changes.
#   * The "_Overwrite Existing Data" row: a Gtk.Switch suffix, and before it a
#     flat "help-about-symbolic" MenuButton whose popover carries the warning
#     that the option slows formatting down.
#   * The four type rows under "Type", each with a Gtk.CheckButton prefix bound
#     to the page's own `update_fs_type` property action with the type's name
#     as its target, which is what makes the four behave as one radio group.
#   * The "_Password Protect Volume" Adw.SwitchRow, sensitive only while Ext4
#     is selected, with its own notify::active folded into the type change.
#   * The constructor's defaults: FAT on a removable flash drive, on anything
#     removable under 20 GB, or wherever NTFS is unavailable; NTFS on the other
#     removable drives; and Ext4 — the property's own default — otherwise. A
#     type whose mkfs the daemon cannot run has its row made insensitive with
#     "The utility %s is missing." as the tooltip.
#
# Three deliberate differences:
#
#   * Upstream's `fs-type` is a GduFsType enum property whose value nicks are
#     "ext4", "ntfs", "vfat" and "other". Registering an enum GType from Ruby
#     to carry four strings buys nothing, so the property is the nick itself —
#     which is what gdu_create_filesystem_page_get_fs () returns, and what the
#     check buttons' action targets already are.
#
#   * Upstream takes a UDisksClient and a UDisksDrive. There is no libudisks
#     binding here, so the page takes the three Drive properties the
#     constructor reads — Removable, MediaCompatibility and Size — and asks the
#     UDisks Manager about mkfs availability through Utils.can_format.
#
#   * `complete` is a property that is always true, as upstream's is, so the
#     dialog can connect notify::complete to the same place on every page.
#
class CreateFilesystemPage < Adwaita::Bin
  type_register

  EXT4 = 'ext4'
  NTFS = 'ntfs'
  FAT = 'vfat'
  OTHER = 'other'

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
      EXT4,
      GLib::Param::READABLE | GLib::Param::WRITABLE,
    ),
  )

  install_property_action('update_fs_type', 'fs-type')

  # The size below which a removable drive is assumed to be a flash card and
  # formatted FAT.
  FLASH_CARD_MAX_SIZE = 20 * 1000 * 1000 * 1000

  ERASE_ZERO = 'zero'

  OVERWRITE_INFO_TEXT = 'Ensures that existing data cannot be recovered. This option slows down formatting.'

  # The four rows under "Type", in the .blp's order: title, subtitle, type.
  TYPE_ROWS = [
    ['E_xt4', 'For use only with Linux systems', EXT4],
    ['N_TFS', 'For use with Windows', NTFS],
    ['_FAT', 'For use with all systems and devices', FAT],
    ['Ot_her', nil, OTHER],
  ].freeze

  def initialize(removable: false, media_compatibility: [], drive_size: 0)
    super()

    @removable = removable
    @media_compatibility = media_compatibility
    @drive_size = drive_size
    @fs_type = EXT4
  end

  def build
    tap do |page|
      page.child = preferences_page

      preferences_page.tap do |prefs|
        prefs.add(name_group)
        prefs.add(erase_group)
        prefs.add(type_group)
        prefs.add(encrypt_group)

        name_group.tap do |group|
          group.add(name_entry)

          name_entry.signal_connect('apply') { on_fs_name_changed }
        end

        erase_group.tap do |group|
          group.add(erase_row)

          erase_row.tap do |row|
            row.add_suffix(overwrite_info_button)
            row.add_suffix(erase_switch)
            row.activatable_widget = erase_switch

            overwrite_info_button.popover = overwrite_info_popover
          end
        end

        type_group.tap do |group|
          type_rows.each { |row| group.add(row) }
        end

        encrypt_group.tap do |group|
          group.add(encrypt_switch)

          encrypt_switch.signal_connect('notify::active') { on_fs_type_changed }
        end
      end

      ext4_check_button.bind_property(
        'active',
        encrypt_switch,
        'sensitive',
        :default,
      )
      encrypt_switch.sensitive = ext4_check_button.active?

      page.signal_connect('notify::fs-type') { on_fs_type_changed }

      apply_defaults
      disable_unavailable_types
    end
  end

  # gdu_create_filesystem_page_get_name ().
  def name = name_entry.text

  # gdu_create_filesystem_page_get_fs ().
  def fs_type = @fs_type

  def fs_type=(value)
    @fs_type = value
    notify('fs-type')
  end

  # gdu_create_filesystem_page_is_other ().
  def other? = @fs_type == OTHER

  # gdu_create_filesystem_page_is_encrypted ().
  def encrypted? = ext4_check_button.active? && encrypt_switch.active?

  # gdu_create_filesystem_page_get_erase (). Upstream's comment notes that
  # "ata-secure-erase" and "ata-secure-erase-enhanced" are still to come.
  def erase
    if erase_switch.active?
      ERASE_ZERO
    end
  end

  def complete = true

  def complete? = true

  private

    # The removable-drive defaults in gdu_create_filesystem_page_new ().
    def apply_defaults
      if @removable
        self.fs_type = default_removable_fs_type
      end
    end

    def default_removable_fs_type
      if Utils.can_format?(FAT) && (flash_card? || !Utils.can_format?(NTFS))
        FAT
      elsif Utils.can_format?(NTFS)
        NTFS
      else
        @fs_type
      end
    end

    def flash_card? = Utils.flash?(@media_compatibility) || @drive_size < FLASH_CARD_MAX_SIZE

    # The two gdu_utils_can_format () checks the constructor makes. Ext4 and
    # "Other" are never disabled here — "Other" has a page of its own that
    # checks each of its types.
    #
    # All four check buttons are bound, via action_name, to the one shared
    # `update_fs_type` property action (that is what makes them act as a
    # single radio group). GTK syncs a GtkActionable's `sensitive` from its
    # bound action's `enabled` the moment the widget is mapped, and that
    # action's `enabled` is always true — it is one action covering four
    # targets, not a per-row flag — which clobbers a manual
    # `sensitive = false` set here as soon as the row is actually shown in a
    # window. Reapplying on `map` (fired after GTK's own sync, since map
    # handlers run bottom-up after the widget is mapped) keeps the row
    # disabled where upstream's gdu_create_filesystem_page_new disables each
    # row independently and permanently.
    def disable_unavailable_types
      { NTFS => ntfs_check_button, FAT => fat_check_button }.each do |fs_type, check_button|
        Utils.can_format(fs_type).then do |available, missing_util|
          unless available
            disable_check_button(check_button, missing_util)
          end
        end
      end
    end

    def disable_check_button(check_button, missing_util)
      apply = lambda do
        check_button.sensitive = false
        check_button.tooltip_text = "The utility #{missing_util} is missing."
      end
      apply.call
      check_button.signal_connect('map') { apply.call }
    end

    # on_fs_name_changed ().
    def on_fs_name_changed
      update_text_entry
    end

    # on_fs_type_changed ().
    def on_fs_type_changed
      update_text_entry
      notify('complete')
    end

    # update_text_entry (). g_string_truncate () counts bytes, and so does the
    # limit it is given; #scrub drops the partial character a cut in the middle
    # of a multi-byte sequence would otherwise leave behind.
    def update_text_entry
      Utils.max_label_length(@fs_type).then do |max_length|
        unless max_length.nil?
          name_entry.text = name_entry.text.byteslice(0, max_length).to_s.scrub('')
        end
      end
    end

    # Memoized widget methods

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def name_group = @name_group ||= Adwaita::PreferencesGroup.new

    def name_entry
      @name_entry ||= Adwaita::EntryRow.new.tap do |row|
        row.title = '_Volume Name'
        row.use_underline = true
      end
    end

    def erase_group = @erase_group ||= Adwaita::PreferencesGroup.new

    def erase_row
      @erase_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = '_Overwrite Existing Data'
        row.use_underline = true
      end
    end

    def overwrite_info_button
      @overwrite_info_button ||= Gtk::MenuButton.new.tap do |button|
        button.tooltip_text = 'More Information'
        button.icon_name = 'help-about-symbolic'
        button.valign = :center
        button.add_css_class('flat')
      end
    end

    def overwrite_info_popover
      @overwrite_info_popover ||= Gtk::Popover.new.tap do |popover|
        popover.child = overwrite_info_label
      end
    end

    def overwrite_info_label
      @overwrite_info_label ||= Gtk::Label.new(OVERWRITE_INFO_TEXT).tap do |label|
        label.halign = :center
        label.valign = :center
        label.margin_start = 6
        label.margin_end = 6
        label.margin_top = 6
        label.margin_bottom = 6
        label.wrap = true
        label.max_width_chars = 50
      end
    end

    def erase_switch
      @erase_switch ||= Gtk::Switch.new.tap do |switch|
        switch.valign = :center
      end
    end

    def type_group
      @type_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = 'Type'
      end
    end

    def type_rows
      @type_rows ||= TYPE_ROWS.map { |title, subtitle, fs_type| type_row(title, subtitle, check_buttons[fs_type]) }
    end

    def type_row(title, subtitle, check_button)
      Adwaita::ActionRow.new.tap do |row|
        row.title = title
        row.subtitle = subtitle.to_s
        row.use_underline = true
        row.add_prefix(check_button)
        row.activatable_widget = check_button
      end
    end

    def check_buttons
      @check_buttons ||= TYPE_ROWS.to_h { |_title, _subtitle, fs_type| [fs_type, type_check_button(fs_type)] }
    end

    def type_check_button(fs_type)
      Gtk::CheckButton.new.tap do |button|
        button.action_name = 'update_fs_type'
        button.action_target = GLib::Variant.new(fs_type)
      end
    end

    def ext4_check_button = check_buttons.fetch(EXT4)
    def ntfs_check_button = check_buttons.fetch(NTFS)
    def fat_check_button = check_buttons.fetch(FAT)

    def encrypt_group = @encrypt_group ||= Adwaita::PreferencesGroup.new

    def encrypt_switch
      @encrypt_switch ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = '_Password Protect Volume'
        row.subtitle = 'Encrypts the volume using LUKS'
        row.use_underline = true
      end
    end
end
