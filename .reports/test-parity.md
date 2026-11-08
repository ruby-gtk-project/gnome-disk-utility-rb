# gnome-disk-utility-rb — test parity (refresh 2)

## Upstream has no test suite to port

`git ls-tree -r --name-only origin/main | grep -i test` returns nothing —
upstream C/Rust gnome-disk-utility ships no unit or integration tests.
Unchanged from the prior report: "port every upstream test" is vacuously
satisfied because there is nothing to port. That does **not** verify the
port's own behaviour; the bar for verification is entirely the port's own
drive script.

## The drive script: real, runs, 161/161 — but still narrow

Ran fresh this pass:
`nix develop --command xvfb-run -a ruby test/drive_gnome_disk_utility.rb`
→ **161 of 161 checks passed, DRIVE OK.** This matches the stated runtime
gate for this round exactly (161 checks, 0 failed).

The new step since the last report is
`d.step("EditFilesystemDialog disables Change until the label actually
changes")` (8 checks, line 880) — this is the whole of this round's test
growth (153 → 161 = +8, all from the one new dialog).

**A GLib-level critical fires during a passing check.** The raw run prints:

```
[52] the application stylesheet parses with no errors swallowed
    ok   the stylesheet parses cleanlyGLib-CRITICAL **: g_atomic_rc_box_release_full: assertion 'real_box->magic == G_BOX_MAGIC' failed
	from test/drive_gnome_disk_utility.rb:0
```

The check still reports `ok` — it only asserts that loading the CSS provider
raised no Ruby exception — but a GTK/GLib object was released with a bad
magic number underneath it, which is a real memory-safety assertion failure
in C code the Ruby binding called into, not a cosmetic warning. "161 of 161
passed" is true and is simultaneously compatible with a critical assertion
firing mid-run. Not independently root-caused or bisected this pass; flagged
here and in `accountability-ensurance.md` as exactly the false-green shape
this round was told to hunt for — nothing before this report mentioned it,
and the gate's own "161 passed, 0 failed" headline gives no sign of it.

Listing every `d.step` block's surrounding scenario, the script exercises
these components/behaviours (20, matching the gate's own count): window +
sidebar + drive row + selection, main menu structure, the two dialog-less
menu actions' absence, shortcuts dialog, about dialog, a real Escape
keypress reaching `win.go-back`, `win.open-app-menu`, job manager + job row
lifecycle (enqueue/run/finish/cancel/dequeue), close-request
veto/confirmation, CLI option validation, `ComboRow`, `TakeOwnershipDialog`,
`SpaceAllocationBar`, `CreatePartitionPage`, `CreateFilesystemPage`,
`CreateOtherPage`, `CreateConfirmPage`, `Utils`, `Enums::Flags`, `Style`,
`Estimator`, and (new) `EditFilesystemDialog`.

## Components in `lib/` the drive script never touches at all

- **`lib/create_password_page.rb`** — zero checks, unchanged from the prior
  round. Not instantiated, not rendered, no property behaviour (strength
  meter, confirm-match, visibility toggle) verified anywhere in the suite.
- **`lib/drive_header.rb`** — zero checks, unchanged. The window's selection
  test only asserts the stack switches to the drive page and that
  `win.drive_view.drive == row.drive`; it never looks inside `drive_header`
  (its layout-view breakpoint switch, its menu, its "Drive Information"
  button).
- **`lib/block_row.rb`** — zero checks, unchanged. The fake drive used
  throughout has no partitions/blocks attached, so `BlockRow` (and the drive
  view's `drive_partitions_listbox` repeater over it) never renders in the
  suite. This matters more this round, not less: `BlockRow` now owns the
  `edit_filesystem` action's installation site
  (`add_action(group, 'edit_filesystem') { edit_filesystem }`), and the new
  `EditFilesystemDialog` check instantiates `EditFilesystemDialog` directly
  rather than driving it through a real `BlockRow`'s menu — so the thing the
  commit message calls "wire it into BlockRow's edit menu" is **not what
  the new check actually drives**. The wiring line itself remains unverified
  by any check.
- **`lib/format_volume_dialog.rb`** (the wizard dialog itself, as opposed to
  its 5 pages) — still no check opens the dialog end to end or exercises its
  Cancel/Create button wiring as a whole. Unchanged.
- **`lib/manager.rb` / `lib/drive.rb` / `lib/block.rb`** — exercised only
  through a hand-built fake `Drive`, not through `Manager.default`'s real
  UDisks-backed path beyond "degrades to zero drives with no daemon".
  Unchanged.

## The `spec/` suite has never once executed

`spec/` contains only `spec_helper.rb` (no example files), unchanged. That
helper `require`s `kettle/test/rspec`, not in the dev shell's runtime gem
closure. Confirmed again this pass:

```
$ nix develop --command xvfb-run -a ruby -Ilib -Ispec -e "require 'rspec'; require './spec/spec_helper'"
```
exits with a `LoadError` on `kettle/test/rspec` before any example could run.
**A suite that has never been executed is a gap, stated plainly**: the
scaffold spec harness is not a verification path for this port at all,
today, and was not before this pass either.

## Verdict

Not clean. The drive script is real and its 161/161 is accurate as a count,
but:

- it covers 20 of the ~33 UI units that exist or are mapped, unchanged in
  proportion from the prior round (one unit added, one check-group added);
- `create_password_page.rb`, `drive_header.rb` and `block_row.rb` remain at
  zero checks;
- the one new check this round (`EditFilesystemDialog`) does not actually
  drive the integration point the matching commit message claims it wires
  ("wire it into BlockRow's edit menu") — it drives the dialog class
  directly;
- a GLib critical assertion fires mid-run under a check that still reports
  green;
- the scaffold `spec/` suite has never run, unchanged.
