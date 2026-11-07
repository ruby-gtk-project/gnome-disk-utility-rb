# frozen_string_literal: true

require 'adwaita'

# DriveHeader is the banner at the top of DriveView: the drive's icon, its
# description and device path, an info button that opens the drive-details
# dialog, and the drive options menu.
#
# A port of upstream's src/resources/ui/gdu-drive-header.blp and
# src/disks/gdu-drive-header.c. Carried over faithfully:
#
#   * The Adw.MultiLayoutView with its "horizontal" layout (a three-column
#     Grid: icon, labels, buttons) and "vertical" layout (the same three
#     slots stacked in a Box, buttons centered) — DriveView's breakpoint
#     setter flips #layout_name between them.
#   * The name and path labels' halign following the active layout — `start`
#     on "horizontal" (so they left-align in the wide grid), `fill` otherwise
#     — which upstream wires through a template expression binding
#     ($get_alignment_from_layout_name) and this port recomputes from
#     #layout_view's own notify::layout-name instead.
#   * The 96px drive_image carrying the "icon-dropshadow" CSS class.
#   * The drive_menu's three sections exactly as upstream orders them: format
#     and the two disk-image actions; benchmark/SMART/settings; the five
#     power actions. Every one of them (and the info button's
#     "view.show-drive-dialog") is a `view.*` action DriveView installs on
#     itself; GTK renders the ones DriveView does not install this round as
#     disabled, the same as the app menu's two unported disk-image items.
#
class DriveHeader < Adwaita::Bin
  type_register

  # gdu_drive_header.blp's `menu drive_menu`.
  MENU = [
    [
      ['Format Disk…', 'view.format'],
      ['Create Disk Image…', 'view.create-image'],
      ['Restore Disk Image…', 'view.restore-image'],
    ],
    [
      ['Benchmark Disk…', 'view.benchmark'],
      ['SMART Data & Self-Tests…', 'view.smart'],
      ['Drive Settings…', 'view.settings'],
    ],
    [
      ['Standby', 'view.standby'],
      ['Wake Up', 'view.wakeup'],
      ['Detach', 'view.detach'],
      ['Eject', 'view.eject'],
      ['Power Off', 'view.poweroff'],
    ],
  ].freeze

  def build
    tap do |header|
      header.child = layout_view

      layout_view.tap do |view|
        view.add_layout(horizontal_layout)
        view.add_layout(vertical_layout)
        view.set_child('icon', drive_image)
        view.set_child('labels', labels_box)
        view.set_child('buttons', buttons_box)

        view.signal_connect('notify::layout-name') { update_alignment }
      end

      labels_box.tap do |box|
        box.append(name_label)
        box.append(path_label)
      end

      buttons_box.tap do |box|
        box.append(info_button)
        box.append(options_button)
      end

      self.layout_name = 'horizontal'
    end
  end

  # gdu_drive_header_set_icon ().
  def icon=(icon)
    drive_image.set_from_gicon(icon)
  end

  # gdu_drive_header_set_drive_name ().
  def drive_name=(name)
    name_label.label = name
  end

  # gdu_drive_header_set_drive_path ().
  def drive_path=(path)
    path_label.label = path
  end

  # gdu_drive_header_set_layout_name ().
  def layout_name=(name)
    layout_view.layout_name = name
  end

  private

    # get_alignment_from_layout_name ().
    def update_alignment
      align = layout_view.layout_name == 'horizontal' ? :start : :fill
      name_label.halign = align
      path_label.halign = align
    end

    # Memoized widget methods

    def layout_view = @layout_view ||= Adwaita::MultiLayoutView.new

    def horizontal_layout
      @horizontal_layout ||= Adwaita::Layout.new(horizontal_grid).tap { |layout| layout.name = 'horizontal' }
    end

    def horizontal_grid
      @horizontal_grid ||= Gtk::Grid.new.tap do |grid|
        grid.column_spacing = 12
        grid.attach(Adwaita::LayoutSlot.new('icon'), 0, 0, 1, 1)
        grid.attach(Adwaita::LayoutSlot.new('labels'), 1, 0, 1, 1)
        grid.attach(Adwaita::LayoutSlot.new('buttons'), 2, 0, 1, 1)
      end
    end

    def vertical_layout
      @vertical_layout ||= Adwaita::Layout.new(vertical_box).tap { |layout| layout.name = 'vertical' }
    end

    def vertical_box
      @vertical_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.hexpand = true
        box.append(Adwaita::LayoutSlot.new('icon'))
        box.append(Adwaita::LayoutSlot.new('labels'))
        box.append(Adwaita::LayoutSlot.new('buttons').tap { |slot| slot.halign = :center })
      end
    end

    def drive_image
      @drive_image ||= Gtk::Image.new.tap do |image|
        image.pixel_size = 96
        image.add_css_class('icon-dropshadow')
      end
    end

    def labels_box
      @labels_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.hexpand = true
        box.valign = :center
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new.tap do |label|
        label.wrap = true
        label.add_css_class('title-1')
      end
    end

    def path_label = @path_label ||= Gtk::Label.new.tap { |label| label.wrap = true }

    def buttons_box = @buttons_box ||= Gtk::Box.new(:horizontal, 12).tap { |box| box.valign = :center }

    def info_button
      @info_button ||= Gtk::Button.new.tap do |button|
        button.tooltip_text = 'Drive Information'
        button.icon_name = 'help-about-symbolic'
        button.action_name = 'view.show-drive-dialog'
      end
    end

    def options_button
      @options_button ||= Gtk::MenuButton.new.tap do |button|
        button.tooltip_text = 'Drive Options'
        button.icon_name = 'view-more-symbolic'
        button.menu_model = drive_menu
      end
    end

    def drive_menu
      @drive_menu ||= Gio::Menu.new.tap do |menu|
        MENU.each { |items| menu.append_section(nil, section_menu(items)) }
      end
    end

    def section_menu(items)
      Gio::Menu.new.tap do |section|
        items.each { |label, action| section.append(label, action) }
      end
    end
end
