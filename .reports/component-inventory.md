# gnome-disk-utility — upstream component inventory

Survey of `origin/main` (upstream C + Rust + blueprint) against `lib/` on the
`ruby` branch, for the full-parity Ruby GTK4/Libadwaita port.
Method: the `component-identification` skill — read the declarative UI first
(`.blp`/`.ui` are the inventory), then the backing source for actions, dynamic
CSS, repeaters and runtime-built widgets.

Upstream is two apps in one tree:

| App | Upstream entry | Port target |
|---|---|---|
| **Disks** (`org.gnome.DiskUtility`) | `src/disks/main.c` + `gdu-application.c` | `lib/main.rb`, `lib/application.rb` |
| **Disk Image Mounter** (`org.gnome.DiskUtility.ImageMounter`) | `src/disk-image-mounter/main.rs` | `lib/image_mounter_application.rb`, `lib/image_mounter_window.rb` |

House shape (set by the `gnome-contacts-rb` pilot): one upstream source file →
one flat `lib/<thing>.rb`, `# frozen_string_literal: true`, `require 'adwaita'`
+ `require_relative` siblings, a comment naming the upstream file, widgets as
memoized accessors configured in `.tap` blocks.

Counts: 34 upstream UI units (29 blueprint, 2 GtkBuilder `.ui`, 3 code-only
widgets). `lib/` currently holds 1 unit (a placeholder application), so parity
is **1 of 34**, and even that one does not match the house layout.

---

## 1. Application and shell

### `src/disks/gdu-application.c` — the Disks application object
→ `lib/application.rb` · kind: application · **partially present**
(`lib/gnome_disk_utility/application.rb` is a placeholder window with a
status page; it is in the wrong path for the house shape and carries none of
the below).

| Component | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Application` | 1 | — | `startup`, `activate`, `open`, `handle-local-options` | app id `org.gnome.DiskUtility`, `HANDLES_OPEN` |
| app actions | 5 | — | `app.new_disk_image`, `app.attach_disk_image`, `app.help`, `app.about`, `app.quit` | `new_disk_image`/`attach_disk_image` present the matching dialogs; `help` opens `help:gnome-help/disk`; `quit` confirms when jobs are running |
| About dialog | 1 | — | `adw_show_about_dialog` | `Adwaita::AboutDialog` — app name “Disks”, version, website, credits |
| quit-confirmation alert | 1 | — | `AdwAlertDialog` responses | shown from `app.quit` when the job manager has running jobs |
| CLI options | 5 | — | — | `--block-device DEVICE`, `--format-device`, `--restore-disk-image FILE`, `--xid` (ignored), `-v/--verbose` |

Accelerators installed (`gtk_application_set_accels_for_action`):
`app.new_disk_image` `<Primary>N` · `app.attach_disk_image` `<Primary>A` ·
`app.help` `F1` · `app.quit` `<Primary>Q` · plus `win.go-back` `Escape`,
`win.open-drive-menu` `F9`, `win.open-volume-menu` `<Shift>F9`,
`win.open-app-menu` `F10`, `win.format-disk` `<Primary>D`,
`win.restore-disk-image` `<Primary>R`, `win.view-smart` `<Primary>S`,
`win.disk-settings` `<Primary>E`, `win.format-partition` `<Primary>P`.
**Upstream bug worth not copying blindly: none of those `win.*` actions is
installed anywhere in the tree** (the drive actions live on `view.*` in
`GduDriveView`, the volume actions on `row.*` in `GduBlockRow`). The port
should install them on the window and route them, which also makes the
shortcuts dialog honest.

### `src/resources/ui/gdu-window.blp` + `src/disks/gdu-window.c` — the main window
→ `lib/window.rb` · kind: window · **missing**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (template) | 1 | — | — | window-state saved to GSettings `org.gnome.Disks.window-state` |
| `Adw.Breakpoint` | 1 | — | `max-width: 682sp` | setters: `split_view.collapsed = true`, `drive_view.mobile = true` |
| `Adw.OverlaySplitView` `split_view` | 1 | — | — | `sidebar-width-fraction: 0.3` |
| `Adw.ToolbarView` | 2 | — | — | sidebar and content |
| `Adw.HeaderBar` | 2 | `flat` (content one) | — | sidebar bar has `Adw.WindowTitle` “Disks” |
| `Gtk.MenuButton` `job_progress_button` | 1 | — | — | `process-working-symbolic`, hidden unless jobs exist |
| `Gtk.Popover` `jobs_popover` | 1 | — | — | holds the jobs list |
| `Gtk.ListBox` `jobs_listbox` | 1 | `boxed-list` | — | repeater over `GduJobManager` jobs → `GduJobRow` |
| `Gtk.MenuButton` `sidebar_menu` | 1 | — | — | primary, `open-menu-symbolic`, `main_menu` |
| `Gtk.ScrolledWindow` | 1 | — | — | `hscrollbar-policy: never` |
| `Gtk.ListBox` `drives_listbox` | 1 | `navigation-sidebar` | `selected-rows-changed` → `drive_list_row_selection_changed_cb` | repeater over `GduManager` drives → `GduDriveRow` |
| `Gtk.ToggleButton` `show_sidebar_button` | 1 | — | bound to `split_view.collapsed` / `show-sidebar` | `sidebar-show-symbolic` |
| `Gtk.Stack` `main_stack` | 1 | — | — | pages `empty_page`, `drive_page` |
| `Adw.StatusPage` | 1 | — | — | **empty state**: “No Device Selected”, `drive-multidisk-symbolic` |
| `$GduDriveView` `drive_view` | 1 | — | — | composite, see below |

`menu main_menu`: section 1 — “_New Disk Image…” (`app.new_disk_image`),
“_Attach Disk Image…” (`app.attach_disk_image`); section 2 — “_Keyboard
Shortcuts” (`app.shortcuts`), “_Help” (`app.help`), “_About Disks”
(`app.about`). Note `app.shortcuts` is referenced by the menu and by the
`<Primary>question` accel in the shortcuts dialog but is **not** in
`app_entries` — another upstream gap the port should close.

### `src/resources/ui/shortcuts-dialog.blp` — keyboard shortcuts
→ `lib/shortcuts_dialog.rb` · kind: dialog · **missing**

`Adw.ShortcutsDialog` with 4 `Adw.ShortcutsSection`s and 14
`Adw.ShortcutsItem`s: General (Help `F1`, app menu `F10`, shortcuts
`<Primary>question`, Quit `<Primary>q`); Disks (new image `<Primary>n`,
attach image `<Primary>a`, unselect disk `Escape`); Drive (drive menu `F9`,
format `<Primary>d`, restore image `<Primary>r`, SMART `<Primary>s`, settings
`<Primary>e`); Partition (volume menu `<Shift>F9`, format `<Primary>p`).
No backing source file — a standalone unit.

---

## 2. Drive view and rows

### `src/resources/ui/gdu-drive-view.blp` + `src/disks/gdu-drive-view.c` — one drive's page
→ `lib/drive_view.rb` · kind: page + dialog · **missing**

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template) | 1 | — | — | `mobile` property set by the window breakpoint |
| `Adw.PreferencesPage` | 1 | — | — | |
| `Adw.PreferencesGroup` | 3 | — | — | header, “Space Allocation”, “Volumes” |
| `$GduDriveHeader` `drive_header` | 1 | — | — | composite |
| `$GduSpaceAllocationBar` | 1 | `space-allocation-bar` | — | custom `Gtk.Widget`, see below |
| `Gtk.ListBox` `drive_partitions_listbox` | 1 | `boxed-list` | — | **repeater** over the drive's blocks → `GduBlockRow`, one per partition, nested by depth |

Installed actions (`view.` prefix, 12): `format`, `create-image`,
`restore-image`, `benchmark`, `smart`, `settings`, `standby`, `wakeup`,
`detach`, `eject`, `poweroff`, `show-drive-dialog`. Each is enabled/disabled
from the drive's feature flags (`ENABLE` macro), which is what makes the
`Detach`/`Eject` menu items `hidden-when: action-disabled`.

Second root in the same file — **Drive Information dialog**
(`Adw.Dialog drive_info_dialog`, content-width 480) → fold into
`lib/drive_view.rb` or split to `lib/drive_info_dialog.rb`:
`Adw.ToolbarView` + `Adw.HeaderBar` + `Adw.ToastOverlay` +
`Adw.PreferencesPage` with 4 `Adw.ActionRow`s (`property`,
`subtitle-selectable`): Model, Serial, Partitioning, Size; the first two carry
a flat `edit-copy-symbolic` copy `Gtk.Button` whose handler shows an
`Adw.Toast` (“Copied drive model to clipboard” / “Copied drive serial to
clipboard”). Two `Adw.AlertDialog`s are also raised from this file, for
eject/power-off confirmation and errors.

### `src/resources/ui/gdu-drive-header.blp` + `gdu-drive-header.c` — drive title block
→ `lib/drive_header.rb` · kind: widget · **missing**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template) | 1 | — | — | properties `drive-name`, `drive-path` |
| `Adw.MultiLayoutView` `layout_view` | 1 | — | — | layouts `horizontal` (Grid) and `vertical` (Box) |
| `Adw.Layout` | 2 | — | — | |
| `Adw.LayoutSlot` | 6 | — | — | `icon`, `labels`, `buttons` in each layout |
| `Gtk.Grid` / `Gtk.Box` | 1 / 3 | — | — | |
| `Gtk.Image` `drive_image` | 1 | `icon-dropshadow` | — | pixel-size 96 |
| `Gtk.Label` | 2 | `title-1` (first) | — | bound to `drive-name` / `drive-path`; `halign` bound through `$get_alignment_from_layout_name` |
| `Gtk.Button` | 1 | — | `view.show-drive-dialog` | “Drive Information”, `help-about-symbolic` |
| `Gtk.MenuButton` | 1 | — | `drive_menu` | “Drive Options”, `view-more-symbolic` |

`menu drive_menu` — 11 items in 3 sections: Format Disk… (`view.format`),
Create Disk Image… (`view.create-image`), Restore Disk Image…
(`view.restore-image`) / Benchmark Disk… (`view.benchmark`), SMART Data &
Self-Tests… (`view.smart`), Drive Settings… (`view.settings`) / Standby
(`view.standby`), Wake Up (`view.wakeup`), Detach (`view.detach`,
`hidden-when: action-disabled`), Eject (`view.eject`, same), Power Off
(`view.poweroff`).

### `src/resources/ui/gdu-drive-row.blp` + `gdu-drive-row.c` — one drive in the sidebar
→ `lib/drive_row.rb` · kind: row · **missing**

`Adw.ActionRow` template with a prefix `Gtk.Image` `drive_image`
(`lowres-icon`, pixel-size 32). Title/subtitle set from the drive; row is the
sidebar selection unit.

### `src/resources/ui/gdu-block-row.blp` + `gdu-block-row.c` — one volume/partition
→ `lib/block_row.rb` · kind: row · **missing**

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ExpanderRow` (template) | 1 | one of `blue`, `brown`, `green`, `grey`, `orange`, `purple`, `red`, `yellow` — **dynamic**, from the block's `color` data | — | the colour matches the space-allocation bar segment |
| `Gtk.Box` `button` | 1 | — | — | prefix |
| `Gtk.Label` `partition_depth_label` | 1 | — | — | invisible; carries nesting depth |
| `Gtk.Image` `partition_image` | 1 | `partition-row` | — | 20×20 |
| `Gtk.Spinner` `job_indicator_spinner` | 1 | — | — | visible while a job touches this block |
| `Adw.Clamp` | 1 | — | — | max 160 |
| `Gtk.LevelBar` `space_level_bar` | 1 | — | — | usage; hidden unless the filesystem reports size |
| `Gtk.Button` `create_partition_button` | 1 | `flat` | `row.create_partition` | “Create Partition”, `list-add-symbolic`, shown only on free space |
| `Gtk.MenuButton` `block_menu_button` | 1 | `flat` | `block_menu` | “Partition Options”, visibility inverse of the above |
| `Adw.ActionRow` | 4 | `property`, `subtitle-selectable` | — | Size, Device ID, UUID, Partition Type |

`menu block_menu` — 11 static items plus up to 1 prepended at runtime:
Resize… (`row.resize`); submenu “Edit” → Partition… (`row.edit_partition`),
Filesystem… (`row.edit_filesystem`), Change Passphrase…
(`row.change_passphrase`), Mount Options… (`row.configure_fstab`), Encryption
Options… (`row.configure_crypttab`), Take Ownership… (`row.take_ownership`);
Format Partition… (`row.format_partition`), Delete… (`row.delete`); Check
Filesystem… (`row.check_fs`), Repair Filesystem… (`row.repair_fs`), Benchmark
Partition… (`row.benchmark_partition`); Create Partition Image…
(`row.create_partition_image`), Restore Partition Image…
(`row.restore_partition_image`). `gdu_block_row_update` prepends exactly one
of **Mount** (`row.mount`), **Unmount** (`row.unmount`), **Lock**
(`row.lock`), **Unlock** (`row.unlock`) into `volume_actions_submenu`
depending on state — four menu items the scan cannot see.

Installed actions (`row.` prefix, 14 in the table + the 4 dynamic ones).
Confirmation/result `Adw.AlertDialog`s raised from this file (6, all
user-facing text the port must carry): “Delete Partition?” / “All data on the
partition will be lost” / _Delete_; “Confirm Check?” / _Check_; “Repair
Filesystem?” / _Repair_; result messages “Filesystem intact” / “Filesystem
damaged”, “Repair successful” / “Repair failed”; and error dialogs “Error
mounting filesystem”, “Error deleting partition”, “Error while resizing
filesystem”, “Error while checking filesystem”, “Error while repairing
filesystem”, “Error while taking filesystem ownership”.

### `src/disks/gdu-space-allocation-bar.c` — the space bar
→ `lib/space_allocation_bar.rb` · kind: widget (custom draw/allocate) · **missing**

A `Gtk.Widget` subclass with its own `measure`/`size_allocate`, CSS class
`space-allocation-bar`, holding one `Adw.Bin` per block with CSS classes
`partition-bin` plus the block's dynamic colour. No `.blp`. In Ruby this is a
`Gtk::Box`-with-proportions or a `Gtk::DrawingArea`; the house style has a
Cairo-drawing pattern for exactly this (see the `ruby-gtk` skill's
declarative-patterns reference).

### `src/resources/ui/gdu-job-row.blp` + `gdu-job-row.c` — one running job
→ `lib/job_row.rb` · kind: row · **missing**

`Adw.PreferencesRow` template (`focusable: false`) → `Gtk.Box` (vertical)
with a title `Gtk.Label` bound to `template.title`, a `Gtk.Box` holding a
`Gtk.ProgressBar` `progress_bar` and a `Gtk.Button`
(`process-stop-symbolic`, tooltip “Cancel”, CSS `circular raised`, action
`job.cancel`), and a `Gtk.Label` `status_label` (CSS `dimmed`).
Backed by `gdu-job-manager.c` / `gdulocaljob.c` / `localjob.rs` /
`estimator.rs` + `gduestimator.c` → `lib/job_manager.rb`, `lib/local_job.rb`,
`lib/estimator.rb` (model, not widgets, but the row is meaningless without
them).

---

## 3. Dialogs — drive level

### `src/resources/ui/gdu-format-disk-dialog.blp` + `gdu-format-disk-dialog.c`
→ `lib/format_disk_dialog.rb` · kind: dialog · **missing**

`Adw.Dialog` (title “Format Disk”, width 400) → `Adw.ToolbarView` +
`Adw.HeaderBar` (no title buttons, `Adw.WindowTitle`) with “_Cancel”
(`window.close`) and “_Format” (`destructive-action`, →
`on_format_clicked_cb`). Content `Adw.PreferencesPage`: group 1 — an
`Adw.ActionRow` “_Overwrite Existing Data” with a flat `help-about-symbolic`
`Gtk.MenuButton` + `Gtk.Popover` + wrapped `Gtk.Label` explanation, and a
suffix `Gtk.Switch` `erase_switch`; group 2 “Partitioning” — 3
`Adw.ActionRow`s each with a prefix `Gtk.CheckButton` targeting
`format.update_part_type` with `'gpt'` / `'dos'` / `'empty'` (“_GUID
Partition Table (GPT)”, “_Master Boot Record (MBR)”, “_No Partitioning”).
A confirmation `Adw.AlertDialog` is raised before formatting.

### `src/resources/ui/gdu-benchmark-dialog.blp` + `gdu-benchmark-dialog.c`
→ `lib/benchmark_dialog.rb` (+ `lib/benchmark_graph.rb`) · kind: dialog · **missing**

`Adw.Dialog` “Benchmark” → `Adw.ToolbarView`/`Adw.HeaderBar` with
`close_button` “_Cancel” (`window.close`), `cancel_button` “_Cancel”
(`on_cancel_clicked_cb`, visibility inverse of the first), “_Start…”
(`suggested-action`, `on_start_clicked_cb`) and an `Adw.WindowTitle`.
Content `Gtk.Stack` `pages_stack` (crossfade) with 2 pages:
- **options** — `Adw.PreferencesPage` with a description paragraph; 3
  `Adw.SpinRow`s (“Transfer S_amples” 2–1000, “Transfer Sample S_ize” with
  `output => set_sample_size_unit_cb`, “_Access Time Samples” 2–10000) each
  with its own `Gtk.Adjustment`; plus an `Adw.SwitchRow` “_Write Benchmark”
  (“Data should be backed up before using this feature”).
- **results** — `$GduBenchmarkGraph benchmark_graph` (a code-only drawing
  widget defined in `gdu-benchmark-dialog.c`) and 4 `Adw.ActionRow`s
  (`property`): Sample Size, Average Read Rate, Average Write Rate, Average
  Access Time (the last three `use-markup`).

Settings read/written: `org.gnome.Disks.benchmark` (`num-samples`,
`sample-size-mib`, `do-write`, `num-access-samples`).

### `src/resources/ui/gdu-ata-smart-dialog.ui` + `gdu-ata-smart-dialog.c`
→ `lib/ata_smart_dialog.rb` · kind: dialog · **missing**
*The only remaining GtkBuilder `.ui` of the Disks app — still GTK3-era in
style (`Gtk.TreeView` + `Gtk.ListStore` with 10 columns).*

`Adw.Dialog` `smart-dialog` → `Adw.ToolbarView` + `Adw.HeaderBar` +
`Gtk.Box` `content-area`: a `Gtk.Grid` `status-grid` of 13 `Gtk.Label`s
(6 with `dim-label`) — Powered On, Updated, Temperature, Self-test Result,
Self-assessment, Overall Assessment and their value labels — a `Gtk.Switch`
`enabled-switch`, a mnemonic label “SMART _Attributes”, a
`Gtk.ScrolledWindow` + `Gtk.TreeView` `attributes-treeview` (+
`Gtk.TreeSelection`) with 10 columns built in code, and a `toolbar` box with
`Gtk.MenuButton` `start-selftest-button` “_Start Self-test”, `Gtk.Button`
`stop-selftest-button` “_Stop Self-test” and `Gtk.Button` `refresh-button`
“Refresh” (`raised`). `menu selftest-menu`: “_Short” (`test.short`),
“_Extended” (`test.extended`), “_Conveyance” (`test.conveyance`) — a
`Gio::SimpleActionGroup` installed in code. Also a per-attribute detail
mapping (`smart_details_map`) of ~30 translated attribute names/descriptions.
**Port note:** `Gtk::TreeView` is deprecated in GTK4; the Ruby port should
use `Gtk::ColumnView` + `SignalListItemFactory` (the `ruby-gtk` skill's list
patterns) and keep the same 10 columns.

### `src/resources/ui/gdu-disk-settings-dialog.blp` + `gdu-disk-settings-dialog.c`
→ `lib/disk_settings_dialog.rb` · kind: dialog · **missing**
*Top-level named object (`Adw.Dialog disk-settings-dialog`), not a template.*

`Adw.Dialog` “Drive Settings” (500×300) → `Adw.ToolbarView` + `Adw.HeaderBar`
(“_Cancel” → `window.close`, `Adw.WindowTitle`, `ok-button` “Sa_ve”
`suggested-action`) → `Gtk.Notebook` with 4 tabs, each a vertical `Gtk.Box`
with a heading `Gtk.Label` (`heading`) + master `Gtk.Switch`:

| Tab | Widgets |
|---|---|
| “_Standby” | `standby-switch`, `standby-value-label`, `Gtk.Scale` `standby-scale` + `standby-adjustment` (0–255, 60), `dim-label` “Enter Standby After” |
| “A_PM” | `apm-switch`, `apm-label`/`apm-value-label` (`dim-label`), `Gtk.Scale` `apm-scale` + adjustment (1–255, 127), a `caption` warning about aggressive spin-down |
| “_AAM” | `aam-switch`, `Gtk.Grid` of 4 labels (Vendor Recommended / AAM Level + values), `Gtk.Scale` `aam-scale` + adjustment (127–254, 128) |
| “Wr_ite Cache” | `write-cache-switch`, `dim-label` “S_etting”, `Gtk.ComboBoxText` `write-cache-comboboxtext` (“Enable Write Cache”, “Disable Write Cache”), a `caption` warning about data loss |

Plus an `Adw.AlertDialog` confirmation on OK (`on_ok_clicked`).
**Port notes:** `Gtk::Notebook` is fine in GTK4 but the Adwaita-native shape
is `Adw::ViewStack` + `Adw::ViewSwitcher`; `Gtk::ComboBoxText` is deprecated
— use `Adw::ComboRow` with a `Gtk::StringList`. Record either choice in the
file's porting comment.

### `src/resources/ui/gdu-create-disk-image-dialog.blp` + `.c`
→ `lib/create_disk_image_dialog.rb` · kind: dialog · **missing**

`Adw.Dialog` (width 440) → header “_Cancel” / “C_reate” (`suggested-action`,
`on_create_image_button_clicked_cb`); `Adw.PreferencesPage` with
`Adw.EntryRow` `name_entry` “_Name”, `Adw.ActionRow` `location_entry`
“Location” (`property`) with a flat `folder-open-symbolic` button →
`Gtk.FileDialog`, and `Adw.ActionRow` `source_label` “Source” (`property`).
Runtime: a progress/“unreadable data” `Adw.AlertDialog` (heading about data
that could not be read), the `image-dir-uri` GSetting, and a `GduLocalJob`
feeding the jobs popover.

### `src/disks/restore_disk_image_dialog.rs` + `gdu-restore-disk-image-dialog.blp`
→ `lib/restore_disk_image_dialog.rb` · kind: dialog · **missing**

`Adw.Dialog` (width 440) → header “_Cancel” / `start_restore_button`
“_Restore…” (`suggested-action`, insensitive until valid). Content vertical
`Gtk.Box`: `Adw.Banner` `error_banner`, `Adw.Banner` `warning_banner`
(**error states**), then `Adw.PreferencesPage` / `Adw.PreferencesGroup` with
`Adw.ActionRow` `image_row` “Image”/“None Selected” (`property`) + flat
`folder-open-symbolic` `file_chooser_button` → `gtk::FileDialog`,
`Adw.ActionRow` `size_row` “Image Size” (`property`), and `$GduComboRow`
`destination_row` “Destination” (`property`, `notify::selected`).

### `src/disks/gdu_combo_row.rs` — non-truncating combo row
→ `lib/combo_row.rb` · kind: widget · **missing**
An `Adw.ComboRow` subclass that stops the popover truncating long items (it
replaces the list factory). Used by the restore dialog.

### `src/resources/ui/gdu-new-disk-image-dialog.blp` + `.c`
→ `lib/new_disk_image_dialog.rb` · kind: dialog · **missing**

`Adw.Dialog` “Create Disk Image” (440) → header “_Cancel” / “C_reate”.
`Adw.PreferencesPage`: `Adw.EntryRow` `name_entry` “_Name”,
`Adw.ActionRow` `location_entry` “Location” (`property`) + flat
`folder-open-symbolic` button → `Gtk.FileDialog`, `Adw.SpinRow` `size_entry`
“_Size” (adjustment upper 1e13, `output => set_size_entry_unit_cb`), and an
`Adw.ComboRow` `size_unit_combo` “Units” over an 11-entry `Gtk.StringList`
(bytes, kB, MB, GB, TB, PB, KiB, MiB, GiB, TiB, PiB). Plus an error
`Adw.AlertDialog`.

### `src/resources/ui/gdu-attach-disk-image-dialog.blp` + `.c`
→ `lib/attach_disk_image_dialog.rb` · kind: dialog · **missing**

`Adw.Dialog` “Attach Disk Image” (`follows-content-size`) → header “_Cancel” /
`attach_image_button` “_Attach” (`suggested-action`, insensitive until a file
is chosen). `Adw.PreferencesPage`: `Adw.ActionRow` `disk_image_file_row`
“_Disk Image File” / “None Selected” (`property`) with a flat
`folder-open-symbolic` `file_chooser_button` (tooltip “Select a Disk Image”)
→ `Gtk.FileDialog` filtered to disk images, and `Adw.SwitchRow` `readonly_row`
“_Read-Only” (active).

---

## 4. Dialogs — volume level

### `src/resources/ui/gdu-format-volume-dialog.blp` + `.c` — the format assistant
→ `lib/format_volume_dialog.rb` · kind: dialog (multi-page wizard) · **missing**

`Adw.Dialog` → `Adw.ToolbarView` + `Adw.HeaderBar` with `back_button` and
`forward_button` (labels and sensitivity recomputed per page) and a
`Gtk.Stack` `pages_stack` (crossfade) whose children are the five page
widgets below. Page order is computed in `gdu-format-volume-dialog.c`:
partition → filesystem → (other) → (password) → confirm, branching on
“extended partition”, “other filesystem” and “encrypt”.

Its five pages, each its own unit:

| Upstream | → | Contents |
|---|---|---|
| `gdu-create-partition-page.blp` + `.c` | `lib/create_partition_page.rb` | `Adw.Bin` → `Gtk.Box` with `Adw.Banner` `top_banner`, `Adw.PreferencesPage`: a `Gtk.Scale` over `size_adjustment`; `Adw.SpinRow` `size_row` “Partition Size” and `Adw.SpinRow` `free_space_row` “Free Space”/“Space following new partition” (both `output => set_size_entry_unit_cb`, adjustments cross-bound, `value-changed => on_size_changed_cb`); a group holding `Adw.SwitchRow` `dos_extended_row` “Extended Partition” (hidden unless MBR, `notify::active => on_part_type_changed`); `Adw.ComboRow` `size_unit_combo` “Units” over the 11-unit `Gtk.StringList` |
| `gdu-create-filesystem-page.blp` + `.c` | `lib/create_filesystem_page.rb` | `Adw.Bin` (`notify::fs-type`) → `Adw.EntryRow` `name_entry` “_Volume Name” (`apply => on_fs_name_changed`); an `Adw.ActionRow` “_Overwrite Existing Data” with flat `help-about-symbolic` `Gtk.MenuButton` + `Gtk.Popover` + `Gtk.Label` and a suffix `Gtk.Switch` `erase_switch`; a “Type” group of 4 `Adw.ActionRow`s each with a prefix `Gtk.CheckButton` on action `update_fs_type` with targets `'ext4'`, `'ntfs'`, `'vfat'`, `'other'` (“E_xt4” / “For use only with Linux systems”, “N_TFS” / “For use with Windows”, “_FAT” / “For use with all systems and devices”, “Ot_her”); `Adw.SwitchRow` `encrypt_switch` “_Password Protect Volume” / “Encrypts the volume using LUKS”, sensitive only when ext4 |
| `gdu-create-other-page.blp` + `.c` | `lib/create_other_page.rb` | `Adw.Bin` → `Adw.PreferencesGroup` `fs_types_group` “Type” — a **repeater**: one `Adw.ActionRow` + prefix `Gtk.CheckButton` per filesystem type built in `.c` (xfs, swap, btrfs, f2fs, exfat, udf, empty, dos-extended, …) — plus `Adw.SwitchRow` `encrypt_switch` “Password Protect Volume” |
| `gdu-create-password-page.blp` + `.c` | `lib/create_password_page.rb` | `Adw.Bin` → group with description; `Adw.PasswordEntryRow` `password_entry` “Password” and `confirm_password_entry` “Confirm Password” (both `notify::text => on_password_changed`); `Gtk.Label` `confirm_password_label` “The passwords do not match.” (hidden until needed — an **error state**); `Gtk.LevelBar` `strength_indicator` (continuous, max 5) with offsets `strength-weak`, `strength-low`, `strength-medium`, `strength-good`, `strength-high`; `Gtk.Label` `strength_hint_label` (`dim-label explanation-label`) |
| `gdu-create-confirm-page.blp` + `.c` | `lib/create_confirm_page.rb` | `Adw.Bin` (400 wide) → `Adw.Banner` “Warning: All the data on the volume will be lost” (revealed), a `Gtk.Label` “Confirm the details…”, and 4 `Adw.ActionRow`s (`property`): Device, Volume, Used (hidden unless known), Location |

### `src/resources/ui/gdu-edit-filesystem-dialog.blp` + `.c`
→ `lib/edit_filesystem_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Edit Filesystem” → header “_Cancel” / `change_button`
“Ch_ange” (`suggested-action`, insensitive until changed); a top
`Adw.Banner` `warning_banner` (“This filesystem will be automatically
unmounted prior to any changes.”); `Adw.EntryRow` `fs_label_row` “Label”
(`notify::text`), length-capped by `gdu_utils_get_max_label_length`.

### `src/resources/ui/gdu-edit-partition-dialog.blp` + `.c`
→ `lib/edit_partition_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Edit Partition” (500) → header “_Cancel” / `confirm_button`
“_Done”. `Adw.PreferencesPage`: `Adw.ComboRow` `type_row` “_Partition Type”
(subtitle about the 32-bit GUID, model filled in `.c` from the partition type
table), `Adw.EntryRow` `name_entry` “_Name” (`property`, tooltip-markup about
`/dev/disk/by-partlabel`); a “Flags” group of 3 `Adw.ActionRow`s —
“_Legacy BIOS Bootable”, “_System Partition”, “_Hide from Firmware” — each
with a flat `help-about-symbolic` `Gtk.MenuButton` + `Gtk.Popover` +
explanatory `Gtk.Label` and a suffix `Gtk.Switch` (`bootable_switch`,
`system_partition_switch`, `firmware_hide_switch`, all
`notify::active => on_property_changed_cb`).

### `src/resources/ui/gdu-resize-volume-dialog.blp` + `.c`
→ `lib/resize_volume_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Resize Volume” → header “_Cancel” / “_Resize”
(`destructive-action`). Content `Gtk.Overlay` over an
`Adw.PreferencesPage` (description warning about data loss) with a
`Gtk.Scale` `size_scale` + `size_adjustment`; 3 `Adw.ActionRow`s
(`property`): Available Space, Current Size, Minimum Size; 2 `Adw.SpinRow`s
“_New Size” and “_Free After Resize”; `Adw.ComboRow` `size_unit_combo`
“_Units” over the 11-unit `Gtk.StringList`. Overlay child `Adw.Spinner`
`spinner` (hidden; the page goes insensitive while it shows) — the
**busy state**.

### `src/resources/ui/gdu-change-passphrase-dialog.blp` + `.c`
→ `lib/change_passphrase_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Change Passphrase” (590×320) → header “_Cancel” /
`change_pass_button` “Ch_ange” (`suggested-action`, insensitive until valid);
`Adw.Banner` `banner` (markup, about `/etc/crypttab`); 3
`Adw.PasswordEntryRow`s (“C_urrent Password”, “_New Password”, “C_onfirm
Password”, each `notify::text => on_dialog_entry_changed`); `Gtk.LevelBar`
`strength_indicator` with the five `strength-*` offsets; `Gtk.Label`
`strength_hint_label` (`dim-label explanation-label`).

### `src/resources/ui/gdu-unlock-dialog.blp` + `.c`
→ `lib/unlock_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Unlock Volume” → header `close_button` “_Cancel” /
`unlock_button` “_Unlock” (`suggested-action`, insensitive until valid).
Content: `Adw.Banner` `keyring_banner` (“The encryption passphrase was
retrieved from the keyring”), `Adw.Banner` `veracrypt_banner` (“This volume
might be a VeraCrypt volume…”); group “Security Credentials” with
`Adw.PasswordEntryRow` `passphrase_entry`, `Adw.EntryRow` `pim_entry_row`
(PIM, VeraCrypt-only), `Adw.ActionRow` `keyfile_row` “Keyfiles”/“None
Selected” + flat `folder-open-symbolic` `keyfile_chooser` →
`Gtk.FileDialog`; group “Volume Configuration” (VeraCrypt-only) with 2
`Adw.ActionRow`s “Hidden” and “Windows System”, each a flat
`help-about-symbolic` `Gtk.MenuButton` + `Gtk.Popover` + `Gtk.Label` and a
suffix `Gtk.Switch` (`tcrypt_hidden_switch_row`,
`tcrypt_system_switch_row`, both CSS `flat`). The VeraCrypt half is revealed
by `keyfile_chooser.visible`.

### `src/resources/ui/gdu-mount-options-dialog.blp` + `.c`
→ `lib/mount_options_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Mount Options” (height 600) → header “_Cancel” / `save_button`
“_Done”. Content: `Adw.Banner` `info_banner` (“The system may not work
correctly if this entry is modified or removed”); a `Gtk.Overlay` over an
`Adw.PreferencesPage` with `Adw.SwitchRow` `automount_switch_row`
“_Automatic Mount Options” (every following group is `sensitive` on its
inverse); “General” — `Adw.SwitchRow` × 3 (“_Mount at Startup”, “_Show in
Files”, “_Require Authorization”); “Appearance” — `Adw.EntryRow` × 3
(“D_isplay Name”, “C_olor Icon”, “S_ymbolic Icon”); “Technical Options” —
`Adw.EntryRow` × 3 (`property`: “_fstab Options”, “Mount _Point”,
“Filesystem _Type”); `Adw.ComboRow` `device_combo_row` “Ide_ntify As”; and an
`Adw.ButtonRow` “R_estore Default Settings” (`destructive-action`). Overlay
child `Adw.Spinner` `spinner` (busy state). Every row fires
`on_property_changed`.

### `src/resources/ui/gdu-encryption-options-dialog.blp` + `.c`
→ `lib/encryption_options_dialog.rb` · kind: dialog · **missing**
`Adw.Dialog` “Encryption Options” (560×500) → header “Cancel” /
`done_button` “Done” (`suggested-action`, insensitive until changed); top
`Adw.Banner` `infobar` (markup, about `/etc/crypttab` vs *Change Passphrase*);
`Adw.SwitchRow` `use_defaults_switch` “Automatic Encryption Options”; two
groups sensitive on its inverse — `Adw.EntryRow` “Name”, `Adw.EntryRow`
“Passphrase”; `Adw.SwitchRow` “Unlock at System Start”, `Adw.SwitchRow`
“Require Additional Authorization”, `Adw.EntryRow` “Additional Options”.

### `src/resources/ui/gdu-take-ownership-dialog.blp`
→ `lib/take_ownership_dialog.rb` · kind: dialog · **missing**
*Top-level named object, no backing `.c` of its own (driven from
`gdu-block-row.c`).* `Adw.AlertDialog` `ownership_dialog` heading “Take
Ownership?”, responses `cancel` “_Cancel” and `confirm` “_Take Ownership”
(suggested), body formatted “Make your user and group the owner of ”%s””;
`extra-child` is an `Adw.PreferencesGroup` with one `Adw.ActionRow`
“_Recursive Mode” carrying a flat `help-about-symbolic` `Gtk.MenuButton` →
`Popover info_popover` (a wrapped `Gtk.Label` warning about subdirectories)
and a suffix `Gtk.Switch` `recursive_switch` (`notify::active`).

---

## 5. Shared dialog helpers

### `src/libgdu/gduutils.c` + `src/libgdu/gduutils.rs`
→ `lib/utils.rb` · kind: helpers + 3 dialogs · **missing**

Three user-facing dialogs every other unit calls, so they belong in one file:
- `gdu_utils_show_error (parent, title, error)` — `Adw.AlertDialog`, heading
  = title, body = the GError, one response “_Close”; the single error
  presentation for the whole app.
- `gdu_utils_show_message (title, message, parent)` — same shape, for
  results.
- `gdu_utils_show_confirmation (parent, data, extra_child)` —
  `Adw.AlertDialog` with `cancel` + a caller-supplied response verb
  (`destructive` appearance), optional extra child; this is what Delete,
  Check, Repair, Format, Eject and Power Off all go through.
Plus the non-widget helpers the port needs anyway: size/duration formatting,
unit defaults, `configure_file_dialog_for_disk_images`, the fstab/crypttab
option editors, `can_resize` / `can_repair` / `can_format` /
`can_take_ownership` / `can_check`, `max_label_length`, `unfuse_path`.

### `src/resources/style.css`
→ `lib/style.rb` (a `Gtk::CssProvider` loaded at startup) · kind: stylesheet · **missing**
Classes defined: `.space-allocation-bar`, `.partition-bin`, `.partition-row`,
`.explanation-label`, and the 8 partition colours `.blue`, `.brown`,
`.green`, `.grey`, `.orange`, `.purple`, `.red`, `.yellow`. The `strength-*`
level-bar offsets are styled by Adwaita itself. All of these are applied from
`gdu-block-row.c` / `gdu-space-allocation-bar.c` / the password pages — none
is dead.

---

## 6. The second app: Disk Image Mounter

### `src/disk-image-mounter/application.rs` + `main.rs`
→ `lib/image_mounter_application.rb` · kind: application · **missing**
`Gtk.Application` (`HANDLES_OPEN`), action `app.quit`, accels
`app.quit` `<Control>q` and `window.close` `<Control>w`; `open` builds one
window per file.

### `src/resources/ui/gdu-image-mounter-window.blp` + `window.rs`
→ `lib/image_mounter_window.rb` · kind: window · **missing**

`Adw.ApplicationWindow` (500×730, min 360×640) → `Adw.ToolbarView`
(`top-bar-style: flat`) + `Adw.HeaderBar` (`show-title: false`) +
`Adw.ToastOverlay` `toast_overlay` + `Adw.StatusPage` `status_page`
(`media-optical-symbolic`, title bound to `$window_title(template.file)`) →
`Adw.Clamp` (max 400) → `Gtk.Box`:

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` | 5 | — | — | Open in Files / Unmount Disk Image (hidden unless mounted) / Edit Contents in Files / Write to Drive / Inspect in Disks, each with subtitle; three are `sensitive` on `$mountable(template.file)` |
| `Gtk.CheckButton` | 5 | — | property action `win.action` with targets `"open-in-files"`, `"unmount"`, `"open-in-files-writable"`, `"write"`, `"inspect"` | one radio group |
| `Gtk.Button` | 1 | `pill`, `suggested-action` | `on_continue_button` | label bound to `$button_label(template.continue-action)` |
| `Adw.Toast` | — | — | — | **error state**: one per action (“Could not mount…”, etc.) via `user_visible_error_msg` |

### `src/notify/gdusdmonitor.c` + `src/notify/main.c`
→ `lib/sd_monitor.rb` · kind: background notifier · **missing**
A session service that polls SMART and raises a notification —
“Hard Disk Problems Detected” / “A hard disk is likely to fail soon.” with an
“Examine” action that launches Disks. `libnotify` is not bound in
ruby-gnome; the port's equivalent is `Gio::Notification` +
`Gtk::Application#send_notification`. Lowest priority of the three apps.

---

## 7. Model layer the components need (no UI of their own)

| Upstream | → | Role |
|---|---|---|
| `src/disks/gdu-manager.c` | `lib/manager.rb` | the UDisks client, the drive list, `app.*` entry points |
| `src/disks/gdu-item.c` | `lib/item.rb` | base interface for drive/block tree items |
| `src/disks/gdu-drive.c` | `lib/drive.rb` | one drive, its features, its blocks |
| `src/disks/gdu-block.c` | `lib/block.rb` | one block/partition, its `color` data, its usage |
| `src/disks/gdu-job-manager.c`, `gdulocaljob.c`, `localjob.rs` | `lib/job_manager.rb`, `lib/local_job.rb` | the jobs behind `GduJobRow` |
| `src/disks/gduestimator.c`, `estimator.rs` | `lib/estimator.rb` | rate/time estimates in the job rows and the image dialogs |
| `src/disks/gdudvdsupport.c`, `gduxzdecompressor.c`, `page_aligned_buffer.rs` | `lib/dvd_support.rb`, `lib/xz_decompressor.rb`, — | disk-image read paths; the aligned buffer has no Ruby analogue |
| `src/libgdu/enums.rs`, `gduenums.h` | `lib/enums.rb` | format/resize/duration flag sets |

---

## 8. Translations

`po/` has **84 locales** (`po/LINGUAS`) and `po/POTFILES.in` lists 67 files —
37 sources plus 29 blueprint files and the 1 remaining `.ui`. Parity work:
`po/` on `ruby` does not exist yet; the port needs its own POT extracted with
`rake pot` (the dev shell carries `rxgettext`) and the upstream `.po`
catalogues carried over with the msgids re-keyed to the Ruby sources. The
GSettings schema `data/org.gnome.Disks.gschema.xml` (3 schemas:
`org.gnome.Disks` `image-dir-uri`, `.window-state` `window-state`,
`.benchmark` 4 keys) is also translated and also missing; the dev shell
already exports `GSETTINGS_SCHEMA_DIR=$PWD/data/schemas` for it.

## 9. Dead upstream component — do not port

`src/resources/ui/erase-multiple-disks-dialog.ui` is a GTK3-era
`GtkDialog` + `GtkButtonBox` + `GtkComboBox` that is still listed in
`gnome-disks.gresource.xml`, `src/resources/meson.build` and `po/POTFILES.in`
but is **loaded by no source file**. Record it as dead and skip it.

---

## Summary table

| # | Upstream | `lib/*.rb` | Kind | Exists |
|--:|---|---|---|:-:|
| 1 | `src/disks/main.c` | `lib/main.rb` | entry point | no |
| 2 | `src/disks/gdu-application.c` | `lib/application.rb` | application | partial |
| 3 | `src/resources/ui/gdu-window.blp` + `gdu-window.c` | `lib/window.rb` | window | no |
| 4 | `src/resources/ui/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | dialog | no |
| 5 | `gdu-drive-view.blp` + `.c` | `lib/drive_view.rb` | page + dialog | no |
| 6 | `gdu-drive-header.blp` + `.c` | `lib/drive_header.rb` | widget + menu | no |
| 7 | `gdu-drive-row.blp` + `.c` | `lib/drive_row.rb` | row | no |
| 8 | `gdu-block-row.blp` + `.c` | `lib/block_row.rb` | row + menu | no |
| 9 | `gdu-space-allocation-bar.c` | `lib/space_allocation_bar.rb` | widget | no |
| 10 | `gdu-job-row.blp` + `.c` | `lib/job_row.rb` | row | no |
| 11 | `gdu-format-disk-dialog.blp` + `.c` | `lib/format_disk_dialog.rb` | dialog | no |
| 12 | `gdu-benchmark-dialog.blp` + `.c` | `lib/benchmark_dialog.rb` | dialog | no |
| 13 | `gdu-benchmark-dialog.c` (`GduBenchmarkGraph`) | `lib/benchmark_graph.rb` | widget | no |
| 14 | `gdu-ata-smart-dialog.ui` + `.c` | `lib/ata_smart_dialog.rb` | dialog | no |
| 15 | `gdu-disk-settings-dialog.blp` + `.c` | `lib/disk_settings_dialog.rb` | dialog | no |
| 16 | `gdu-create-disk-image-dialog.blp` + `.c` | `lib/create_disk_image_dialog.rb` | dialog | no |
| 17 | `gdu-restore-disk-image-dialog.blp` + `restore_disk_image_dialog.rs` | `lib/restore_disk_image_dialog.rb` | dialog | no |
| 18 | `gdu_combo_row.rs` | `lib/combo_row.rb` | widget | no |
| 19 | `gdu-new-disk-image-dialog.blp` + `.c` | `lib/new_disk_image_dialog.rb` | dialog | no |
| 20 | `gdu-attach-disk-image-dialog.blp` + `.c` | `lib/attach_disk_image_dialog.rb` | dialog | no |
| 21 | `gdu-format-volume-dialog.blp` + `.c` | `lib/format_volume_dialog.rb` | dialog (wizard) | no |
| 22 | `gdu-create-partition-page.blp` + `.c` | `lib/create_partition_page.rb` | page | no |
| 23 | `gdu-create-filesystem-page.blp` + `.c` | `lib/create_filesystem_page.rb` | page | no |
| 24 | `gdu-create-other-page.blp` + `.c` | `lib/create_other_page.rb` | page | no |
| 25 | `gdu-create-password-page.blp` + `.c` | `lib/create_password_page.rb` | page | no |
| 26 | `gdu-create-confirm-page.blp` + `.c` | `lib/create_confirm_page.rb` | page | no |
| 27 | `gdu-edit-filesystem-dialog.blp` + `.c` | `lib/edit_filesystem_dialog.rb` | dialog | no |
| 28 | `gdu-edit-partition-dialog.blp` + `.c` | `lib/edit_partition_dialog.rb` | dialog | no |
| 29 | `gdu-resize-volume-dialog.blp` + `.c` | `lib/resize_volume_dialog.rb` | dialog | no |
| 30 | `gdu-change-passphrase-dialog.blp` + `.c` | `lib/change_passphrase_dialog.rb` | dialog | no |
| 31 | `gdu-unlock-dialog.blp` + `.c` | `lib/unlock_dialog.rb` | dialog | no |
| 32 | `gdu-mount-options-dialog.blp` + `.c` | `lib/mount_options_dialog.rb` | dialog | no |
| 33 | `gdu-encryption-options-dialog.blp` + `.c` | `lib/encryption_options_dialog.rb` | dialog | no |
| 34 | `gdu-take-ownership-dialog.blp` | `lib/take_ownership_dialog.rb` | dialog | no |
| 35 | `src/libgdu/gduutils.c` + `.rs` | `lib/utils.rb` | helpers + 3 dialogs | no |
| 36 | `src/resources/style.css` | `lib/style.rb` | stylesheet | no |
| 37 | `src/disk-image-mounter/application.rs` + `main.rs` | `lib/image_mounter_application.rb` | application | no |
| 38 | `gdu-image-mounter-window.blp` + `window.rs` | `lib/image_mounter_window.rb` | window | no |
| 39 | `src/notify/gdusdmonitor.c` + `main.c` | `lib/sd_monitor.rb` | notifier | no |
| 40 | `src/disks/gdu-manager.c` | `lib/manager.rb` | model | no |
| 41 | `src/disks/gdu-item.c` | `lib/item.rb` | model | no |
| 42 | `src/disks/gdu-drive.c` | `lib/drive.rb` | model | no |
| 43 | `src/disks/gdu-block.c` | `lib/block.rb` | model | no |
| 44 | `gdu-job-manager.c` + `gdulocaljob.c` | `lib/job_manager.rb`, `lib/local_job.rb` | model | no |
| 45 | `gduestimator.c` + `estimator.rs` | `lib/estimator.rb` | model | no |
| 46 | `src/libgdu/enums.rs` + `gduenums.h` | `lib/enums.rb` | model | no |
| — | `erase-multiple-disks-dialog.ui` | — | dead | n/a |

## Blockers to settle before any port unit is written

1. **No UDisks2 in the dev shell, and no Ruby UDisks binding.** Every
   component above is driven by `UDisksClient`. `flake.nix`'s `gtkStack` has
   no `udisks` and `typelibPath` therefore carries no `UDisks-2.0.typelib`,
   so `GObjectIntrospection` cannot load it. Decide and record: add `udisks`
   to the flake and bind through `gobject-introspection`, or drive
   `udisksctl`/D-Bus (`Gio::DBusProxy`) directly, or ship a fake device
   layer for the UI units. Until this is chosen, every unit past the window
   shell is blocked on data.
2. **The port's file layout does not match the house shape.** The existing
   scaffold is `lib/gnome_disk_utility/application.rb` inside a
   `GnomeDiskUtility` module; the pilot is flat `lib/<thing>.rb` with classes
   subclassing Adwaita widgets directly. Pick one before the second file
   lands — this inventory assumes the pilot's flat layout.
3. **Two upstream action gaps not to copy.** `app.shortcuts` is referenced by
   the main menu and an accel but never installed, and none of the ten
   `win.*` accelerated actions exists anywhere. The port should install both
   sets (on the application and the window respectively) and route them to
   the `view.*`/`row.*` handlers.
4. **Deprecated upstream widgets.** `Gtk.TreeView`/`Gtk.ListStore` (SMART
   dialog) and `Gtk.ComboBoxText` (disk settings) are GTK3 leftovers; the
   port should use `Gtk::ColumnView` + `SignalListItemFactory` and
   `Adw::ComboRow` + `Gtk::StringList`, and say so in each file's comment.
5. **Blueprint-only constructs with no Ruby equivalent yet verified.**
   `Adw.MultiLayoutView` / `Adw.Layout` / `Adw.LayoutSlot` (drive header),
   `Adw.Breakpoint` setters, `Adw.ShortcutsDialog`, `Adw.ButtonRow`,
   `Adw.Spinner` and `Gtk.LevelBar` offsets all need a constructor check in
   the dev shell before they are used — the `ruby-gtk` skill's
   adwaita-quirks reference is the place to record what each one turns out
   to need.
6. **No `po/` and no GSettings schema on `ruby`.** 84 locales and 3 schemas
   to carry; the dev shell already looks for `data/schemas`.
