# test-parity — gnome-disk-utility-rb

## Step 1 — census of `origin/main`

Searched every `.c` and `.rs` file in `origin/main` for `g_test_add_func`,
`#[test]`, and `#[cfg(test)] mod tests`:

```
git ls-tree -r --name-only origin/main | grep -E '\.(c|rs)$' \
  | xargs -I{} git show origin/main:{} | grep -lE 'g_test_add|#\[test\]|#\[cfg\(test\)\]'
```

One hit: `src/libgdu/gduutils.rs`, lines 1056–1069, a `#[cfg(test)] mod
unfuse_path_tests` with exactly two `#[test]` functions:

| # | Upstream test | What it pins |
|---|---|---|
| 1 | `unfuse_path_home` | `unfuse_path(file!())` rewrites the current source file's path with `$HOME` abbreviated to `~`, for any path actually under `$HOME` |
| 2 | `unfuse_path_without_home` | A path outside `$HOME` (`/__gdu_path_outside_home__`) passes through `unfuse_path` unchanged |

**Upstream test count: N = 2.** No other `#[test]`/`g_test_add_func` exists
anywhere in `origin/main`'s C or Rust sources, and there is no `test/` or
`tests/` directory in the tree (`git ls-tree -r --name-only origin/main |
grep -i test` returns nothing beyond the CI scripts under `.gitlab-ci/`,
which are not test cases). This is a small upstream suite; small is not the
same as zero, and the census must still be exact.

## Step 2 — port side

`lib/utils.rb:107` defines `Utils.unfuse_path`, ported from the same
upstream function. I grepped `test/drive_gnome_disk_utility.rb` for
`unfuse`:

```
grep -n "unfuse" test/drive_gnome_disk_utility.rb
```

Zero matches. **Neither upstream test has a named port counterpart.** The
port count is 0 against upstream's 2.

## Step 3 — does the ported suite run at all?

`test/drive_gnome_disk_utility.rb` is a GTK-driver script run under a
virtual display: `nix develop --command xvfb-run -a ruby
test/drive_gnome_disk_utility.rb`. Per the committed `.reports/drive-findings.md`
(this pass's runtime gate: `drive_ok=false`, 151/152 checks passed, 1 left
failing by the port's own admission), the script does execute and most of
its checks pass. It covers 21 of the port's classes
(`Block`, `ComboRow`, `CreateConfirmPage`, `CreateFilesystemPage`,
`CreateOtherPage`, `CreatePartitionPage`, `Drive`, `DriveRow`, `Estimator`,
`Item`, `JobManager`, `JobRow`, `LocalJob`, `App`, `Manager`,
`ShortcutsDialog`, `SpaceAllocationBar`, `Style`, `TakeOwnershipDialog`,
`Utils`, `Window` — confirmed by grepping the test file's class references
against `lib/*.rb`'s `class`/`module` declarations), which is an honest,
executed suite over what exists.

A second suite does **not** run: `spec/` contains only `spec_helper.rb`,
which `require`s `kettle/test/rspec`, a gem not in the dev shell's runtime
closure. Running the scaffold's rspec command reports "0 examples ... 2
errors occurred outside of examples" (recorded in `drive-findings.md`,
confirmed still true — this is the kettle-dev packaging scaffold, not a
port-authored suite, and it has never executed successfully). **A suite
that has never been executed is a gap, stated plainly: the rspec scaffold
is dead weight that has not run once since the port's `ruby` branch
started.**

## Verdict

- **Census: N = 2 upstream tests, 0 ported.** The `unfuse_path` behaviour —
  home-directory abbreviation in displayed paths — is implemented in
  `lib/utils.rb` but has no test pinning either of upstream's two cases
  (the happy path under `$HOME`, and the no-op path outside it) in the
  Ruby port. This is a full-sized gap on a 2-test suite: 100% missing.
- **Behaviour still owed:** a path the app shows to the user that happens
  to live under their home directory is abbreviated with `~`, and this
  rewrite is skipped for paths outside the home directory. Neither
  property is pinned by a Ruby test today.
- **The executed suite (`test/drive_gnome_disk_utility.rb`) is real** —
  it runs, and the numbers in `drive-findings.md` describe an actual run,
  not an aspiration — but it was never built as a census against upstream's
  `#[test]` functions; its 152 checks are coverage of the 21 ported classes
  on their own terms, not a 1:1 mapping to the 2 tests upstream wrote. By
  this skill's definition that is still test parity (a test written
  differently in Ruby still counts, as long as it's named and pins the same
  property) — but no such named test exists for `unfuse_path` in either
  suite, so the two upstream tests have zero counterpart under any
  definition.
- **The rspec scaffold (`spec/`) has never been executed successfully and
  contributes zero tests.** It is not a second suite with partial coverage;
  it is 0 examples, every time it has been run, and nothing in this port's
  history shows it passing once.
