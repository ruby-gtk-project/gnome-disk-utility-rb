# frozen_string_literal: true

require 'adwaita'
require_relative 'enums'

# Item is the abstract base every row in the drive view is built from.
#
# Ported from upstream's src/disks/gdu-item.c (and gdu-item.h for the
# GduFeature flags, which live in lib/enums.rb here). Upstream makes this a
# G_DEFINE_ABSTRACT_TYPE whose class vtable carries get_description,
# get_partition_type, get_icon, get_size, get_partitions, get_parent,
# get_features and changed; subclasses override the slots they care about and
# the rest fall back to the "real" implementations below.
#
# Two deliberate differences from upstream:
#
#   * It descends from GLib::Object (via `type_register`) rather than being a
#     plain Ruby object, because Gio::ListStore — which Drive uses for its
#     partitions and Manager for its drives — only accepts GObjects.
#
#   * `changed` is a Ruby observer list rather than a GObject signal. The Ruby
#     bindings can define signals, but a widget that wants to follow an item
#     only ever calls `item.on_changed { ... }`, and the plain callback list
#     keeps the item usable from a spec with no main loop running.
#
class Item < GLib::Object
  type_register

  # Upstream's gdu_item_real_get_description and gdu_item_real_get_partition_type
  # both return an em dash for "nothing to say here".
  UNKNOWN = '—'

  def initialize
    super()
    @changed_observers = []
  end

  # --- The vtable, with upstream's default implementations ----------------

  def description = UNKNOWN

  def partition_type = UNKNOWN

  # gdu_item_real_get_icon is g_assert_not_reached (): every concrete item must
  # provide one, and a subclass that forgets is a bug, not a blank row.
  def icon
    raise NotImplementedError, "#{self.class} must implement #icon"
  end

  def size = 0

  def parent = nil

  def partitions = nil

  def features = Enums::Feature::NONE

  # --- The changed signal -------------------------------------------------

  # Registers @block to run whenever this item changes. Returns the block so a
  # caller can hand it back to #off_changed later.
  def on_changed(&block)
    @changed_observers << block
    block
  end

  def off_changed(observer)
    @changed_observers.delete(observer)
  end

  # gdu_item_changed (), which dispatches through the class's `changed` slot.
  # Drive overrides it to refresh itself from UDisks before notifying; the
  # default simply notifies.
  def changed
    emit_changed
  end

  # gdu_item_real_changed (), the signal emission on its own.
  def emit_changed
    @changed_observers.dup.each { |observer| observer.call(self) }
  end

  # --- Convenience over the feature bitmask -------------------------------

  def feature?(flag) = Enums::Flags.set?(features, flag)

  def feature_names = Enums::Flags.names(features, Enums::Feature::ALL)

  def n_partitions
    partitions.then do |model|
      if model.nil?
        0
      else
        model.n_items
      end
    end
  end

  # The partitions as a Ruby array, which is what every caller that is not a
  # Gtk::ListBox actually wants.
  def partition_items
    partitions.then do |model|
      if model.nil?
        []
      else
        Array.new(model.n_items) { |i| model.get_item(i) }
      end
    end
  end
end
