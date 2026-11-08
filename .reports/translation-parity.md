# gnome-disk-utility-rb — translation parity (refresh 2)

## Upstream's translation footprint

`git ls-tree -r --name-only origin/main | grep '^po/'` → 88 files: `ChangeLog`,
`LINGUAS`, `POTFILES.in`, `POTFILES.skip`, and 84 locale `.po` files. A
representative locale (`po/ar.po`) carries **724 `msgid` entries**.
`POTFILES.in` lists every source file with translatable strings, spanning
both GApplications' blueprint/`.ui` UI, the
`.desktop.in`/`.metainfo.xml.in`/`.gschema.xml` data files, and the C/Rust
source. Unchanged since the prior report.

## The port: still zero translation infrastructure

Re-checked fresh this pass:

- `ls po` → no such directory.
- `grep -rn "gettext\|FastGettext" lib exe Gemfile gnome-disk-utility-rb.gemspec`
  matches exactly one line — a comment in `lib/utils.rb:307` quoting the
  upstream C macro (`g_dngettext (GETTEXT_PACKAGE, "%d thing", "%d things",
  value)`) as documentation of what the ported Ruby method replaces, not a
  call to any gettext mechanism.
- No `require 'gettext'` / `require 'fast_gettext'` anywhere in `lib/`,
  `exe/`, or the gemspec's runtime dependencies.
- The new file this round, `lib/edit_filesystem_dialog.rb`, carries its own
  user-facing strings verbatim as bare English literals — e.g. the
  "Change" button label and the unmount-warning banner text — with no
  marker of any kind. It adds to the gap rather than closing any part of
  it; checked explicitly this pass since it is the one new component since
  the last report.
- No `.desktop.in`/`.metainfo.xml.in`/`.gschema.xml` equivalents exist in
  the port at all.

## Verdict

**0 of 724 upstream `msgid`s survive in any form.** Unchanged, confirmed
again this pass including against the one file added since the last
report. Every user-facing string in the port — dialog titles, button
labels, menu items, tooltips, error messages, the about dialog's credits,
and now `EditFilesystemDialog`'s label-change prompts and unmount warning —
is a hardcoded English literal with no translation mechanism wired to mark
it, extract it, or substitute a locale's string at runtime. This is a total
translation-parity gap, not a partial one.

This gap is still **not** called out anywhere in `lib/`'s class comments,
in `PORTING.md` (no such file exists in this repo), or in any commit
message (`git log --all -i --grep='gettext\|i18n\|l10n\|translat'` on the
`ruby` branch returns nothing). It remains an entirely silent gap — present
by omission, never acknowledged — which is flagged again in
`accountability-ensurance.md`: a reader of the other four reports alone,
without checking `po/`, would still have no way to learn this gap exists.
