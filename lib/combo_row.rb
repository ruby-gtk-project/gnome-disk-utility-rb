# frozen_string_literal: true

require 'adwaita'

# ComboRow is an Adw.ComboRow whose popover does not truncate its items.
#
# A port of upstream's src/disks/gdu_combo_row.rs. Adw.ComboRow's own factory
# (adw-combo-row.c) builds a box holding an ellipsizing label and a
# "object-select-symbolic" tick, and caps the label at 20 characters so the row
# itself stays narrow. That cap also applies inside the popover, where there is
# room for the whole string — which matters here because the filesystem-type and
# partition-type lists the create dialogs show are long.
#
# So upstream installs its own factory that does what Adw.ComboRow's does, then,
# every time the row's box changes root, works out whether that box is currently
# inside this row's popover and if so lifts the character cap and shows the tick.
#
# Both widths, the icon name and the "is this box in my popover" test are
# upstream's, as are the two libadwaita line references.
#
class ComboRow < Adwaita::ComboRow
  type_register

  # The cap Adw.ComboRow puts on the row's own label; -1 is "no cap".
  MAX_WIDTH_CHARS = 20
  UNCAPPED_WIDTH_CHARS = -1

  def initialize
    super()

    @selection_handlers = {}
    self.factory = item_factory
  end

  private

    def item_factory
      Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect('setup') { |_factory, list_item| on_factory_setup(list_item) }
        factory.signal_connect('bind') { |_factory, list_item| on_factory_bind(list_item) }
        factory.signal_connect('unbind') { |_factory, list_item| on_factory_unbind(list_item) }
      end
    end

    # https://gitlab.gnome.org/GNOME/libadwaita/-/blob/ad446167acf3e6d1ee693f98ca636268be8592a1/src/adw-combo-row.c#L280
    def on_factory_setup(list_item)
      Gtk::Box.new(:horizontal, 0).tap do |box|
        box.append(item_label)
        box.append(selected_icon)

        list_item.child = box
      end
    end

    # https://gitlab.gnome.org/GNOME/libadwaita/-/blob/ad446167acf3e6d1ee693f98ca636268be8592a1/src/adw-combo-row.c#L341
    def on_factory_bind(list_item)
      list_item.child.tap do |box|
        box.first_child.label = list_item.item.string

        @selection_handlers[list_item.object_id] =
          signal_connect('notify::selected-item') { on_item_selected(list_item) }
        on_item_selected(list_item)

        # https://gitlab.gnome.org/GNOME/gnome-control-center/-/blob/5cbf3f952b69d56c5a7276742f898d36dd9c083c/panels/sound/cc-device-combo-row.c#L51
        box.signal_connect('notify::root') { |rooted_box| on_item_root_changed(rooted_box) }
        on_item_root_changed(box)
      end
    end

    # Upstream connects notify::selected-item once per bind and never
    # disconnects, so a row recycled through the factory ends up with one stale
    # handler per bind and the handlers fire against an already-unbound list
    # item. Dropping the handler on unbind keeps the behaviour and loses the
    # leak.
    def on_factory_unbind(list_item)
      @selection_handlers.delete(list_item.object_id).then do |handler_id|
        if handler_id
          signal_handler_disconnect(handler_id)
        end
      end
    end

    # The tick is only opaque on the row that is currently selected.
    def on_item_selected(list_item)
      list_item.child&.last_child&.tap do |icon|
        if selected_item == list_item.item
          icon.opacity = 1.0
        else
          icon.opacity = 0.0
        end
      end
    end

    # Adw.ComboRow reuses the very same child widgets for the row's own display
    # and for the popover's list, so which of the two a box is in can only be
    # answered once it has a root — hence notify::root rather than a one-off
    # check at bind time.
    def on_item_root_changed(box)
      in_combo_popover?(box).then do |in_popover|
        box.last_child.visible = in_popover

        if in_popover
          box.first_child.max_width_chars = UNCAPPED_WIDTH_CHARS
        else
          box.first_child.max_width_chars = MAX_WIDTH_CHARS
        end
      end
    end

    def in_combo_popover?(box)
      box.get_ancestor(Gtk::Popover.gtype).then do |popover|
        !popover.nil? && popover.get_ancestor(Adwaita::ComboRow.gtype) == self
      end
    end

    def item_label
      Gtk::Label.new(nil).tap do |label|
        label.xalign = 0.0
        label.ellipsize = :end
        label.max_width_chars = MAX_WIDTH_CHARS
        label.width_chars = 1
        label.valign = :center
      end
    end

    def selected_icon
      Gtk::Image.new.tap do |icon|
        icon.accessible_role = :presentation
        icon.icon_name = 'object-select-symbolic'
      end
    end
end
