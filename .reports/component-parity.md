# gnome-disk-utility-rb — component parity (refresh)

Supersedes the component-parity.md committed at `2632264e` (written before
`9e5734a0` ported the drive view, drive header, block row and format-volume
wizard; that earlier report's "14/46, 0 confirmed" numbers are stale and
understate current progress — but the picture is still **no parity**).

Based this pass on `component-identification.md` (refreshed alongside this
file) plus direct reads of the files below.

## Files present: count vs. behaviour

| File | Structurally present | Behaviour gap |
|---|---|---|
| `lib/main.rb` | yes | self-documented: `app.new_disk_image`/`app.attach_disk_image` actions deliberately unregistered (their dialogs don't exist); 7 of 9 accelerated `win.*` actions (`open-drive-menu`, `open-volume-menu`, `format-disk`, `restore-disk-image`, `view-smart`, `disk-settings`, `format-partition`) have accelerators bound in `ACTION_ACCELS` but no action installed in `window_actions` — the keys do nothing |
| `lib/window.rb` | yes | empty/drive-page stack switching present; no GSettings schema exists for the window-state binding it attempts |
| `lib/drive_view.rb` | yes | self-documented: only 2 of 11 `view.*` actions installed (`format`, `show-drive-dialog`); `create-image`, `restore-image`, `benchmark`, `smart`, `settings`, `standby`, `wakeup`, `detach`, `eject`, `poweroff` are all unwired because their target dialogs/Drive methods don't exist |
| `lib/drive_header.rb` | yes | its menu's items route through `drive_view`'s action group, so the same 9 unwired actions apply here too |
| `lib/block_row.rb` | yes | `row.create_partition` wired; upstream's volume-level actions on the block menu (resize, edit filesystem, edit partition, change passphrase, unlock, mount options) have no destination dialog, so not independently re-verified for wiring beyond what the drive script's components cover |
| `lib/format_volume_dialog.rb` + 5 wizard pages | yes | `CreateFilesystemPage` has a known, left-failing bug (row sensitivity resets once realized — recorded in `drive-findings.md`, not fixed) |
| `lib/take_ownership_dialog.rb` | yes | default-response bug fixed this cycle (per `drive-findings.md`) |
| model layer (`manager.rb`, `drive.rb`, `block.rb`, `item.rb`, `job_manager.rb`, `local_job.rb`, `estimator.rb`, `enums.rb`) | yes | `drive.rb`'s own class comment admits `#features` never sets `GDU_FEATURE_SMART`/`GDU_FEATURE_SETTINGS`; `manager.rb`'s `gdu_manager_open_loop_async` not ported (self-recorded) |
| `lib/style.rb`, `lib/space_allocation_bar.rb`, `lib/combo_row.rb`, `lib/job_row.rb`, `lib/drive_row.rb`, `lib/shortcuts_dialog.rb`, `lib/utils.rb` | yes | not independently re-verified rule-for-rule/signal-for-signal against upstream source this pass beyond what `test/drive_gnome_disk_utility.rb` exercises |

## Files absent: 16 dialogs/windows, zero axes hold

For every one of the 16 missing UI units named in `component-identification.md`
(ATA SMART, attach/create/new/restore disk image, benchmark + graph, change
passphrase, disk settings, edit filesystem, edit partition, encryption
options, format disk, mount options, resize volume, unlock, erase-multiple-disks,
and the entire Disk Image Mounter window) there is no file, so there is no
count, style, behaviour or text to compare. Any menu item or button that
would open one of these in upstream exists in the port's menus/headers only
as inert chrome.

## Verdict

Not clean. Structurally, most of the *built* surface area (drive list,
one drive's page, the format-volume wizard) now exists and the drive script
exercises it without crashing. But:

- 16 of 33 upstream dialogs/windows are entirely unbuilt.
- 9 of 11 `view.*` drive actions and 7 of 9 accelerated `win.*` actions are
  unwired — present in the menu as dead entries.
- The Disk Image Mounter app and the udisks2 notifier are wholly absent.
- Zero translation infrastructure (see `translation-parity.md`).

A user who picks a drive and opens its menu hits a wall on all but two
items (Format Disk, Drive Information). This is a partial port with real,
working pieces — not a port at parity.
