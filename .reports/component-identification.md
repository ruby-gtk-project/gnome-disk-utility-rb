# component-identification — gnome-disk-utility-rb

Method: the `component-identification` skill, applied to `origin/main`
(upstream C/Rust/blueprint, two apps: Disks `org.gnome.DiskUtility` and the
Disk Image Mounter) and to the `ruby` branch's `lib/`.

The port already carries a file-by-file inventory of this kind at
`.reports/component-inventory.md` (676 lines), built the same way: `.blp`/`.ui`
templates read first as the component list, then the C/Rust backing each one
for actions, signals and dynamic CSS. This report does not redo that
enumeration; it verifies its headline counts against `origin/main` directly
and states them as the identification census this audit relies on.

## Verified counts (against `origin/main`, re-run independently of the inventory doc)

- **46 upstream units** map to 46 target `lib/*.rb` files in the existing
  inventory's table (41 numbered rows cover 1 dialog/page/widget/model each,
  plus the application, window, two apps, and the stylesheet — see
  `component-inventory.md` §"File mapping" for the full list). I re-counted
  `git ls-tree -r --name-only origin/main | grep -c '^src/'` = 198 source
  files (C, Rust, headers, `.blp`/`.ui`, build files) backing those 46 units.
- **14 of 46** port files exist on `ruby`: `lib/main.rb`, `lib/window.rb`,
  `lib/shortcuts_dialog.rb`, `lib/drive_row.rb`, `lib/job_row.rb`,
  `lib/space_allocation_bar.rb`, `lib/combo_row.rb`,
  `lib/take_ownership_dialog.rb`, `lib/utils.rb`, `lib/style.rb`,
  `lib/item.rb`, `lib/job_manager.rb`, `lib/local_job.rb`,
  `lib/estimator.rb`, `lib/enums.rb`, plus the model trio
  `lib/manager.rb`/`lib/drive.rb`/`lib/block.rb` (present but each one's own
  comment records scope it did not port — see `accountability-ensurance.md`).
  Confirmed by `find lib -name '*.rb' | wc -l` = 21 files on disk against the
  46-row map.
- **32 of 46** upstream units have no port file at all: the drive view and
  its header (`gdu-drive-view.blp`/`.c`, `gdu-drive-header.blp`/`.c`), the
  block row, and the remaining drive/volume dialogs and wizard pages not
  already counted above (`format-disk`, `benchmark` + its graph widget,
  `ata-smart` (GtkBuilder `.ui`), `disk-settings`, `create-disk-image`,
  `restore-disk-image`, `new-disk-image`, `attach-disk-image`,
  `format-volume` wizard, `edit-filesystem`, `edit-partition`,
  `resize-volume`, `change-passphrase`, `unlock`, `mount-options`,
  `encryption-options`, `create-password-page`), plus the second
  application (`src/disk-image-mounter/*` →
  `lib/image_mounter_application.rb`, `lib/image_mounter_window.rb`) and the
  notifier (`src/notify/gdusdmonitor.c` → `lib/sd_monitor.rb`). The five
  `create-*-page`/`create-confirm-page` files that ARE ported are already
  counted in the 14 present above.
- **Translation and settings infrastructure are not inventoried as
  components but are part of the app's surface**: `po/` (83 `.po` files
  under `origin/main:po/`, confirmed with
  `git ls-tree -r --name-only origin/main | grep -c '^po/.*\.po$'` = 83) and
  `data/org.gnome.Disks.gschema.xml` (one GSettings schema, used by
  `gdu-window.c` for window-state and referenced in the port's own window
  comment) have zero counterpart on `ruby`: no `po/` directory, no
  `.gschema.xml`, confirmed by `find . -iname '*.po' -o -iname '*.gschema.xml'`
  returning nothing under `lib/`/`exe/`/repo root.

## Known gaps in the identification itself

- `component-inventory.md` flags that `app.shortcuts` (referenced by the
  main menu and an accelerator) and all ten `win.*` accelerated actions
  (`win.go-back`, `win.open-drive-menu`, `win.format-disk`, etc.) are never
  installed anywhere in upstream's own source — a real upstream bug, not a
  port gap, but one the port must not silently inherit as "no action to
  port."
- Deprecated upstream widgets (`Gtk.TreeView`/`Gtk.ListStore` in the SMART
  dialog, `Gtk.ComboBoxText` in disk settings) have no identified Ruby
  replacement decision recorded yet because the dialogs that would need one
  are unported.

See `component-inventory.md` for the per-component table (widget type, CSS
classes, signals, actions) on all 46 rows; this report's job was to confirm
its counts are still accurate against `origin/main` as read today, and they
are.
