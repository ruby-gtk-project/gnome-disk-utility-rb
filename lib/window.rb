# frozen_string_literal: true

require 'adwaita'
require_relative 'drive_row'
require_relative 'job_manager'
require_relative 'job_row'
require_relative 'utils'

# Window is the main window: the drives sidebar on the left, the selected
# drive's view on the right, a jobs popover behind the progress button and the
# main menu behind the hamburger.
#
# A port of upstream's src/resources/ui/gdu-window.blp and
# src/disks/gdu-window.c. Carried over faithfully:
#
#   * The Adw.OverlaySplitView at sidebar-width-fraction 0.3, with the
#     Adw.Breakpoint at "max-width: 682sp" collapsing it.
#   * The sidebar's Adw.ToolbarView: a header bar with the Adw.WindowTitle
#     "Disks", the initially hidden "process-working-symbolic" MenuButton whose
#     popover holds the boxed jobs list, and the primary "open-menu-symbolic"
#     MenuButton for the main menu; below it a never-horizontally-scrolling
#     ScrolledWindow around the single-selection "navigation-sidebar" list box.
#   * The content's flat header bar with the sidebar-show toggle, bound both
#     ways to the split view's `collapsed` and `show-sidebar`.
#   * The Gtk::Stack with "empty_page" (the "No Device Selected" status page
#     with the drive-multidisk-symbolic icon) and "drive_page".
#   * The 980x640 default size, restored from and saved to the window state.
#
# Two things differ, both because a collaborator is not a GObject here:
#
#   * Upstream binds the job manager's `n-jobs` property to the progress
#     button's `visible`. JobManager reports its count through a callback
#     instead, so the window connects to that.
#
#   * gdu_window_load_state/gdu_window_unmap read and write the
#     org.gnome.Disks.window-state `initial-state` GSettings key, an (i, i, b)
#     tuple. The same tuple is kept in the port's JSON settings file under
#     "window-initial-state" — see Utils.settings_path for why.
#
# The drive view is passed in rather than built here. Upstream's template
# instantiates $GduDriveView directly and the breakpoint sets its `mobile`
# property; the window does both when it is given one.
#
class Window < Adwaita::ApplicationWindow
  type_register

  DEFAULT_WIDTH = 980
  DEFAULT_HEIGHT = 640
  STATE_KEY = 'window-initial-state'
  BREAKPOINT_CONDITION = 'max-width: 682sp'

  EMPTY_PAGE = 'empty_page'
  DRIVE_PAGE = 'drive_page'

  # gdu_window.blp's `menu main_menu`.
  MAIN_MENU = [
    [
      ['_New Disk Image…', 'app.new_disk_image'],
      ['_Attach Disk Image…', 'app.attach_disk_image'],
    ],
    [
      ['_Keyboard Shortcuts', 'app.shortcuts'],
      ['_Help', 'app.help'],
      ['_About Disks', 'app.about'],
    ],
  ].freeze

  attr_reader :drives, :job_manager, :drive_view

  def initialize(application, drives:, job_manager:, drive_view: nil)
    # A type_register'd subclass gets a no-argument initialize, so the
    # application cannot be passed up the way Adwaita::ApplicationWindow.new
    # takes it; it is set as a property instead, which is what
    # g_object_new (…, "application", application, NULL) does upstream.
    super()
    self.application = application

    @drives = drives
    @job_manager = job_manager
    @drive_view = drive_view
    @drive_rows = {}

    load_state
  end

  def build
    tap do |win|
      win.content = split_view
      win.add_breakpoint(breakpoint)

      split_view.tap do |view|
        view.sidebar = sidebar_toolbar
        view.content = content_toolbar

        sidebar_toolbar.tap do |toolbar|
          toolbar.add_top_bar(sidebar_header)
          toolbar.content = drives_scroller

          sidebar_header.tap do |header|
            header.title_widget = window_title
            header.pack_start(job_progress_button)
            header.pack_end(sidebar_menu)

            job_progress_button.popover = jobs_popover
            jobs_popover.child = jobs_listbox
          end

          drives_scroller.child = drives_listbox
        end

        content_toolbar.tap do |toolbar|
          toolbar.add_top_bar(content_header)
          toolbar.content = main_stack

          content_header.pack_start(show_sidebar_button)

          main_stack.add_named(empty_page, EMPTY_PAGE)

          if @drive_view
            main_stack.add_named(@drive_view, DRIVE_PAGE)
          end
        end
      end

      bind_sidebar_toggle
      bind_drives
      bind_job_manager

      win.signal_connect('unmap') { save_state }
    end
  end

  # drive_list_row_selection_changed_cb ().
  def on_selection_changed
    drives_listbox.selected_row.then do |row|
      if row.nil? || @drive_view.nil?
        # Upstream's template always instantiates the drive view, so it always
        # has a "drive_page" to switch to. Here the view is injected, and
        # without one the only page in the stack is the empty state.
        main_stack.visible_child_name = EMPTY_PAGE
      else
        main_stack.visible_child_name = DRIVE_PAGE
        @drive_view.drive = row.drive
      end
    end
  end

  # The "Unselect current disk" shortcut (Escape) in the shortcuts dialog.
  def unselect_drive
    drives_listbox.unselect_all
  end

  private

    # gdu_window_create_job_row_cb () plus gtk_list_box_bind_model ().
    def bind_job_manager
      jobs_listbox.bind_model(@job_manager.jobs) { |job| JobRow.new(job, @job_manager).build }

      @job_manager.on_n_jobs_changed { |_manager, n_jobs| job_progress_button.visible = n_jobs.positive? }
      job_progress_button.visible = @job_manager.n_jobs.positive?
    end

    def bind_drives
      drives_listbox.bind_model(@drives) { |drive| DriveRow.new(drive).build }
      drives_listbox.signal_connect('selected-rows-changed') { on_selection_changed }
    end

    # `visible: bind split_view.collapsed bidirectional` and
    # `active: bind split_view.show-sidebar bidirectional`.
    def bind_sidebar_toggle
      split_view.bind_property(
        'collapsed',
        show_sidebar_button,
        'visible',
        :bidirectional,
      )
      split_view.bind_property(
        'show-sidebar',
        show_sidebar_button,
        'active',
        :bidirectional,
      )
    end

    # gdu_window_load_state ().
    def load_state
      Utils.read_setting(STATE_KEY, [-1, -1, false]).then do |width, height, maximized|
        set_default_size(default_dimension(width, DEFAULT_WIDTH), default_dimension(height, DEFAULT_HEIGHT))

        if maximized
          maximize
        end
      end
    end

    def default_dimension(value, fallback)
      if value.nil? || value == -1
        fallback
      else
        value
      end
    end

    # gdu_window_unmap ().
    def save_state
      Utils.write_setting(STATE_KEY, [default_width, default_height, maximized?])
    end

    # Memoized widget methods

    def split_view
      @split_view ||= Adwaita::OverlaySplitView.new.tap do |view|
        view.sidebar_width_fraction = 0.3
      end
    end

    # The breakpoint's two setters, the second only when there is a drive view
    # to set it on. `mobile: "true"` in the .blp is the string "true", which is
    # how Blueprint spells a boolean for a property it cannot type-check.
    def breakpoint
      @breakpoint ||= Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse(BREAKPOINT_CONDITION)).tap do |point|
        point.add_setter(split_view, 'collapsed', true)

        if @drive_view
          point.add_setter(@drive_view, 'mobile', true)
        end
      end
    end

    def sidebar_toolbar = @sidebar_toolbar ||= Adwaita::ToolbarView.new
    def content_toolbar = @content_toolbar ||= Adwaita::ToolbarView.new
    def sidebar_header = @sidebar_header ||= Adwaita::HeaderBar.new
    def window_title = @window_title ||= Adwaita::WindowTitle.new('Disks', '')

    def content_header
      @content_header ||= Adwaita::HeaderBar.new.tap do |header|
        header.show_title = false
        header.add_css_class('flat')
      end
    end

    # Upstream's .blp carries a note against this button about one day
    # replacing the icon with an animated DrawingArea; as upstream has it, the
    # button shows the "process-working-symbolic" spinner icon.
    def job_progress_button
      @job_progress_button ||= Gtk::MenuButton.new.tap do |button|
        button.visible = false
        button.icon_name = 'process-working-symbolic'
      end
    end

    def jobs_popover = @jobs_popover ||= Gtk::Popover.new

    def jobs_listbox
      @jobs_listbox ||= Gtk::ListBox.new.tap do |listbox|
        listbox.selection_mode = :none
        listbox.add_css_class('boxed-list')
      end
    end

    def sidebar_menu
      @sidebar_menu ||= Gtk::MenuButton.new.tap do |button|
        button.primary = true
        button.icon_name = 'open-menu-symbolic'
        button.menu_model = main_menu
        button.tooltip_text = 'Main Menu'
      end
    end

    def main_menu
      @main_menu ||= Gio::Menu.new.tap do |menu|
        MAIN_MENU.each do |items|
          menu.append_section(nil, section_menu(items))
        end
      end
    end

    def section_menu(items)
      Gio::Menu.new.tap do |section|
        items.each { |label, action| section.append(label, action) }
      end
    end

    def show_sidebar_button
      @show_sidebar_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = 'sidebar-show-symbolic'
        button.tooltip_text = 'Show Sidebar'
      end
    end

    def drives_scroller
      @drives_scroller ||= Gtk::ScrolledWindow.new.tap do |scroller|
        scroller.hscrollbar_policy = :never
      end
    end

    def drives_listbox
      @drives_listbox ||= Gtk::ListBox.new.tap do |listbox|
        listbox.vexpand = true
        listbox.selection_mode = :single
        listbox.add_css_class('navigation-sidebar')
      end
    end

    def main_stack = @main_stack ||= Gtk::Stack.new

    def empty_page
      @empty_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = 'No Device Selected'
        page.icon_name = 'drive-multidisk-symbolic'
      end
    end
end
