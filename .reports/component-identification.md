# gnome-disk-utility-rb — component identification (refresh)

Supersedes the component-identification/inventory snapshots committed before
`9e5734a0` (drive view, block row, format-volume wizard) and `e29bdbfd`. This
pass re-walked `origin/main`'s tree (`git ls-tree -r --name-only origin/main`)
against the current `lib/` on `ruby` as of this commit.

Upstream ships **two GApplications and one daemon** in one tree:

| Unit | Upstream entry | Port target | Status |
|---|---|---|---|
| Disks | `src/disks/main.c` + `gdu-application.c` | `lib/main.rb` | present, with two self-documented action gaps |
| Disk Image Mounter | `src/disk-image-mounter/{main,application,window}.rs` | — | **absent** — no file anywhere in `lib/` or `exe/` |
| udisks2 notifier | `src/notify/{main.c,gdusdmonitor.c}` | — | **absent** |

## Upstream UI/dialog units (from `src/resources/ui/*.blp` + `*.ui` + their `.c`/`.rs`)

29 blueprint files + 2 GtkBuilder `.ui` files = 31 declarative units, plus the
code-only `gdu-space-allocation-bar.c` (custom `GtkWidget`, no `.blp`) and the
Rust `gdu_combo_row.rs`. Current `lib/` file-for-file match:

| Upstream | Port file | Present? |
|---|---|---|
| gdu-window.blp | lib/window.rb | yes |
| shortcuts-dialog.blp | lib/shortcuts_dialog.rb | yes |
| gdu-drive-row.blp | lib/drive_row.rb | yes |
| gdu-drive-header.blp | lib/drive_header.rb | yes |
| gdu-drive-view.blp | lib/drive_view.rb | yes |
| gdu-block-row.blp | lib/block_row.rb | yes |
| gdu-job-row.blp | lib/job_row.rb | yes |
| gdu-space-allocation-bar.c | lib/space_allocation_bar.rb | yes |
| gdu_combo_row.rs | lib/combo_row.rb | yes |
| gdu-take-ownership-dialog.blp | lib/take_ownership_dialog.rb | yes |
| gdu-format-volume-dialog.blp | lib/format_volume_dialog.rb | yes |
| gdu-create-partition-page.blp | lib/create_partition_page.rb | yes |
| gdu-create-filesystem-page.blp | lib/create_filesystem_page.rb | yes |
| gdu-create-other-page.blp | lib/create_other_page.rb | yes |
| gdu-create-confirm-page.blp | lib/create_confirm_page.rb | yes |
| gdu-create-password-page.blp | lib/create_password_page.rb | yes |
| gdu-ata-smart-dialog.ui | — | **no** |
| gdu-attach-disk-image-dialog.blp | — | **no** |
| gdu-benchmark-dialog.blp (+ benchmark graph) | — | **no** |
| gdu-change-passphrase-dialog.blp | — | **no** |
| gdu-create-disk-image-dialog.blp | — | **no** |
| gdu-disk-settings-dialog.blp | — | **no** |
| gdu-edit-filesystem-dialog.blp | — | **no** |
| gdu-edit-partition-dialog.blp | — | **no** |
| gdu-encryption-options-dialog.blp | — | **no** |
| gdu-format-disk-dialog.blp | — | **no** |
| gdu-mount-options-dialog.blp | — | **no** |
| gdu-new-disk-image-dialog.blp | — | **no** |
| gdu-resize-volume-dialog.blp | — | **no** |
| gdu-restore-disk-image-dialog.blp | — | **no** |
| gdu-unlock-dialog.blp | — | **no** |
| erase-multiple-disks-dialog.ui | — | **no** |
| gdu-image-mounter-window.blp | — | **no** (whole second app absent) |

**16 of 33 declarative UI units have no port file at all.** Every menu item,
keyboard accelerator and action that opens one of those 16 is dead in the
port: GTK will render the triggering button/menu row, but activating it does
nothing (no handler exists) or the action was never installed.

## Non-UI upstream pieces also checked

- `data/org.gnome.Disks.gschema.xml` — GSettings schema `gdu-window.c` binds
  window-state to. No `.gschema.xml` exists anywhere in this repo; `lib/window.rb`
  cannot actually persist window state against a real schema.
- `po/` — 88 files, including `POTFILES.in` listing every translatable
  source and ~724 `msgid`s in a representative locale (`ar.po`). The port has
  **no `po/` directory, no `.pot`, no gettext/FastGettext call anywhere in
  `lib/` or `exe/`** (`grep -rn "gettext\|_(" lib exe` matches only a code
  comment in `lib/utils.rb` quoting the upstream C macro, not a call). See
  `translation-parity.md`.
- `app.shortcuts` — referenced by `lib/main.rb`'s menu and wired to a real
  `Gio::SimpleAction` (`register_actions`) — this one upstream gap the port
  *does* close, correctly noted in the file's own class comment.
- `win.*` actions — upstream's `ACTION_ACCELS` table (ported verbatim into
  `App::ACTION_ACCELS`) binds 9 `win.*` actions to accelerators, but
  `window_actions` in `lib/main.rb` only ever installs 2 of them
  (`go-back`, `open-app-menu`). The other 7 (`open-drive-menu`,
  `open-volume-menu`, `format-disk`, `restore-disk-image`, `view-smart`,
  `disk-settings`, `format-partition`) have accelerators bound to actions
  that do not exist in the window's action group — pressing F9, Ctrl+D,
  Ctrl+S, Ctrl+E, Ctrl+P etc. does nothing. Two of those seven
  (`open-drive-menu`/`open-volume-menu`) could be wired today against the
  existing `drive_header`/`block_row` menu buttons; five cannot be, because
  their target dialogs don't exist yet.

## Empty / error states

- Window's "No Device Selected" `Adw.StatusPage` empty state: present
  (`lib/window.rb`), matches upstream copy and icon.
  Not independently re-verified against drive-selected / drive-removed
  transitions beyond what the drive script exercises.
  - No empty/error state exists for any of the 16 missing dialogs, trivially
  (there's no dialog to have one).

## Bottom line

**17 of 33 upstream UI units present** (16 absent dialogs/windows + the
second app's window), plus the whole Disk Image Mounter application and the
udisks2 notifier daemon absent, plus zero translation infrastructure, plus
7 of 9 accelerated `win.*` actions pointing at nothing. This is a
substantially incomplete port, not a nearly-finished one.
