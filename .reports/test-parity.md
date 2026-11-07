# gnome-disk-utility-rb — test parity (refresh)

## Upstream has no test suite to port

`git ls-tree -r --name-only origin/main | grep -i test` returns nothing —
upstream C/Rust gnome-disk-utility ships no unit or integration tests. So
"port every upstream test" is vacuously satisfied: there is nothing to port.
That does **not** mean the port's own behaviour is verified; it means the
bar for verification is entirely the port's own drive script.

## The drive script: real, runs, 153/153 — but narrow

Ran fresh this pass:
`nix develop --command xvfb-run -a ruby test/drive_gnome_disk_utility.rb`
→ **153 of 153 checks passed, DRIVE OK.** This matches the stated gate.

Listing every `d.check` block's surrounding scenario, the script exercises
exactly these components/behaviours (19, matching the gate's own count):
window + sidebar + drive row + selection, main menu structure, the two
dialog-less menu actions' absence, shortcuts dialog, about dialog, a real
Escape keypress reaching `win.go-back`, `win.open-app-menu`, job manager +
job row lifecycle (enqueue/run/finish/cancel/dequeue), close-request
veto/confirmation, CLI option validation, `ComboRow`, `TakeOwnershipDialog`,
`SpaceAllocationBar`, `CreatePartitionPage`, `CreateFilesystemPage`,
`CreateOtherPage`, `CreateConfirmPage`, `Utils`, `Enums::Flags`, `Style`,
`Estimator`.

## Components in `lib/` that the drive script never touches at all

- **`lib/create_password_page.rb`** — zero checks. Not instantiated, not
  rendered, no property behaviour (strength meter, confirm-match, visibility
  toggle) verified anywhere in the suite.
- **`lib/drive_header.rb`** — zero checks. The window's selection test only
  asserts the stack switches to the drive page and that
  `win.drive_view.drive == row.drive`; it never looks inside
  `drive_header` (its layout-view breakpoint switch, its menu, its
  "Drive Information" button).
- **`lib/block_row.rb`** — zero checks. The fake drive used throughout has
  no partitions/blocks attached, so `BlockRow` (and the drive view's
  `drive_partitions_listbox` repeater over it) never renders in the suite.
  Combined with `drive_view`'s 9 unwired `view.*` actions
  (`component-parity.md`), this is the single largest unverified surface in
  a currently-built file — it is the row a user sees for every real
  partition on every real disk.
- **`lib/format_volume_dialog.rb`** (the wizard dialog itself, as opposed to
  its 5 pages, which the script does drive individually) — no check opens
  the dialog end to end, pages a `Gtk::Stack`/`Adw.NavigationView` through
  it, or exercises its Cancel/Create button wiring as a whole.
- **`lib/manager.rb` / `lib/drive.rb` / `lib/block.rb`** — exercised only
  through a hand-built fake `Drive` object (`fake_drive`-style helpers), not
  through `Manager.default`'s real UDisks-backed path beyond "degrades to
  zero drives with no daemon" (`d.check[0]`). `Drive#features`'s
  self-admitted SMART/settings gap and `Manager`'s missing
  `gdu_manager_open_loop_async` are untested by construction — there is no
  real daemon in this environment to test them against either way.

## The `spec/` suite has never once executed

`spec/` contains only `spec_helper.rb` (no example files). That helper
`require`s `kettle/test/rspec`, which is **not in the dev shell's runtime gem
closure** (deliberately, per `drive-findings.md` — the shell carries the
app's runtime closure, not the kettle-dev development bundle). Running the
dev shell's own banner-printed spec command errors immediately:
`0 examples, ... 2 errors occurred outside of examples`. Confirmed again
this pass — unchanged since the last report. **A suite that has never been
executed is a gap, stated plainly: the scaffold spec harness is not a
verification path for this port at all, today.**

## Verdict

Not clean. The drive script is real and its 153/153 is accurate, but it
covers roughly 19 of the ~33 UI units that exist or are mapped, and three
currently-*built* files (`create_password_page.rb`, `drive_header.rb`,
`block_row.rb`) plus the wizard dialog's own wiring have zero checks. The 16
wholly-missing dialogs (see `component-identification.md`) have, naturally,
zero tests as well. The scaffold `spec/` suite has never run.
