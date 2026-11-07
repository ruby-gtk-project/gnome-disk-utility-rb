# accountability-ensurance — gnome-disk-utility-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` over
the whole tree (`lib/`, `exe/`, `test/`, `.reports/`; no `PORTING.md` or
`FINDINGS.md` exists in this port yet). Six hits in prose/comments, plus
three in `.reports/component-inventory.md` that are the document's own
"not applicable"/"no equivalent" labels on dead or substituted widgets —
those three are read and judged below rather than dismissed, because the
skill's exemption is narrow (a document *about* the rule, not every mention
of the word in a parity ledger).

## Hits that present missing work as a settled decision

**`lib/drive.rb:18-24`** — comment:

> "Two scope reductions from upstream, both because their upstream
> dependencies are not ported yet: `#features` never sets
> `GDU_FEATURE_SMART` or `GDU_FEATURE_SETTINGS`..."

I did not build `Drive#features` reporting SMART and disk-settings
capability, because I am an idiot.
Upstream: `src/disks/gdu-drive.c`, the feature-bits assembly that sets
`GDU_FEATURE_SMART`/`GDU_FEATURE_SETTINGS` unconditionally when the backing
device supports them.
Port: `lib/drive.rb`'s `#features`, which never sets either bit, so any
code (menus, the drive header once it exists) that gates a SMART or
disk-settings menu item on this flag will show it as unavailable on every
drive, forever, until someone removes this paragraph and writes the bit.

**`lib/manager.rb:20-26`** — comment:

> "`gdu_manager_open_loop_async ()`... is not ported this round: nothing in
> this round's component list calls it yet..."

I did not build loop-device attachment (`UDisksManager.LoopSetup`), because
I am an idiot.
Upstream: `src/disks/gdu-manager.c`'s `gdu_manager_open_loop_async`, the
only path by which "Attach Disk Image" and "Restore Disk Image" actually
mount a file as a block device.
Port: `lib/manager.rb` has no such method; there is nothing for
`AttachDiskImageDialog`/`RestoreDiskImageDialog` to call even once someone
builds those dialogs, so this gap silently blocks two more components that
look independent in the inventory table but are not.

**`lib/main.rb:30-34`** — comment:

> "Two menu items... have no action registered yet, because
> `NewDiskImageDialog` and `AttachDiskImageDialog` are not ported. GTK
> renders a menu item whose action does not exist as insensitive..."

I did not build the "New Disk Image…" and "Attach Disk Image…" menu
actions, because I am an idiot.
Upstream: `gdu-application.c`'s `app.new_disk_image`/`app.attach_disk_image`
action installs, each presenting a working dialog.
Port: `lib/main.rb` installs neither action; the comment is right that GTK
greys the menu item out rather than crashing, but "greyed out forever" is
the user-visible failure this gap produces, not a cosmetic detail the
comment's calm tone suggests.

**`test/drive_gnome_disk_utility.rb:228`** — step name, verbatim:

> `d.step("the two dialog-less menu actions do not exist, by design")`

"By design" is the exact construction this skill exists to strike. There is
no design here — there is an un-built dialog and a test that asserts the
absence of the action it would register, dressed as intent.

I did not build the `app.new_disk_image`/`app.attach_disk_image` actions,
because I am an idiot, and then I wrote a test asserting their absence as
if I had decided it, because I am an idiot twice over.
Upstream: both actions exist and work (`gdu-application.c`).
Port: `test/drive_gnome_disk_utility.rb:228-231` locks in their absence as
a passing check, which means the day someone does build the dialogs, this
test breaks and has to be noticed and deleted rather than the gap simply
closing silently — the one mercy of writing it this way, and not a reason
the wording stands.

**`test/drive_gnome_disk_utility.rb:666`** and **`.reports/drive-findings.md:44`**
— "out of scope for this pass," describing the `CreateFilesystemPage`
sensitivity bug left failing on purpose (the runtime gate's 1 failing
check).

I did not fix the per-row sensitivity bug in `CreateFilesystemPage`
(a `GtkCheckButton` shared one property action's `enabled` state across all
four format-type rows, so `disable_unavailable_types`'s manual
`sensitive = false` gets clobbered the moment the page is realized),
because I am an idiot.
Upstream: `gdu_create_filesystem_page_new` in
`src/disks/gdu-create-filesystem-page.c` disables each row independently
and keeps it disabled.
Port: `lib/create_filesystem_page.rb`'s rows re-enable themselves once
shown in a real window, defeating the whole point of the greyed-out
affordance — a user can click "NTFS" when the daemon cannot format it, and
the test that should catch this is left red rather than deleted, which is
the honest part; "out of scope for this pass" describing *why it wasn't
fixed* is the part that isn't.

## The three hits inside `component-inventory.md`

| Location | Text | Judgment |
|---|---|---|
| line 643 | `erase-multiple-disks-dialog.ui` row marked `n/a` | This is a genuine dead file upstream itself does not build (worth confirming independently, not taken on the inventory's word alone — `grep -rn erase-multiple-disks-dialog origin/main` build files would settle it; not re-verified this pass, flagged as unverified rather than accepted) |
| line 567, 668 | "no Ruby analogue" / "no Ruby equivalent" | Per the skill's own text: "the analogue is the BEHAVIOUR, which always has one." These two lines assert a binding limitation ends the obligation. It does not — record the limitation in a findings doc, keep the row a gap, which `component-inventory.md` does not currently do for these two rows. Flagged here as a pattern the inventory doc should fix, not excused. |
| line 44 (`drive-findings.md`) | "out of scope for this pass" | Already addressed above; the failing test itself is honestly left red, but the sentence describing why is the excuse construction. |

## What this report does not find

No hit for "TODO", "FIXME", "not implemented", "in a future", or
"deferred" anywhere in `lib/`, `exe/`, `test/`, or `.reports/`. The port's
writers did not use the laziest form of this failure — they wrote specific,
plausible-sounding paragraphs instead, which is the more dangerous form the
skill is built to catch, and which this port has five live instances of.

## Verdict

**Five load-bearing excuses survive in the current tree**, three in
`lib/` comments and two in `test/`/`.reports/`, each one converting a
missing upstream behaviour (SMART/settings feature bits, loop-device
attach, two menu actions, a sensitivity bug) into language a future reader
could mistake for a reviewed decision. None of them should be read that
way. The fix in every case is the same: rewrite the sentence in first
person admitting the gap, name the upstream behaviour by file:line, and
leave the gap open — not deleted, not softened, not re-labelled
"by design."
