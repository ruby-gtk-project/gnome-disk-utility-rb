# frozen_string_literal: true

require 'adwaita'
require_relative 'item'

# DriveRow is one drive in the window's sidebar.
#
# A port of upstream's src/resources/ui/gdu-drive-row.blp and
# src/disks/gdu-drive-row.c: an Adw.ActionRow whose prefix is a 32px image with
# the "lowres-icon" class, showing the drive's description as the title, its
# name as the subtitle, and its GIcon in the image. The row follows the drive's
# `changed` signal and refreshes all three on every emission.
#
class DriveRow < Adwaita::ActionRow
  type_register

  ICON_PIXEL_SIZE = 32

  attr_reader :drive

  def initialize(drive)
    super()

    @drive = drive
  end

  def build
    tap do |row|
      row.add_prefix(drive_image)

      @changed_observer = @drive.on_changed { update }
      update
    end
  end

  # update_drive_row ().
  def update
    self.title = @drive.description.to_s
    self.subtitle = @drive.name.to_s
    drive_image.set_from_gicon(@drive.icon)
  end

  # gdu_drive_row_finalize () drops the drive reference; here the only thing
  # worth dropping is the observer, so the row stops being called after the
  # list box has thrown it away.
  def unbind
    if @changed_observer
      @drive.off_changed(@changed_observer)
      @changed_observer = nil
    end
  end

  private

    def drive_image
      @drive_image ||= Gtk::Image.new.tap do |image|
        image.pixel_size = ICON_PIXEL_SIZE
        image.add_css_class('lowres-icon')
      end
    end
end
