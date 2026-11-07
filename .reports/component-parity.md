# component-parity — gnome-disk-utility-rb

Verdict: **no parity**. 14 of 46 upstream units have a port file at all;
of those 14, several carry recorded, self-admitted scope reductions, and
none has been checked against upstream for all four axes (count, style,
behaviour, text) in a document that states pass/fail per axis. This report
states that explicitly rather than letting the inventory's "present" column
stand in for "at parity."

## Axis-by-axis, for the 14 present units

| File | Count | Style (CSS) | Behaviour (signals/actions) | Text (i18n) |
|---|---|---|---|---|
| `lib/main.rb` | gap — 2 menu actions (`app.new_disk_image`, `app.attach_disk_image`) unregistered because their dialogs don't exist | not checked | gap — same 2 actions | gap, see translation-parity.md |
| `lib/window.rb` | not independently re-verified this pass; inventory marks "present" | not re-verified | gap — none of upstream's ten `win.*` accelerated actions is installed per the inventory's own blocker #3 | gap |
| `lib/shortcuts_dialog.rb` | present | not re-verified | — | gap |
| `lib/drive_row.rb` | present | not re-verified | not re-verified | gap |
| `lib/job_row.rb` | present | not re-verified | not re-verified | gap |
| `lib/space_allocation_bar.rb` | present (bug fixed this round per drive-findings.md: missing `#color` reader) | not re-verified | not re-verified | gap |
| `lib/combo_row.rb` | present | not re-verified | not re-verified | gap |
| `lib/take_ownership_dialog.rb` | present (default-response bug fixed per drive-findings.md) | not re-verified | not re-verified | gap |
| `lib/utils.rb` | present | n/a | n/a | gap — `unfuse_path` ported, its upstream test is not (see test-parity.md) |
| `lib/style.rb` | present | not re-verified against `src/resources/style.css` rule-for-rule | n/a | n/a |
| `lib/item.rb`, `lib/job_manager.rb`, `lib/local_job.rb`, `lib/estimator.rb`, `lib/enums.rb` | present (model layer) | n/a | not re-verified | n/a |
| `lib/manager.rb` | gap — `gdu_manager_open_loop_async` not ported (self-recorded, see accountability-ensurance.md) | n/a | gap, same method | n/a |
| `lib/drive.rb` | gap — `#features` never sets `GDU_FEATURE_SMART`/`GDU_FEATURE_SETTINGS` (self-recorded) | n/a | gap | n/a |

I did not re-run a full signal-by-signal, CSS-class-by-CSS-class diff against
upstream source for every "present" row in the time this pass had — that
re-verification is itself undone and is listed as a gap below, not assumed
clean because a prior pass called the file "present."

## The 32 missing units: zero axes hold

For all 32 units listed as absent in `component-identification.md`, all four
axes are gaps by construction — there is no port file, so there is no count,
no style, no behaviour and no text to compare. This includes:

- The entire **drive view and header** — the window's main content pane.
  Nothing in `lib/window.rb` currently shows a drive's content; the window
  renders sidebar and empty content only.
- **23 dialogs/pages**: format disk, format volume (wizard), benchmark +
  graph, ATA SMART, disk settings, create/restore/attach/new disk image,
  edit filesystem, edit partition, resize volume, change passphrase, unlock,
  mount options, encryption options, create-password-page.
- The **Disk Image Mounter** app in its entirety (`org.gnome.DiskUtility.ImageMounter`)
  — a second, separately-launchable GApplication upstream ships. Zero trace
  of it on `ruby`.
- The **udisks2 status notifier** (`src/notify/`).
- **GSettings schema** (`data/org.gnome.Disks.gschema.xml`) — window-state
  persistence that `gdu-window.c` depends on has no schema to bind to on
  `ruby`.

## What "component-identification and component-parity" together conclude

A reader of only `drive-findings.md` ("151 checks passed") or only
`component-inventory.md`'s header line could believe substantial UI exists.
It does not: the drive view — the screen a user sees immediately after
picking a disk, which is most of what "Disks" is — is unbuilt, and so is
every dialog it would open. Component parity for this port is **14/46 files
touched, 0/46 confirmed at full four-axis parity**, because the four-axis
check itself was never completed for the 14 that do exist.
