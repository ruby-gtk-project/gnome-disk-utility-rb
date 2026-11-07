# gnome-disk-utility-rb — accountability ensurance (refresh)

Grepped `lib/`, `exe/`, `.reports/` for `TODO`, `FIXME`, `not implemented`,
`for now`, `in a future`, plus scope-reduction language. There is no
`PORTING.md` in this repository.

## No TODO/FIXME/"not implemented"/"for now"/"in a future" anywhere

None of those five literal strings appears anywhere in `lib/`, `exe/`, or
this round's reports. The port does not leave dangling placeholder markers.

## Scope reductions in code comments are disclosed honestly, not excused

`lib/drive.rb`, `lib/format_volume_dialog.rb`, `lib/block_row.rb`,
`lib/drive_view.rb` and `lib/main.rb` each carry a class/method comment
naming a specific scope reduction (SMART/settings features not set, one
upstream `#ensure_unused` call not ported, two block-row dependents not
ported, 9 of 11 `view.*` actions not wired, the two disk-image menu actions
deliberately absent) with a concrete reason (the dependency doesn't exist
yet). None of these claims a check verifies something it does not; they are
scoped, named gaps, which is the right shape for a disclosure. These are
not the finding here.

## The real finding: the port's own `.reports/` were stale relative to the code they describe

Before this pass, `component-parity.md`, `component-identification.md`,
`test-parity.md`, `translation-parity.md` and `accountability-ensurance.md`
were all committed at `2632264e` ("Parity reports"), **before**
`9e5734a0` ("Port the format-volume wizard, drive view and block row") and
`e29bdbfd` landed. `component-parity.md` stated "14 of 46 files touched,
0/46 confirmed," and `component-identification.md`/`component-inventory.md`
marked `lib/drive_view.rb`, `lib/drive_header.rb`, `lib/block_row.rb` and
all five wizard pages **"missing"** — when, by the time this audit ran, all
of those files existed in `lib/` and are driven (at least partially) by
`test/drive_gnome_disk_utility.rb`. In this direction the staleness
understated progress rather than overstating it, so it is not itself a
false-green claim — but it is exactly the kind of drift this skill exists
to catch: a report's "missing" is only as good as the commit it was written
against, and nothing in the repo flagged that these five documents had gone
stale relative to two intervening feature commits. All five have been
rewritten fresh in this pass against the current tree; future rounds should
re-run all five skills rather than trust a prior round's documents without
checking `git log` for commits since they were written.

## False-green risk actually found: narrow test coverage reported as a clean gate

The runtime gate language for this round ("153 checks passed, 0 failed,
covering 19 components") is accurate as a count, and `drive-findings.md`'s
own prose is honest about its one known-failing check and the ruby-gnome
binding gap it worked around. But nothing in the pre-existing reports
called out, before this pass, that three files that already existed in
`lib/` at the time — `lib/create_password_page.rb`, `lib/drive_header.rb`,
`lib/block_row.rb` — have **zero** checks anywhere in the suite (see
`test-parity.md`). A reader of only the drive-run summary ("153 of 153
passed") would reasonably conclude the built surface is verified; it is
not, for those three files plus `format_volume_dialog.rb`'s own top-level
wiring. That gap is now stated explicitly in `test-parity.md` and
`component-parity.md`; it was not stated anywhere before this pass.

## Translation parity: a silent gap, not an excused one

`translation-parity.md` finds 0 of 724 upstream `msgid`s survive and no
gettext/FastGettext infrastructure exists anywhere in the port. This is not
marked "for now" or "TODO" anywhere — it simply isn't mentioned in any
class comment, report, or `PORTING.md` (which doesn't exist). A silent,
un-flagged total gap is the harder failure mode to catch than an honestly
labeled one, and is called out here explicitly so it does not slip through
as implicitly "fine" for lack of anyone saying otherwise.

## Verdict

No excuse-language violation (no TODO/FIXME/"not implemented"/"for now"/
"in a future" anywhere). But two accountability gaps found and corrected by
this pass: (1) the standing `.reports/` had drifted stale against two
feature commits and were not re-validated before this round started, and
(2) three built-but-unexercised files and the whole translation layer were
not flagged as gaps anywhere before this audit. Neither is a "false green"
in the sense of a report actively lying about a passing check, but both are
exactly the shape of thing this skill exists to surface before they harden
into an assumed-done status that nobody re-checks.
