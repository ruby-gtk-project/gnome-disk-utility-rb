# frozen_string_literal: true

require 'adwaita'
require 'gio2'
require 'udisks'
require_relative 'drive'
require_relative 'block'
require_relative 'utils'

# Manager is the top-level model: it owns the UDisksClient, watches its
# ObjectManager for devices appearing and disappearing, and keeps #drives — a
# Gio::ListStore of Drive — in sync with the bus.
#
# Ported from upstream's src/disks/gdu-manager.c. Upstream is a process-wide
# singleton behind gdu_manager_get_default (); this port keeps that shape as
# .default, since App and every dialog that opens a drive share one
# UDisksClient and one drives model.
#
# gdu_manager_open_loop_async () (UDisksManager.LoopSetup, attaching a disk
# image as a loop device) is not ported this round: nothing in this round's
# component list calls it yet (AttachDiskImageDialog and
# RestoreDiskImageDialog, upstream's only two callers, are not ported either),
# and its `h` (file descriptor) argument needs a GUnixFDList side-channel this
# port has not proven against a running udisksd.
#
class Manager
  class << self
    # gdu_manager_get_default (). Raises the UDisks::Client's own error when
    # the bus cannot be reached, same as upstream's udisks_client_new_sync
    # handing back a GError.
    def default
      @default ||= new
    end
  end

  attr_reader :client, :drives

  def initialize(client: UDisks::Client.new)
    @client = client
    @drives = Gio::ListStore.new(Item)
    load_drives
  end

  private

    # Copied from upstream's src/disks/gdudevicetreemodel.c (and kept in sync
    # with src/disks/restore_disk_image_dialog.rs, which re-implements it).
    def should_include_block?(object)
      block = object.block
      loop = object.loop

      return false if block.nil?
      return false if Utils.userspace_mount_option?(block.userspace_mount_options, 'x-gdu.hide')

      device = block.device.to_s
      return false if device.start_with?('/dev/ram', '/dev/zram')

      return false if block.size.zero? && loop

      return false unless object.partition.nil?

      return false unless block.drive.to_s == '/'

      block.crypto_backing_device.to_s == '/'
    end

    def drive_in_manager(object)
      n_items.times.find { |i| @drives.get_item(i).matches_object?(object) }
    end

    def n_items = @drives.n_items

    def manager_get_object_drive(object)
      drive = object_manager_drive_cache[object.object_path]
      return drive if drive

      block = object.block
      if block
        udrive = client.get_drive_for_block(block)
        found = udrive && object_manager_drive_cache[udrive.object&.object_path]
        return found if found
      end

      n_items.times.each { |i| @drives.get_item(i).then { |d| return d if d.matches_object?(object) } }

      nil
    end

    def object_manager_drive_cache = @object_manager_drive_cache ||= {}

    def manager_add_drive(object)
      udrive = object.drive
      block = object.block

      return unless udrive || (block && should_include_block?(object))

      drive = Drive.new_for_object(client, object, nil)
      object_manager_drive_cache[object.object_path] = drive

      position = @drives.n_items.times.find { |i| compare_drive_path(drive, @drives.get_item(i)) < 0 } || @drives.n_items
      @drives.insert(position, drive)
    end

    def compare_drive_path(drive_a, drive_b)
      a_has_drive = !drive_a.object.drive.nil?
      b_has_drive = !drive_b.object.drive.nil?
      if a_has_drive && !b_has_drive
        -1
      elsif b_has_drive && !a_has_drive
        1
      else
        drive_a.object.object_path.to_s <=> drive_b.object.object_path.to_s
      end
    end

    def manager_remove_drive(object)
      position = drive_in_manager(object)
      return if position.nil?

      object_manager_drive_cache.delete(object.object_path)
      @drives.remove(position)
    end

    def object_added(object)
      drive = manager_get_object_drive(object)
      if drive && object.partition_table && object.block
        drive.changed
      elsif drive && object.block
        drive.block_changed(object)
      end

      manager_add_drive(object) if drive.nil?
    end

    def object_removed(object)
      manager_remove_drive(object) if object.drive || object.loop || object_manager_drive_cache.key?(object.object_path)
    end

    def interface_removed(object, _interface)
      if object_manager_drive_cache.key?(object.object_path)
        manager_remove_drive(object)
      else
        manager_get_object_drive(object)&.changed
      end
    end

    # manager_load_drives (): subscribe to the ObjectManager and seed #drives
    # from whatever is already on the bus.
    def load_drives
      object_manager = client.object_manager
      return if object_manager.nil?

      object_manager.signal_connect('object-added') { |_om, object| object_added(object) }
      object_manager.signal_connect('object-removed') { |_om, object| object_removed(object) }
      object_manager.signal_connect('interface-added') { |_om, object, _iface| object_added(object) }
      object_manager.signal_connect('interface-removed') { |_om, object, iface| interface_removed(object, iface) }

      Array(object_manager.objects).sort_by { |object| object.drive.nil? ? 1 : 0 }.each { |object| object_added(object) }
    end
end
