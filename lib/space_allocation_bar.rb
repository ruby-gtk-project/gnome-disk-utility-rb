# frozen_string_literal: true

require 'adwaita'
require_relative 'style'

# SpaceAllocationBar is the horizontal bar at the top of the drive view that
# shows how a drive's space is divided between its partitions.
#
# A port of upstream's src/disks/gdu-space-allocation-bar.c. It is a bare
# GtkWidget with its own measure and size_allocate: one child per partition,
# each an Adw.Bin carrying the "partition-bin" class plus that partition's
# colour class, allocated at the offset and width its partition occupies on the
# disk. Everything else — the 25px height request, the hidden overflow that
# clips the children to the bar's rounded corners, the "space-allocation-bar"
# class that rounds them, the 128KB added to each width to absorb rounding, and
# rebuilding on the partition model's items-changed — is upstream's.
#
# The one carried-over quirk: upstream's update_space_allocation_bar creates its
# bins inside `for (i = 0; i < n_items; i++)` without using `i`, so the bins are
# colourless and sizeless until size_allocate runs. That is kept, because
# size_allocate is where the colour class is added.
#
class SpaceAllocationBar < Gtk::Widget
  type_register

  HEIGHT_REQUEST = 25

  # "Add 128KB to the size to account for floating point errors".
  SIZE_SLACK = 128 * 1024

  attr_reader :drive

  def initialize
    super()

    @drive = nil
    @partitions_handler = nil

    set_size_request(-1, HEIGHT_REQUEST)
    self.overflow = :hidden
    add_css_class('space-allocation-bar')
  end

  # gdu_space_allocation_bar_set_drive ().
  def drive=(drive)
    unless @drive == drive
      disconnect_partitions
      @drive = drive
      connect_partitions
      update
    end
  end

  # gdu_space_allocation_bar_measure (): the bar is as big as its biggest child
  # in either direction, because the children are positioned by transform
  # rather than stacked.
  def virtual_do_measure(orientation, for_size)
    minimum = 0
    natural = 0

    children.each do |child|
      child_minimum, child_natural, = child.measure(orientation, for_size)
      minimum = [minimum, child_minimum].max
      natural = [natural, child_natural].max
    end

    [minimum, natural, -1, -1]
  end

  # gdu_space_allocation_bar_size_allocate ().
  def virtual_do_size_allocate(width, height, baseline)
    total_size = drive_size

    if total_size.positive?
      allocate_children(
        width,
        height,
        baseline,
        total_size,
      )
    end
  end

  private

    def allocate_children(width, height, baseline, total_size)
      blocks = partition_items

      children.each_with_index do |child, index|
        blocks[index].then do |block|
          if block
            allocate_child(
              child,
              block,
              width,
              height,
              baseline,
              total_size,
            )
          end
        end
      end
    end

    def allocate_child(child, block, width, height, baseline, total_size)
      size = (width * (block.size + SIZE_SLACK).to_f / total_size).to_i
      position_offset = (width * block.offset.to_f / total_size).to_i

      child.allocate(
        size,
        height,
        baseline,
        Gsk::Transform.new.translate(Graphene::Point.new(position_offset, 0)),
      )

      block.color.then do |color|
        if color
          child.add_css_class(color)
        end
      end
    end

    # update_space_allocation_bar (): throw the old bins away, make one bin per
    # partition.
    def update
      unparent_children

      partition_items.each do
        Adwaita::Bin.new.tap do |partition_bin|
          partition_bin.add_css_class('partition-bin')
          partition_bin.set_parent(self)
        end
      end
    end

    def connect_partitions
      @drive&.partitions.then do |partitions|
        if partitions
          @partitions_handler = partitions.signal_connect('items-changed') { update }
        end
      end
    end

    def disconnect_partitions
      if @partitions_handler && @drive&.partitions
        @drive.partitions.signal_handler_disconnect(@partitions_handler)
      end

      @partitions_handler = nil
    end

    def drive_size
      @drive.then do |drive|
        if drive.nil?
          0
        else
          drive.size
        end
      end
    end

    def partition_items
      @drive.then do |drive|
        if drive.nil?
          []
        else
          drive.partition_items
        end
      end
    end

    # The gtk_widget_get_first_child/get_next_sibling walk upstream repeats in
    # three places. GTK4 has no "children" accessor, so the walk is done once
    # here and the rest of the class works with an array.
    def children
      [].tap do |collected|
        child = first_child

        while child
          collected << child
          child = child.next_sibling
        end
      end
    end

    def unparent_children
      children.each(&:unparent)
    end
end
