# frozen_string_literal: true

require 'adwaita'
require 'gio2'
require 'udisks'
require_relative 'item'
require_relative 'block'
require_relative 'enums'
require_relative 'utils'

# Drive represents one row in the sidebar: a physical drive, a loop device, or
# (for devices UDisks exposes with no separate Drive object) the block device
# itself. Its partitions model is what DriveView's volume grid shows.
#
# Ported from upstream's src/disks/gdu-drive.c.
#
# Two scope reductions from upstream, both because their upstream
# dependencies are not ported yet:
#
#   * #features never sets GDU_FEATURE_SMART or GDU_FEATURE_SETTINGS — those
#     bits come from AtaSmartDialog's one-liner assessment and
#     DiskSettingsDialog's "should show" check, neither of which exists in
#     this port yet. Adding them here ahead of those dialogs would wire a
#     menu entry to a dialog that cannot open.
#
#   * The power/eject/detach actions (standby, wakeup, eject, power off,
#     detach) are left out of this round entirely, rather than ported
#     half-tested — see the port's `remaining` list.
#
PARTITION_COLORS = %w[blue green yellow orange red purple brown].freeze

class Drive < Item
  type_register

  attr_reader :client, :object

  def self.new_for_object(client, object, parent = nil)
    new.tap do |drive|
      drive.send(:setup, client, object, parent)
      drive.changed
    end
  end

  def initialize
    super()
    @partitions = Gio::ListStore.new(Item)
    @partition_color_index = 0
  end

  # --- The Item vtable --------------------------------------------------

  def description = info&.description || UNKNOWN

  def partition_type
    if partition_table_object
      table = partition_table_object.partition_table
      client.get_partition_table_type_for_display(table&.type)
    else
      UNKNOWN
    end
  end

  def icon = info&.icon || Gio::ThemedIcon.new('drive-harddisk-symbolic')

  def parent = @parent

  def size
    if udrive && udrive.size.positive?
      udrive.size
    elsif block
      block.size
    else
      0
    end
  end

  def partitions = @partitions

  def features
    @features ||= compute_features
  end

  # gdu_drive_changed (): rebuild #block, #udrive and the partitions model from
  # the current state of @object on the bus.
  def changed
    refresh_description_source
    refresh_block_and_drive
    refresh_partitions
    emit_changed
  end

  # --- Plain getters ------------------------------------------------------

  def name = info&.name || UNKNOWN

  def model
    return @model if @model

    @model = if udrive.nil?
               'Loop Device'
             else
               model_from_udrive
             end
  end

  def serial = udrive&.serial || UNKNOWN

  # gdu_drive_get_object_for_format (): the partition-table object when the
  # drive has one, else the drive's own object — what DriveHeader's
  # "Format Disk…"/"Create Disk Image…" actions and FormatVolumeDialog hand
  # UDisks.
  def object_for_format = partition_table_object || object

  # gdu_drive_get_siblings (): the UDisksObjects for this drive's siblings.
  def siblings
    return [] if udrive.nil?

    Array(client.get_drive_siblings(udrive)).filter_map(&:object)
  end

  # --- Matching, used by Manager --------------------------------------------

  def matches_object?(udisks_object)
    (object && object.object_path == udisks_object.object_path) ||
      (block && udisks_object.block&.equal?(block)) ||
      (udrive && udisks_object.drive&.equal?(udrive)) ||
      partition_items.any? { |item| item.respond_to?(:matches_object?) && item.matches_object?(udisks_object) }
  end

  # gdu_drive_block_changed (): the object's Block interface changed (e.g. its
  # filesystem was mounted/unmounted); refresh without re-deriving identity.
  def block_changed(_udisks_object) = changed

  private

    UNKNOWN = Item::UNKNOWN

    def setup(client, object, parent)
      @client = client
      @object = object
      @parent = parent
    end

    def info = @info

    def refresh_description_source
      @info = client.get_object_info(object)
    end

    def refresh_block_and_drive
      @block = object.block
      if @block
        @udrive = client.get_drive_for_block(@block)
      else
        @udrive = object.drive
        drive_block = @udrive && client.get_block_for_drive(@udrive, false)
        @block = drive_block
        @block_object = drive_block&.object
      end
      @block_object ||= @block && object
    end

    def block = @block

    def udrive = @udrive

    def block_object = @block_object

    def partition_table_object
      return @partition_table_object if defined?(@partition_table_object) && @partition_table_object

      @partition_table_object = block_object&.partition_table ? block_object : nil
    end

    def model_from_udrive
      vendor = udrive.vendor
      model = udrive.model
      base = if vendor.nil? || vendor.empty?
               model.to_s
             elsif model.nil? || model.empty?
               vendor
             else
               "#{vendor} #{model}"
             end
      revision = udrive.revision
      revision && !revision.empty? ? "#{base} (#{revision})" : base
    end

    def refresh_partitions
      @partition_color_index = 0
      @partitions.remove_all

      return if size.zero? || block_object.nil?

      if partition_table_object
        load_partition_table(partition_table_object)
      else
        load_no_partitioning(block_object)
      end
    end

    # gdu_drive_set_no_partitioning (): one block spanning the whole device.
    def load_no_partitioning(object)
      partition = if udrive.nil?
                    Block.new_for_object(client, object, self)
                  else
                    Block.new_sized(client, 0, size, self)
                  end
      color_block(partition)
      @partitions.append(partition)
      add_decrypted(object, partition) if object.encrypted
    end

    # gdu_drive_set_child (), minus the free-space-gap bookkeeping, which this
    # scoped-down port leaves for a later round — see the class comment.
    def load_partition_table(table_object)
      partitions = Array(client.get_partitions(table_object.partition_table))
      partitions.sort_by!(&:offset)

      partitions.each do |upartition|
        # g_dbus_interface_get_object (): the UDisksObject this partition
        # interface proxy belongs to.
        object = upartition.object
        next if object.nil?

        block = Block.new_for_object(client, object, self)
        color_block(block)
        @partitions.append(block)
        add_decrypted(object, block) if object.encrypted
      end
    end

    def add_decrypted(object, parent)
      cleartext = client.get_cleartext_block(object.block)
      return if cleartext.nil?

      cleartext_object = cleartext.object
      return if cleartext_object.nil?

      decrypted = Block.new_for_object(client, cleartext_object, parent)
      color_block(decrypted)
      @partitions.append(decrypted)
    end

    def color_block(block)
      color = if Enums::Flags.set?(block.features, Enums::Feature::CREATE_PARTITION)
                'grey'
              else
                PARTITION_COLORS[@partition_color_index % PARTITION_COLORS.size].tap { @partition_color_index += 1 }
              end
      block.instance_variable_set(:@color, color)
    end

    def compute_features
      features = Enums::Feature::NONE
      features |= eject_and_power_features
      features |= Enums::Feature::DETACH if object.loop
      features |= image_and_partition_features
      features
    end

    def eject_and_power_features
      features = Enums::Feature::NONE
      return features if udrive.nil?

      features |= Enums::Feature::EJECT if udrive.ejectable? && udrive.media_removable?
      features |= Enums::Feature::POWEROFF if udrive.can_power_off?
      features
    end

    def image_and_partition_features
      return Enums::Feature::NONE if block.nil?

      features = Enums::Feature::NONE
      drive_for_block = client.get_drive_for_block(block)
      includeable = block.size.positive? || (drive_for_block && !drive_for_block.media_change_detected?)
      return features unless includeable

      features |= Enums::Feature::CREATE_IMAGE | Enums::Feature::BENCHMARK
      unless block.read_only?
        features |= Enums::Feature::RESTORE_IMAGE | Enums::Feature::CREATE_PARTITION
        features |= Enums::Feature::FORMAT if block.hint_partitionable?
      end
      features
    end
end
