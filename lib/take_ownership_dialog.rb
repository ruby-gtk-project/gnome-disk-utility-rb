# frozen_string_literal: true

require 'adwaita'

# TakeOwnershipDialog asks before making the current user and group the owner of
# a filesystem, and offers to do it recursively.
#
# A port of upstream's src/resources/ui/gdu-take-ownership-dialog.blp, together
# with the two handlers in src/disks/gdu-block-row.c that drive it —
# on_recursive_switch_cb and on_take_ownership_dialog_response_cb. The dialog is
# an Adw.AlertDialog with a PreferencesGroup as its extra child holding the
# "_Recursive Mode" row, a help MenuButton with the warning popover, and the
# switch itself.
#
# The behaviour worth naming, because it is easy to miss in the .blp: flipping
# the switch on makes "_Take Ownership" destructive and moves the default
# response to "_Cancel"; flipping it off makes the confirm response suggested
# and the default again. That is on_recursive_switch_cb, and it is why the
# switch's notify::active is wired to the dialog rather than to the row.
#
# #choose reports the user's answer as [confirmed, recursive]; issuing the
# UDisks Filesystem.TakeOwnership call with the "recursive" option is the block
# row's job, as it is upstream.
#
class TakeOwnershipDialog < Adwaita::AlertDialog
  type_register

  INFO_TEXT = 'Recursive mode changes the ownership of subdirectories and files. ' \
              'This can cause problems if files are owned by other users.'

  def initialize
    # A type_register'd subclass gets a no-argument initialize, so the heading
    # is set as a property rather than passed to adw_alert_dialog_new ().
    super()

    self.heading = 'Take Ownership?'
    self.default_response = 'cancel'
    self.close_response = 'cancel'
  end

  def build
    tap do |dialog|
      dialog.add_response('cancel', '_Cancel')
      dialog.add_response('confirm', '_Take Ownership')
      dialog.set_response_appearance('confirm', :suggested)
      dialog.extra_child = preferences_group

      preferences_group.add(recursive_row)

      recursive_row.tap do |row|
        row.add_suffix(info_button)
        row.add_suffix(recursive_switch)
        row.activatable_widget = recursive_switch

        recursive_switch.signal_connect('notify::active') { on_recursive_switch }
      end

      info_button.popover = info_popover
    end
  end

  # adw_alert_dialog_format_body (_("Make your user and group the owner of ”%s”"), …).
  # The closing double quotation mark on both sides is upstream's, not a typo
  # introduced here.
  def describe(description)
    self.body = "Make your user and group the owner of ”#{description}”"
  end

  def recursive? = recursive_switch.active?

  # Presents the dialog and yields [confirmed, recursive] once the user answers.
  def choose_response(parent_window, &callback)
    choose(parent_window, nil) do |_source, result|
      choose_finish(result).then do |response|
        callback&.call(response != 'cancel', recursive?)
      end
    end
  end

  private

    # on_recursive_switch_cb ().
    def on_recursive_switch
      if recursive?
        set_response_appearance('confirm', :destructive)
        self.default_response = 'cancel'
      else
        set_response_appearance('confirm', :suggested)
        self.default_response = 'confirm'
      end
    end

    # Memoized widget methods

    def preferences_group = @preferences_group ||= Adwaita::PreferencesGroup.new

    def recursive_row
      @recursive_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = '_Recursive Mode'
        row.use_underline = true
      end
    end

    def info_button
      @info_button ||= Gtk::MenuButton.new.tap do |button|
        button.valign = :center
        button.tooltip_text = 'More Information'
        button.icon_name = 'help-about-symbolic'
        button.add_css_class('flat')
      end
    end

    def info_popover
      @info_popover ||= Gtk::Popover.new.tap do |popover|
        popover.child = info_label
      end
    end

    def info_label
      @info_label ||= Gtk::Label.new(INFO_TEXT).tap do |label|
        label.margin_top = 6
        label.margin_bottom = 6
        label.margin_start = 6
        label.margin_end = 6
        label.wrap = true
        label.max_width_chars = 50
        label.justify = :left
        label.xalign = 0
      end
    end

    def recursive_switch
      @recursive_switch ||= Gtk::Switch.new.tap do |switch|
        switch.valign = :center
      end
    end
end
