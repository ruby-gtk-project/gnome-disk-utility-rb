# frozen_string_literal: true

require 'adwaita'
require_relative 'utils'

# EditFilesystemDialog lets the user change a volume's filesystem label.
#
# A port of upstream's src/resources/ui/gdu-edit-filesystem-dialog.blp and
# src/disks/gdu-edit-filesystem-dialog.c: an Adw.Dialog with a header bar
# ("_Cancel" / "Ch_ange"), a warning banner revealed when the filesystem is
# currently mounted (it will be unmounted automatically before the label is
# changed), and one Adw.EntryRow for the label.
#
# on_fs_label_row_changed_cb () disables "Change" and marks the entry row
# "error" while its text equals the filesystem's current label; this is
# ported as #on_label_changed. on_change_button_clicked () calls
# Block#set_fs_label_async and closes the dialog once the UDisks call
# replies (whether it succeeded or not — the same as upstream, which reports
# the error and then closes unconditionally).
#
class EditFilesystemDialog < Adwaita::Dialog
  type_register

  # gdu_edit_filesystem_dialog_show ().
  def self.show(parent_window, block)
    new(block).build.tap { |dialog| dialog.present(parent_window) }
  end

  def initialize(block)
    super()

    @block = block
  end

  def build
    tap do |dialog|
      dialog.title = 'Edit Filesystem'
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.add_top_bar(warning_banner)
        view.content = preferences_page

        header_bar.tap do |bar|
          bar.show_start_title_buttons = false
          bar.show_end_title_buttons = false
          bar.pack_start(cancel_button)
          bar.pack_end(change_button)
        end
      end

      preferences_page.add(preferences_group)
      preferences_group.add(fs_label_row)

      cancel_button.signal_connect('clicked') { close }
      change_button.signal_connect('clicked') { on_change_clicked }
      fs_label_row.signal_connect('notify::text') { on_label_changed }

      fs_label_row.text = @block.fs_label.to_s
      warning_banner.revealed = @block.needs_unmount?
    end
  end

  private

    # on_change_button_clicked (), change_filesystem_label_cb ().
    def on_change_clicked
      @block.set_fs_label_async(fs_label_row.text) do |success, error_message|
        unless success
          Utils.show_message('Error setting label', error_message, window)
        end
        close
      end
    end

    # on_fs_label_row_changed_cb ().
    def on_label_changed
      if fs_label_row.text == @block.fs_label.to_s
        fs_label_row.add_css_class('error')
        change_button.sensitive = false
      else
        fs_label_row.remove_css_class('error')
        change_button.sensitive = true
      end
    end

    def window = root

    # Memoized widget methods

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def warning_banner
      @warning_banner ||= Adwaita::Banner.new('This filesystem will be automatically unmounted prior to any changes.')
    end

    def cancel_button
      @cancel_button ||= Gtk::Button.new.tap do |button|
        button.label = '_Cancel'
        button.use_underline = true
      end
    end

    def change_button
      @change_button ||= Gtk::Button.new.tap do |button|
        button.label = 'Ch_ange'
        button.use_underline = true
        button.sensitive = false
        button.add_css_class('suggested-action')
      end
    end

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def preferences_group = @preferences_group ||= Adwaita::PreferencesGroup.new

    def fs_label_row = @fs_label_row ||= Adwaita::EntryRow.new.tap { |row| row.title = 'Label' }
end
