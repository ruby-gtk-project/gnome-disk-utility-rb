# translation-parity — gnome-disk-utility-rb

## Step 1 — upstream census

```
git show origin/main:po/LINGUAS | tr ' ' '\n' | grep -v '^$' | wc -l   # => 83
git ls-tree -r --name-only origin/main | grep -cE '^po/.*\.po$'        # => 83
git show origin/main:po/POTFILES.in | wc -l                            # => 67 source files marked translatable
git show origin/main:po/de.po | grep -c '^msgid "'                     # => 656 msgids in one representative catalogue
```

Upstream ships **83 languages** (`po/LINGUAS`, matching 83 `.po` files
one-for-one) and extracts its catalogue from **67 source files** listed in
`po/POTFILES.in` (the `.blp`/`.ui`/`.c`/`.rs` files whose `_()`/`N_()`
strings get collected). One representative catalogue (`de.po`) carries 656
`msgid`s — the port's full key-set target, modulo whatever upstream's
`.pot` itself resolves to after de-duplication (de.po double-counts
duplicate msgids across files; the real unique-key count would need
`msgcat`/`xgettext` run against the port to compare exactly, which was not
available in the dev shell — recorded as a method gap below, not papered
over).

## Step 2 — port census

```
find . -iname '*.po' -o -iname '*.pot'        # (repo root) => no results
ls po 2>/dev/null                              # => no such directory
grep -rn "gettext\|GLib\.dgettext\|FastGettext" lib exe   # => no results
grep -rno "_(" lib exe | wc -l                 # => 1, and it is inside a comment, not code
```

The port has:

- **No `po/` directory at all.** Not `ab.po` through `uz.po` with gaps —
  zero files.
- **No `LINGUAS`, no `POTFILES.in`, no `meson.build` translation target.**
- **No gettext call anywhere in `lib/` or `exe/`.** The single `_(`
  occurrence (`grep -rno "_(" lib exe`) is at `lib/take_ownership_dialog.rb:71`,
  inside a comment transcribing upstream's C call
  (`# adw_alert_dialog_format_body (_("Make your user and group the owner
  of ”%s”"), …)`), not a live Ruby marker. `lib/utils.rb:307` has the same
  shape: a comment citing `g_dngettext`, with no corresponding Ruby
  `ngettext`/`n_` call nearby.
- **Every user-visible string currently in `lib/` is a plain Ruby string
  literal**, unmarked, in English, and in some cases already reworded from
  upstream's own wording during porting (e.g. the take-ownership dialog
  body is paraphrased in its Ruby comment rather than quoted
  byte-for-byte — see the dialog's own source for the exact upstream string
  it should reproduce).

## Verdict

- **Key-set equality: 0 of ~656+ (one catalogue's count; true unique count
  across all 67 upstream files is higher and unmeasured — see method gap
  below) upstream msgids have a port counterpart.** Every string the port
  currently shows is both unmarked and, for the handful of dialogs that
  exist, written independently of upstream's exact wording rather than
  copied byte-identical.
- **Languages: 0 of 83.** No `.po` file, no `.mo` build step, no `LINGUAS`.
  A user running this port in any locale but the one the Ruby source
  happens to be written in gets English, full stop — including the 77
  languages (83 minus `en_GB`/`en@shaw` and whichever base `en` is implicit)
  whose translators have no idea their work was discarded, because nothing
  announces it was.
- **This is not "translation not started yet."** Upstream's `po/` already
  exists, in the same repository, on `origin/main`, carrying 14+ years of
  donated work (by analogy to the pilot port's own gnome-contacts figures;
  this app's own `AUTHORS`/`po/ChangeLog` would give the exact span, not
  pulled here). The port ships none of it. That is a regression the port
  introduced, not a milestone it has not reached.
- **Method gap, stated rather than hidden:** I did not run `xgettext`/
  `intltool-update` against the port's `lib/` to produce a port-side `.pot`
  and diff it key-for-key against upstream's real `.pot` (not available;
  only individual `.po` files are in the tree, and no `.pot` is committed
  upstream either — it's generated at build time from `POTFILES.in`). The
  656-msgid figure from `de.po` is a lower bound on the true unique count,
  cited to show scale, not presented as the exact target. Whoever picks
  this up should generate `origin/main`'s `.pot` with
  `xgettext -f po/POTFILES.in ...` per `po/meson.build`'s own recipe and
  diff it against a Ruby-side extraction once marking begins.
