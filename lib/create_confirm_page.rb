# frozen_string_literal: true

require 'adwaita'
require_relative 'utils'

# CreateConfirmPage is the wizard's last page: the device about to be written
# to, spelled out, behind a banner warning that its contents will be lost.
#
# A port of upstream's src/resources/ui/gdu-create-confirm-page.blp and
# src/disks/gdu-create-confirm-page.c. Carried over faithfully:
#
#   * The always-revealed Adw.Banner titled "Warning: All the data on the
#     volume will be lost", and the "Confirm the details of the current volume
#     before proceeding." label under it.
#   * The four "property"-styled Adw.ActionRows — Device, Volume, Used and
#     Location — and the 400px width request on the page.
#   * The Device row's "<description> — <name>" subtitle, whose em dash
#     upstream flags for translators as the one part that may need changing.
#   * The Volume row falling back to the filesystem's type when the volume has
#     no label.
#   * The Used row staying hidden unless the filesystem is mounted and its
#     unused space can be read, in which case it shows "<used> (<percent>%)"
#     with the percentage to one decimal place.
#   * `complete` being a property that is always true, so the dialog can
#     connect notify::complete to the same place on every page.
#
# Upstream takes a UDisksClient, a UDisksObject and a UDisksBlock and reads
# five things off them. There is no libudisks binding here, so the page takes
# those five plain values: the object info's description and name, the block's
# IdLabel, IdType, PreferredDevice and Size, and the unused space
# gdu_utils_get_unused_for_block () works out — which Utils computes from the
# filesystem's first mount point.
#
class CreateConfirmPage < Adwaita::Bin
  type_register

  install_property(
    GLib::Param::Boolean.new(
      'complete',
      'complete',
      'Whether the page has everything it needs',
      true,
      GLib::Param::READABLE,
    ),
  )

  WIDTH_REQUEST = 400

  BANNER_TITLE = 'Warning: All the data on the volume will be lost'
  EXPLANATION = 'Confirm the details of the current volume before proceeding.'

  def initialize(
    description:,
    name:,
    id_label:,
    id_type:,
    preferred_device:,
    size:,
    unused_space: -1
  )
    super()

    @description = description
    @name = name
    @id_label = id_label
    @id_type = id_type
    @preferred_device = preferred_device
    @size = size
    @unused_space = unused_space

    self.width_request = WIDTH_REQUEST
  end

  def build
    tap do |page|
      page.child = preferences_page

      preferences_page.tap do |prefs|
        prefs.add(warning_group)
        prefs.add(details_group)

        warning_group.tap do |group|
          group.add(warning_banner)
          group.add(explanation_label)
        end

        details_group.tap do |group|
          group.add(device_row)
          group.add(volume_row)
          group.add(usage_row)
          group.add(location_row)
        end
      end

      set_device_name
      set_volume_label
      set_usage
      set_location
    end
  end

  def complete = true

  def complete? = true

  private

    # gdu_create_confirm_page_set_device_name (). Upstream's example of what
    # the two UDisks strings look like together is
    # "Partition 1 of 32 GB Flash Disk — /dev/sdb1".
    def set_device_name
      device_row.subtitle = "#{@description} — #{@name}"
    end

    # gdu_create_confirm_page_set_volume_label ().
    def set_volume_label
      if @id_label.to_s.empty?
        volume_row.subtitle = @id_type.to_s
      else
        volume_row.subtitle = @id_label
      end
    end

    # gdu_create_confirm_page_set_location ().
    def set_location
      location_row.subtitle = @preferred_device.to_s
    end

    # gdu_create_confirm_page_set_usage (): nothing is shown unless the unused
    # space came back positive, which it only does for a mounted filesystem.
    def set_usage
      if @unused_space.to_i.positive?
        usage_row.visible = true
        usage_row.subtitle = usage_subtitle(@size - @unused_space)
      end
    end

    def usage_subtitle(used)
      format('%<used>s (%<percent>.1f%%)', used: GLib.format_size(used), percent: 100.0 * used / @size)
    end

    # Memoized widget methods

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def warning_group = @warning_group ||= Adwaita::PreferencesGroup.new

    def warning_banner
      @warning_banner ||= Adwaita::Banner.new(BANNER_TITLE).tap do |banner|
        banner.revealed = true
      end
    end

    def explanation_label
      @explanation_label ||= Gtk::Label.new(EXPLANATION).tap do |label|
        label.margin_top = 6
      end
    end

    def details_group = @details_group ||= Adwaita::PreferencesGroup.new

    def device_row
      @device_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Device'
        row.add_css_class('property')
      end
    end

    def volume_row
      @volume_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Volume'
        row.add_css_class('property')
      end
    end

    def usage_row
      @usage_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Used'
        row.visible = false
        row.add_css_class('property')
      end
    end

    def location_row
      @location_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = 'Location'
        row.add_css_class('property')
      end
    end
end
