# frozen_string_literal: true

require 'adwaita'
require 'gio2'
require 'udisks'
require_relative 'item'
require_relative 'enums'
require_relative 'utils'

# Block represents a portion of a drive: a partition, or a sized span of a
# drive with no partition table ("the whole device"), or a run of unused
# space between partitions.
#
# Ported from upstream's src/disks/gdu-block.c. Upstream distinguishes a real
# UDisksObject-backed block from a synthetic free-space span by whether
# `self->block` is set; this port keeps the same distinction by whether
# `@object` is nil.
#
class Block < Item
  type_register

  attr_reader :client, :object, :parent_item, :start_offset

  # Drive#color_block sets this (by instance_variable_set, not through this
  # writer) once it has decided which of the eight partition colours this
  # block gets. SpaceAllocationBar#allocate_child reads it back to add the
  # matching CSS class to the block's segment; with no reader at all, every
  # drive with at least one partition crashed the space allocation bar the
  # first time it tried to lay itself out.
  attr_accessor :color

  # gdu_block_new (): a block backed by a real UDisksObject (a partition, or a
  # drive-less device's own Block interface).
  def self.new_for_object(client, object, parent = nil)
    new.tap do |block|
      block.send(:setup_object, client, object, parent)
    end
  end

  # gdu_block_sized_new (): a synthetic free-space span with no UDisksObject.
  def self.new_sized(client, start_offset, size, parent = nil)
    new.tap do |block|
      block.send(:setup_sized, client, start_offset, size, parent)
    end
  end

  def initialize
    super()
    @start_offset = 0
    @size = 0
  end

  # --- The Item vtable ------------------------------------------------------

  # gdu_block_get_description ().
  def description
    @description ||= if free_space?
                        "#{Utils.format_size(size)} Free Space".strip
                      elsif extended?
                        'Extended Partition'
                      else
                        label_or_type_description
                      end
  end

  # gdu_block_get_partition_type ().
  def partition_type
    @partition_type ||= object.nil? ? 'Free Space' : object_partition_type
  end

  # gdu_block_get_icon (). Upstream has no block-specific icon; it falls back
  # to a generic drive-harddisk icon the way the row widgets do.
  def icon = Gio::ThemedIcon.new('drive-harddisk-symbolic')

  def parent = parent_item

  def size = @size

  # --- Plain getters --------------------------------------------------------

  def offset = start_offset

  # gdu_block_get_number (): the partition number, or 0 for a free-space span
  # or a drive-less device's own block.
  def number = partition&.number || 0

  def unused_size
    mount_point = Array(block&.mount_points).first
    (Utils.total_size_for_mount_point(mount_point) - Utils.unused_for_mount_point(mount_point)).then do |used|
      if used.negative?
        0
      else
        size - used
      end
    end
  end

  # gdu_block_is_extended (): a DOS extended partition.
  def extended? = !partition.nil? && partition.container?

  def size_str = Utils.format_size(size)

  def uuid = block&.id_uuid

  def device_id = block&.device

  def fs_label = block&.id_label

  def fs_type = block&.id_type

  def mount_points = Array(file_system&.mount_points)

  def needs_unmount? = !mount_points.empty?

  # gdu_block_set_fs_label_async (): UDisksFilesystem.SetLabel (sa{sv}).
  def set_fs_label_async(label, &callback)
    if file_system
      file_system.call_set_label(label, {}) do |_proxy, result|
        callback&.call(set_fs_label_finish(result))
      end
    else
      callback&.call([false, 'Device has no filesystem interface'])
    end
  end

  def set_fs_label_finish(result)
    file_system.call_set_label_finish(result)
    [true, nil]
  rescue StandardError => e
    [false, e.message]
  end

  # --- Features --------------------------------------------------------------

  # gdu_block_get_features (), the subset that does not need the drive this
  # block belongs to (Drive computes the CREATE_PARTITION bit that decides
  # whether a free-space span is colored "grey" and offers formatting).
  def features
    @features ||= compute_features
  end

  # --- Matching, used by Drive#matches_object and Manager --------------------

  def matches_object?(udisks_object) = !object.nil? && object.object_path == udisks_object.object_path

  def free_space? = object.nil?

  private

    def setup_object(client, object, parent)
      @client = client
      @object = object
      @parent_item = parent
      @start_offset = partition&.offset || 0
      @size = block&.size || 0
    end

    def setup_sized(client, start_offset, size, parent)
      @client = client
      @object = nil
      @parent_item = parent
      @start_offset = start_offset
      @size = size
    end

    def block = object&.block

    def partition = object&.partition

    def file_system = object&.filesystem

    def label_or_type_description
      if fs_label && !fs_label.empty?
        fs_label
      else
        id = client.get_id_for_display(block&.id_usage, block&.id_type, block&.id_version, false)
        "#{Utils.format_size(size)} #{id}".strip
      end
    end

    def object_partition_type
      if partition.nil?
        id = client.get_id_for_display(block&.id_usage, block&.id_type, block&.id_version, true)
        id.nil? || id.empty? ? Item::UNKNOWN : id
      else
        table = client.get_partition_table(partition)
        client.get_partition_type_for_display(table&.type, partition.type)
      end
    end

    def compute_features
      return Enums::Feature::NONE if free_space?

      features = Enums::Feature::NONE
      features |= Enums::Feature::EDIT_PARTITION | Enums::Feature::DELETE_PARTITION unless partition.nil?
      features |= Enums::Feature::EDIT_LABEL if block && !block.read_only?
      features |= Enums::Feature::CAN_MOUNT | Enums::Feature::CAN_UNMOUNT if file_system
      features |= Enums::Feature::CHECK_FILESYSTEM | Enums::Feature::REPAIR_FILESYSTEM if file_system
      features
    end
end
