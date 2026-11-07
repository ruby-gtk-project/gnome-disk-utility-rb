# gnome-disk-utility-rb — translation parity (refresh)

## Upstream's translation footprint

`git ls-tree -r --name-only origin/main | grep '^po/'` → 88 files: `ChangeLog`,
`LINGUAS`, `POTFILES.in`, `POTFILES.skip`, and 84 locale `.po` files. A
representative locale (`po/ar.po`, read via `git show origin/main:po/ar.po`)
carries **724 `msgid` entries**. `POTFILES.in` lists every source file with
translatable strings, spanning both GApplications' blueprint/`.ui` UI, the
`.desktop.in`/`.metainfo.xml.in`/`.gschema.xml` data files, and the C/Rust
source (dialog titles, button labels, error strings, `_()`/`ngettext()`
calls throughout `src/disks/*.c` and `src/disks/*.rs`).

## The port: zero translation infrastructure

- No `po/` directory, `.pot` template, or any `.po` file anywhere in this
  repository.
- `grep -rn "gettext\|FastGettext\| _(" lib exe` matches exactly one line —
  a comment in `lib/utils.rb` quoting the upstream C macro
  (`g_dngettext (GETTEXT_PACKAGE, "%d thing", "%d things", value)`) as
  documentation of what the ported Ruby method replaces, not a call to any
  gettext mechanism.
- No `require 'gettext'` or `require 'fast_gettext'` anywhere in `lib/`,
  `exe/`, or the gemspec's runtime dependencies.
- No `.desktop.in`/`.metainfo.xml.in`/`.gschema.xml` equivalents exist in
  the port at all to carry their own translatable strings (names,
  summaries, descriptions).

## Verdict

**0 of 724 upstream `msgid`s survive in any form.** Every user-facing string
in the port — dialog titles, button labels, menu items, tooltips, error
messages, the about dialog's credits — is a hardcoded English literal with
no translation mechanism wired to mark it, extract it, or substitute a
locale's string at runtime. This is a total translation-parity gap, not a
partial one: there is no scaffolding in place for a future translator to
even attach `.po` files to, let alone 84 locales' worth of ported strings.

This gap is **not** called out anywhere in `PORTING.md` (no such file exists
in this repo) or in any class comment surveyed in `lib/`. No commit message
in `git log` mentions gettext, i18n, l10n, or translation. It is an entirely
silent gap — present by omission, never acknowledged, let alone excused with
"for now" or "in a future pass," which is itself worth flagging in
`accountability-ensurance.md`: a reader of the other four reports alone,
without checking `po/`, would have no way to learn this gap exists.
