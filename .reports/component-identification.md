# gnome-disk-utility-rb — component identification (refresh 2)

Supersedes the snapshot committed at `8af7c1b5` (written before `d80421e5`
ported `EditFilesystemDialog` and before `6bcfff9e` hardened the Escape-key
check). Re-walked `origin/main`'s tree
(`git ls-tree -r --name-only origin/main`) against `lib/` on `ruby` as of
this commit (`6bcfff9e`).

Upstream ships **two GApplications and one daemon** in one tree:

| Unit | Upstream entry | Port target | Status |
|---|---|---|---|
| Disks | `src/disks/main.c` + `gdu-application.c` | `lib/main.rb` | present, with self-documented action gaps |
| Disk Image Mounter | `src/disk-image-mounter/{main,application,window}.rs` | — | **absent** — no file anywhere in `lib/` or `exe/` |
| udisks2 notifier (`gnome-disk-utility-notify`, standby monitor) | `src/notify/{main.c,gdusdmonitor.c}` | — | **absent** |

## Upstream UI/dialog units (from `src/resources/ui/*.blp` + `*.ui` + their `.c`/`.rs`)

29 blueprint files + 2 GtkBuilder `.ui` files = 31 declarative units, plus the
code-only `gdu-space-allocation-bar.c` (custom `GtkWidget`, no `.blp`) and the
Rust `gdu_combo_row.rs` = 33 total. Current `lib/` match:

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
| gdu-create-password-page.blp | lib/create_password_page.rb | yes (built, never run — see test-parity.md) |
| **gdu-edit-filesystem-dialog.blp** | **lib/edit_filesystem_dialog.rb** | **yes — new this round** |
| gdu-ata-smart-dialog.ui | — | **no** |
| gdu-attach-disk-image-dialog.blp | — | **no** |
| gdu-benchmark-dialog.blp (+ benchmark graph) | — | **no** |
| gdu-change-passphrase-dialog.blp | — | **no** |
| gdu-create-disk-image-dialog.blp | — | **no** |
| gdu-disk-settings-dialog.blp | — | **no** |
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

**15 of 33 declarative UI units still have no port file.** `EditFilesystemDialog`
moved from absent to present this round; everything else named "no" in the
prior round is still absent. Every menu item, keyboard accelerator and action
that opens one of those 15 is dead in the port: GTK renders the triggering
button/menu row, but activating it either does nothing (no handler) or the
action was never installed, exactly as before.

## Non-UI upstream pieces also checked

- `data/org.gnome.Disks.gschema.xml` — GSettings schema `gdu-window.c` binds
  window-state to. No `.gschema.xml` exists anywhere in this repo; `lib/window.rb`
  cannot persist window state against a real schema. Unchanged.
- `po/` — 88 files including `POTFILES.in` and ~724 `msgid`s in a
  representative locale. The port still has **no `po/` directory, no `.pot`,
  no gettext call anywhere in `lib/` or `exe/`** — unchanged, confirmed again
  this pass (`grep -rn "gettext\|FastGettext" lib exe` is empty of any real
  call). See `translation-parity.md`.
- `win.*` actions — upstream's `ACTION_ACCELS` table binds 9 `win.*` actions
  to accelerators; `window_actions` in `lib/main.rb` still only installs 2 of
  them (`go-back`, `open-app-menu`). The other 7 (`open-drive-menu`,
  `open-volume-menu`, `format-disk`, `restore-disk-image`, `view-smart`,
  `disk-settings`, `format-partition`) remain bound to accelerators with no
  action in the window's action group. Unchanged this round.

## Newly checked: EditFilesystemDialog's own action surface

`lib/edit_filesystem_dialog.rb` ports `gdu-edit-filesystem-dialog.blp`/`.c`.
It is reachable from `BlockRow`'s menu (`action_group.lookup('edit_filesystem')`
gated on `Enums::Feature::EDIT_LABEL`) and is exercised by the drive script
(`test/drive_gnome_disk_utility.rb:880`, "EditFilesystemDialog disables
Change until the label actually changes" — 8 checks). This is the one
dialog this round that has both a port file **and** a driven check, which
puts it ahead of `create_password_page.rb` (built, never driven) and
`block_row.rb`/`drive_header.rb` (built, never driven at all — see
test-parity.md).

## Empty / error states

- Window's "No Device Selected" `Adw.StatusPage` empty state: present
  (`lib/window.rb`), matches upstream copy and icon. Unchanged.
- No empty/error state exists for any of the 15 still-missing dialogs,
  trivially (there is no dialog to have one).
- `EditFilesystemDialog`'s own error state (the label entry row turning
  `.error` + disabling Change on an invalid/unchanged label) is present and
  driven. Its "unmount warning" banner for a mounted filesystem is also
  present and driven.

## Bottom line

**18 of 33 upstream UI units present** (15 absent dialogs/windows), plus the
whole Disk Image Mounter application and the udisks2 notifier daemon
absent, plus zero translation infrastructure, plus 7 of 9 accelerated
`win.*` actions pointing at nothing. One dialog (`EditFilesystemDialog`)
closed since the last report; the shape of the gap is otherwise unchanged.
This is a substantially incomplete port, not a nearly-finished one.
