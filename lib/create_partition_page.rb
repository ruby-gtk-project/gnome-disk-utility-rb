# frozen_string_literal: true

require 'adwaita'
require_relative 'enums'
require_relative 'utils'

# CreatePartitionPage is the first page of the create-partition wizard: how big
# the new partition should be, how much free space to leave after it, which
# unit the two spin rows count in, and — on an MS-DOS table that has no
# extended partition yet — whether to make this one extended.
#
# A port of upstream's src/resources/ui/gdu-create-partition-page.blp and
# src/disks/gdu-create-partition-page.c. Carried over faithfully:
#
#   * The Adw.Banner above the Adw.PreferencesPage, which reveals itself with
#     "This is the last primary partition that can be created." once three
#     primary partitions exist on a DOS table, and with "Cannot create a new
#     partition. There are already four primary partitions." once there are
#     four — the second one also blocks the page from completing.
#   * The Gtk.Scale and the "Partition Size" Adw.SpinRow sharing one
#     adjustment, and the "Free Space" row's adjustment counting down as the
#     size counts up, both capped at the same upper bound.
#   * Both spin rows' `output` handler, which rewrites the displayed text as
#     "%.2f <unit>" so the number carries its unit.
#   * The "Extended Partition" Adw.SwitchRow, hidden unless the table is "dos"
#     and has no extended partition yet, and the group around it following its
#     visibility.
#   * The "Units" Adw.ComboRow over the eleven unit names, starting at
#     gdu_utils_get_default_unit ()'s pick for the maximum size, and converting
#     the current value rather than resetting it when the unit changes.
#
# Two deliberate differences:
#
#   * Upstream takes a UDisksClient and a UDisksPartitionTable and asks them
#     for the table's type and its partitions. There is no libudisks binding
#     here, so the page takes the two plain values the three gdu_utils
#     partition helpers actually read — the table's Type string and a list of
#     Utils::PartitionInfo — which is the seam lib/utils.rb already uses.
#
#   * Upstream couples the size and free-space adjustments with
#     g_object_bind_property_full () and one transform used in both directions.
#     GLib::Object#bind_property in these bindings takes no transform, so the
#     two adjustments are coupled by their `value-changed` handlers, guarded
#     against re-entering each other. The arithmetic is upstream's
#     size_binding_func ().
#
class CreatePartitionPage < Adwaita::Bin
  type_register

  install_property(
    GLib::Param::Boolean.new(
      'complete',
      'complete',
      'Whether the page has everything it needs',
      false,
      GLib::Param::READABLE,
    ),
  )

  # create_partition_update ()'s two banner strings.
  DOS_ERROR_TITLE = 'Cannot create a new partition. There are already four primary partitions.'
  DOS_WARNING_TITLE = 'This is the last primary partition that can be created.'

  MAX_PRIMARY_DOS_PARTITIONS = 4

  # gtk_adjustment_configure ()'s step and page increments, as set_unit_num ()
  # passes them.
  STEP_INCREMENT = 1
  PAGE_INCREMENT = 100

  attr_reader :offset

  def initialize(partition_table_type:, partitions:, max_size:, offset:)
    super()

    @partition_table_type = partition_table_type
    @partitions = partitions
    @max_size = max_size
    @offset = offset
    @unit = nil
    @complete = false
    @coupling = false
  end

  def build
    tap do |page|
      page.child = page_box

      page_box.tap do |box|
        box.append(top_banner)
        box.append(preferences_page)

        preferences_page.tap do |prefs|
          prefs.add(scale_group)
          prefs.add(size_group)
          prefs.add(dos_extended_group)
          prefs.add(unit_group)

          scale_group.add(size_scale)

          size_group.tap do |group|
            group.add(size_row)
            group.add(free_space_row)

            size_row.signal_connect('output') { on_output(size_row) }
            free_space_row.signal_connect('output') { on_output(free_space_row) }
          end

          dos_extended_group.tap do |group|
            group.add(dos_extended_row)

            dos_extended_row.signal_connect('notify::active') { on_part_type_changed }
          end

          unit_group.tap do |group|
            group.add(size_unit_combo)

            size_unit_combo.signal_connect('notify::selected') { on_size_unit_changed }
          end
        end
      end

      size_adjustment.signal_connect('value-changed') { on_size_changed }
      free_following_adjustment.signal_connect('value-changed') { on_free_following_changed }

      dos_extended_row.bind_property(
        'visible',
        dos_extended_group,
        'visible',
        :default,
      )

      show_dos_extended_row
      set_unit(Utils.default_unit(@max_size))
      update
    end
  end

  # gdu_create_partition_page_is_extended ().
  def extended? = dos_extended_row.active?

  # gdu_create_partition_page_get_size ().
  def size = (size_adjustment.value * Enums::UnitSize.size_in_bytes(@unit)).to_i

  def complete = @complete

  def complete? = @complete

  private

    # The .blp's `visible: false` on the row, lifted by the constructor only
    # for a DOS table that has no extended partition yet.
    def show_dos_extended_row
      if dos_table? && !Utils.dos_extended?(@partitions)
        dos_extended_row.visible = true
      end
    end

    def dos_table? = @partition_table_type == 'dos'

    # create_partition_update ().
    def update
      dos_banner_title.then do |title|
        if title.nil?
          top_banner.revealed = false
        else
          top_banner.title = title
          top_banner.revealed = true
        end

        set_complete(size_adjustment.value.positive? && title != DOS_ERROR_TITLE)
      end
    end

    # The banner shows nothing unless this is a primary partition on a DOS
    # table and the table is at or one short of its four-primary limit.
    def dos_banner_title
      if dos_table? && !Utils.inside_dos_extended?(@partitions, @offset)
        primary_dos_banner_title(Utils.count_primary_dos_partitions(@partitions))
      end
    end

    def primary_dos_banner_title(num_primary)
      case num_primary
      when MAX_PRIMARY_DOS_PARTITIONS then DOS_ERROR_TITLE
      when MAX_PRIMARY_DOS_PARTITIONS - 1 then DOS_WARNING_TITLE
      end
    end

    def set_complete(value)
      @complete = value
      notify('complete')
    end

    # on_size_changed_cb ().
    def on_size_changed
      couple { free_following_adjustment.value = max_size_units - size_adjustment.value }
      update
    end

    # The other half of size_binding_func (), which upstream gets for free from
    # the bidirectional binding.
    def on_free_following_changed
      couple { size_adjustment.value = max_size_units - free_following_adjustment.value }
    end

    # The two handlers above each set the other adjustment's value, which would
    # call the other handler straight back.
    def couple
      unless @coupling
        @coupling = true

        begin
          yield
        ensure
          @coupling = false
        end
      end
    end

    # on_part_type_changed (): an extended partition has no filesystem page
    # after it, which the dialog works out from `complete` changing.
    def on_part_type_changed
      notify('complete')
    end

    # set_size_entry_unit_cb ().
    def on_output(spin_row)
      spin_row.text = format('%.2f %s', spin_row.adjustment.value, Enums::UnitSize.display_name(@unit))
      true
    end

    # on_size_unit_changed_cb ().
    def on_size_unit_changed
      set_unit(Enums::UnitSize.at(size_unit_combo.selected))
      update
    end

    # set_unit_num (): the value carries over into the new unit, and both
    # adjustments are reconfigured for it.
    def set_unit(unit)
      size_unit_combo.selected = Enums::UnitSize.index_of(unit)
      current_bytes.then do |bytes|
        @unit = unit

        configure_adjustment(size_adjustment, bytes / unit_size.to_f)
        configure_adjustment(free_following_adjustment, max_size_units - (bytes / unit_size.to_f))
      end
    end

    # Upstream's cur_unit_num of -1 — no unit picked yet — means the page
    # starts at the whole of the available space.
    def current_bytes
      if @unit.nil?
        @max_size
      else
        size_adjustment.value * unit_size
      end
    end

    def configure_adjustment(adjustment, value)
      adjustment.configure(
        value,
        0.0,
        max_size_units,
        STEP_INCREMENT,
        PAGE_INCREMENT,
        0.0,
      )
    end

    def unit_size = Enums::UnitSize.size_in_bytes(@unit)

    def max_size_units = @max_size / unit_size.to_f

    # Memoized widget methods

    def page_box = @page_box ||= Gtk::Box.new(:vertical, 0)

    def top_banner = @top_banner ||= Adwaita::Banner.new('')

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def scale_group = @scale_group ||= Adwaita::PreferencesGroup.new

    def size_scale = @size_scale ||= Gtk::Scale.new(:horizontal, size_adjustment)

    def size_group = @size_group ||= Adwaita::PreferencesGroup.new

    # The .blp's `upper: 100` is a placeholder the constructor replaces; the
    # step and page increments are the ones it declares.
    def size_adjustment
      @size_adjustment ||= Gtk::Adjustment.new(
        0,
        0,
        100,
        1,
        10,
        0,
      )
    end

    def free_following_adjustment
      @free_following_adjustment ||= Gtk::Adjustment.new(
        0,
        0,
        100,
        1,
        10,
        0,
      )
    end

    def size_row
      @size_row ||= Adwaita::SpinRow.new(size_adjustment, 1, 0).tap do |row|
        row.title = 'Partition Size'
      end
    end

    def free_space_row
      @free_space_row ||= Adwaita::SpinRow.new(free_following_adjustment, 1, 0).tap do |row|
        row.title = 'Free Space'
        row.subtitle = 'Space following new partition'
      end
    end

    def dos_extended_group
      @dos_extended_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.visible = false
      end
    end

    def dos_extended_row
      @dos_extended_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = 'Extended Partition'
        row.subtitle = 'Extended Partitions can contain Logical Partitions'
        row.visible = false
      end
    end

    def unit_group = @unit_group ||= Adwaita::PreferencesGroup.new

    def size_unit_combo
      @size_unit_combo ||= Adwaita::ComboRow.new.tap do |row|
        row.title = 'Units'
        row.model = unit_model
      end
    end

    def unit_model
      @unit_model ||= Gtk::StringList.new(Enums::UnitSize::ORDER.map { |unit| Enums::UnitSize.display_name(unit) })
    end
end
