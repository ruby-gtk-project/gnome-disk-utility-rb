# gnome-disk-utility-rb — component parity (refresh 2)

Supersedes the component-parity.md committed at `8af7c1b5` (written before
`d80421e5` ported `EditFilesystemDialog`). Based on
`component-identification.md` (refreshed alongside this file) plus direct
reads of the files below and the fresh drive run (161/161, see
test-parity.md).

## Files present: count vs. behaviour

| File | Structurally present | Behaviour gap |
|---|---|---|
| `lib/main.rb` | yes | self-documented: `app.new_disk_image`/`app.attach_disk_image` actions unregistered (their dialogs don't exist); 7 of 9 accelerated `win.*` actions (`open-drive-menu`, `open-volume-menu`, `format-disk`, `restore-disk-image`, `view-smart`, `disk-settings`, `format-partition`) have accelerators bound in `ACTION_ACCELS` but no action installed in `window_actions` — the keys do nothing |
| `lib/window.rb` | yes | empty/drive-page stack switching present; no GSettings schema exists for the window-state binding it attempts |
| `lib/drive_view.rb` | yes | self-documented: only 2 of 11 `view.*` actions installed (`format`, `show-drive-dialog`); `create-image`, `restore-image`, `benchmark`, `smart`, `settings`, `standby`, `wakeup`, `detach`, `eject`, `poweroff` are all unwired because their target dialogs/Drive methods don't exist |
| `lib/drive_header.rb` | yes | its menu's items route through `drive_view`'s action group, so the same 9 unwired actions apply here too; **zero checks drive this file directly** (see test-parity.md) |
| `lib/block_row.rb` | yes | `row.create_partition` and (new this round) `row.edit_filesystem` wired to `EditFilesystemDialog`; upstream's other volume-level actions on the block menu (resize, edit partition, change passphrase, unlock, mount options, configure-fstab/crypttab, lock, check-fs, repair-fs, benchmark-partition, partition-image actions) still have no destination dialog; **zero checks drive `BlockRow` itself** — the `EditFilesystemDialog` check instantiates the dialog directly, not through a `BlockRow`'s menu action, so the wiring line (`add_action(group, 'edit_filesystem') { edit_filesystem }`) is still unexercised by any check |
| `lib/edit_filesystem_dialog.rb` | **yes — new this round** | Change-button sensitivity, error styling, and the unmount-warning banner are all driven (8 checks); `Block#set_fs_label_async` call confirmed. Not independently re-verified: the dialog's own Cancel path, and behaviour when the new label is rejected by UDisks (the check only asserts the happy-path call-through, not an error response from `set_fs_label_async`) |
| `lib/format_volume_dialog.rb` + 5 wizard pages | yes | `CreateFilesystemPage` row-sensitivity bug from the prior round is fixed (per `e29bdbfd`); `create_password_page.rb` remains built but has **zero** checks of any kind — not instantiated anywhere in the suite |
| `lib/take_ownership_dialog.rb` | yes | driven, default-response bug from a prior round stays fixed |
| model layer (`manager.rb`, `drive.rb`, `block.rb`, `item.rb`, `job_manager.rb`, `local_job.rb`, `estimator.rb`, `enums.rb`) | yes | `drive.rb`'s own class comment admits `#features` never sets `GDU_FEATURE_SMART`/`GDU_FEATURE_SETTINGS`; `manager.rb`'s `gdu_manager_open_loop_async` not ported (self-recorded); both gaps unchanged this round |
| `lib/style.rb`, `lib/space_allocation_bar.rb`, `lib/combo_row.rb`, `lib/job_row.rb`, `lib/drive_row.rb`, `lib/shortcuts_dialog.rb`, `lib/utils.rb` | yes | not independently re-verified rule-for-rule/signal-for-signal against upstream source this pass beyond what `test/drive_gnome_disk_utility.rb` exercises |

## Files absent: 15 dialogs/windows, zero axes hold

For every one of the 15 missing UI units named in `component-identification.md`
(ATA SMART, attach/create/new/restore disk image, benchmark + graph, change
passphrase, disk settings, edit partition, encryption options, format disk,
mount options, resize volume, unlock, erase-multiple-disks, and the entire
Disk Image Mounter window) there is no file, so there is no count, style,
behaviour or text to compare. Any menu item or button that would open one of
these in upstream exists in the port's menus/headers only as inert chrome.

## Stylesheet check

`lib/style.rb`'s "the application stylesheet parses with no errors swallowed"
check passes, but the drive run emits a `GLib-CRITICAL:
g_atomic_rc_box_release_full: assertion 'real_box->magic == G_BOX_MAGIC'
failed` during that exact step (see raw drive output, step 52). The check's
assertion (`ok`) still reports green because it only asserts the provider
loaded with no *Ruby* exception — a GLib-level memory-management assertion
failure underneath a passing check is exactly the shape of false-green this
round's audit was told to hunt for. Recorded here and in
`accountability-ensurance.md`; not independently root-caused this pass.

## Verdict

Not clean. One dialog (`EditFilesystemDialog`) crossed from absent to present
and driven since the last report, which is real progress. But:

- 15 of 33 upstream dialogs/windows are entirely unbuilt.
- 9 of 11 `view.*` drive actions and 7 of 9 accelerated `win.*` actions are
  still unwired — present in the menu as dead entries.
- The Disk Image Mounter app and the udisks2 notifier are wholly absent.
- Zero translation infrastructure (see `translation-parity.md`).
- `block_row.rb`, `drive_header.rb` and `create_password_page.rb` are built
  but have no check exercising them at all — "present" is not "verified".
- A GLib-level critical assertion fires during a passing check (style.rb,
  step 52) and nothing in the suite or prior reports flagged it.

A user who picks a drive and opens its menu hits a wall on all but a
handful of items (Format Disk, Drive Information, now Edit Filesystem Label).
This is a partial port with real, working pieces — not a port at parity.
