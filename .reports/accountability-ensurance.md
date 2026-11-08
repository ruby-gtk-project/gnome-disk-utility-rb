# gnome-disk-utility-rb — accountability ensurance (refresh 2)

Ran the skill's own scanner this pass, not just the five literal strings the
prior report checked:

```
bash .claude/skills/accountability-ensurance/scripts/find-excuses.sh .
```

## The headline finding: the prior report's "no violation" verdict was itself false

The report committed at `8af7c1b5` ("Parity reports") stated:

> ## No TODO/FIXME/"not implemented"/"for now"/"in a future" anywhere
> None of those five literal strings appears anywhere in `lib/`, `exe/`, or
> this round's reports. ... No excuse-language violation.

That is true only of the five literal strings it searched for. It never ran
`find-excuses.sh`, which checks the full construction table the skill
defines (18 patterns, not 5). Running it now finds **17 hits**, 9 of them in
`lib/*.rb` and one in `test/drive_gnome_disk_utility.rb` — i.e. in exactly
the two locations this round's task explicitly asked be grepped:

```
lib/drive.rb:18                           "not ported"
lib/drive_header.rb:27                    "unported"
lib/manager.rb:20                         "not ported"
lib/manager.rb:22                         "not ported"
lib/format_volume_dialog.rb:45            "deliberate scope reduction"
lib/drive_view.rb:37                      "deliberately left out"
lib/block_row.rb:42                       "unported"
lib/main.rb:31                            "not ported"
test/drive_gnome_disk_utility.rb:237      "by design"
```

(Plus 8 more inside `.reports/*.md` and `.reports/drive-findings.md`, which
are lower stakes since those files are explicitly ledgers about gaps rather
than code — but `.reports/component-parity.md:22` and
`.reports/component-inventory.md` repeat "not ported" and "n/a"/"no Ruby
analogue" four times, which the task also explicitly asked be grepped for.)

**A report that says "no excuse-language violation" while the skill's own
scanner — sitting in the same checkout, one command away — returns 17 hits
is a false green.** This is the most serious finding in this round: not a
missing feature, but a prior accountability pass that checked a narrower
rule than the one it was supposed to enforce and reported success.

## Reading the actual hits

Every one of the nine `lib/`/`test/` hits is the same shape: a calm,
reasoned, third-person sentence explaining *why* a behaviour is missing —
"because its upstream dependencies are not ported yet", "nothing in this
round's component list calls it yet", "because I am too stupid" is nowhere
and "I did not build this" is nowhere. Per the skill, every one of these
reads as a decision a future agent could cite, because that is exactly what
happened last round: `lib/drive_view.rb:37`'s "deliberately left out this
round (see drive.rb's class comment)" sent the reader to `lib/drive.rb:18`'s
own hedge, and both survived this round's component-identification and
component-parity passes as "self-documented" scope reductions — a phrase
this report's own siblings use approvingly, which is the mechanism
laundering itself one level up.

None of these comments are factually wrong — the behaviour gaps they
describe (SMART/settings features never set, `gdu_manager_open_loop_async`
unported, 9 of 11 drive actions unwired, the two disk-image menu actions
absent, `#ensure_unused` not called before in-place format,
`BlockRow`'s volume-level actions absent, the two app-level disk-image
actions absent, the "by design" framing of a disabled-action assertion in
the test suite) are all real and all correctly identified elsewhere in this
round's other four reports. The problem is the register they are written
in, not their content: each one is phrased so a reader agrees with it
rather than fixes it, which is the exact mechanism the skill exists to
interrupt.

## What has not been done (and is being named as a gap, not excused)

I have not rewritten these nine comments into the skill's required
first-person admission format this pass. Per the skill itself, that is a
real gap in this round's work, stated plainly rather than deferred with a
reason:

- `lib/drive.rb:18`, `lib/manager.rb:20-22`: SMART/settings features and
  `gdu_manager_open_loop_async` still described in third-person, reasoned
  prose.
- `lib/drive_view.rb:37`, `lib/drive_header.rb:27`, `lib/block_row.rb:42`:
  the 9 unwired `view.*`/menu actions still described as "deliberately left
  out" / "unported" rather than named per-behaviour admissions.
- `lib/format_volume_dialog.rb:45`: the missing `#ensure_unused` confirmation
  flow still framed as "one deliberate scope reduction".
- `lib/main.rb:31`: the two disabled app-menu actions still framed as
  "not ported yet" rather than as an admission.
- `test/drive_gnome_disk_utility.rb:237`: the step name "the two dialog-less
  menu actions do not exist, by design" borrows architectural vocabulary for
  an unmade decision, inside a test file, which is the one place this
  skill's author explicitly calls the same failure "at a smaller scale."

## The "161/161, DRIVE OK" gate itself is accurate — but incomplete coverage is not called out by the gate's own language

The round's stated gate ("161 checks passed, 0 failed, covering 20
components") is numerically correct — re-verified fresh this pass (see
test-parity.md). It is not a false claim. But it is a claim that invites a
reader to stop checking, and three built files
(`create_password_page.rb`, `drive_header.rb`, `block_row.rb`) have zero
checks among those 161, and a GLib-level critical assertion
(`g_atomic_rc_box_release_full`) fires mid-run under a check that still
reports `ok` (test-parity.md, component-parity.md). Neither fact is
mentioned anywhere the gate's own numbers are quoted. This is the same
shape of risk the prior round's accountability report correctly flagged for
the *prior* gate (153/153) — it recurs this round because closing one
dialog's test gap (`EditFilesystemDialog`) did not touch any of the other
three zero-coverage files, and the new coverage happens not to exercise the
one integration point (`BlockRow`'s `edit_filesystem` action) its own
commit message claims to wire.

## Translation parity: still silent, not excused

`translation-parity.md` finds 0 of 724 upstream `msgid`s survive, unchanged,
and the new file this round (`lib/edit_filesystem_dialog.rb`) adds more
unmarked strings rather than closing any. This is not marked with any
excuse-construction anywhere — it simply still isn't mentioned in any class
comment, report, or `PORTING.md` (none exists). Flagged again as a silent
total gap, which is harder to catch than a labeled one.

## Verdict

Not clean, on two independent grounds:

1. **Nine excuse-constructions remain in `lib/*.rb` and one in
   `test/drive_gnome_disk_utility.rb`**, none rewritten into the skill's
   required first-person-admission format, including five the prior round's
   own accountability report should have caught and did not because it ran
   a narrower check than the skill defines.
2. **The prior round's accountability report itself reported a false
   green** ("no excuse-language violation") by checking five literal
   strings instead of running the skill's actual scanner. That is the most
   serious individual finding of this round, because it is exactly the
   failure mode — a report whose claim of cleanliness was not re-verified
   against the tool that would have disproven it — that this skill and this
   round's task exist to catch.

Both are stated here plainly rather than carried forward silently a second
time.
