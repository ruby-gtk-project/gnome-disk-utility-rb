# gnome-disk-utility-rb — drive run findings

Run with `nix develop --command xvfb-run -a ruby test/drive_gnome_disk_utility.rb`.
152 checks, 151 passed, 1 left failing on purpose (see below). This machine
has no `udisksd`, so every check runs against a real `Manager`/`UDisks::Client`
that correctly degrades to zero drives rather than against a live disk.

## Fixed in the port

1. **`Block` had no `#color` reader.** `Drive#color_block` sets it with
   `block.instance_variable_set(:@color, color)`, and
   `SpaceAllocationBar#allocate_child` reads it back with `block.color` to
   add the matching CSS class — but nothing defined that reader. Every drive
   with at least one partition raised `NoMethodError` the first time its
   space allocation bar tried to lay itself out. Fixed with
   `attr_accessor :color` in `lib/block.rb`.

2. **`TakeOwnershipDialog` opened with the wrong default response.**
   `#initialize` sets `self.default_response = 'cancel'` before the
   recursive switch even exists (just to give `close_response` something to
   fall back to), and `#build` never re-synced it for the switch's actual
   starting state (off). The dialog's own class comment says "flipping the
   switch off makes the confirm response suggested and the default again" —
   but it opened with "Take Ownership" shown as suggested while Enter would
   still have activated "Cancel". Fixed by calling `on_recursive_switch` once
   at the end of `#build` in `lib/take_ownership_dialog.rb`.

## Left failing, with the real cause

**`CreateFilesystemPage`: a type row the daemon cannot format goes sensitive
again once the page is realized.** `disable_unavailable_types` sets
`ntfs_check_button.sensitive = false` (etc.) at build time, confirmed still
false immediately after `#build` with no window at all. Once the page is
presented in a real window and the loop ticks once, GTK re-syncs every
`GtkCheckButton` bound through `action-name`/`action-target` to its shared
`install_property_action`'s *enabled* state — which is always `true`, because
it is one action covering all four radio choices, not a per-row flag — and
that resync clobbers the manual `sensitive = false`. The row's tooltip
("The utility ... is missing.") is unaffected; only the greyed-out,
unclickable presentation is lost once the page is actually shown, which
defeats the whole point of `disable_unavailable_types`. A real fix needs each
row to carry its own enabled state (e.g. a `Gio::SimpleAction` per type with
its own `enabled=`) rather than four widgets sharing one property action —
out of scope for this pass; left failing in
`test/drive_gnome_disk_utility.rb` rather than loosened or deleted.

## ruby-gnome / libadwaita binding gap (not a port bug)

`Gtk::Widget#activate_action("win.<name>", nil)` does not dispatch to an
action group inserted with `insert_action_group("win", group)` on the window
itself when the receiver is an `Adwaita::ApplicationWindow` subclass — it
returns the receiver (ruby-gnome's usual stand-in for a void return) without
the action ever firing. Reproduced in complete isolation from this port:

```ruby
class MyAdwWin < Adwaita::ApplicationWindow
  type_register
end
# ... w = MyAdwWin.new; w.application = app; w.insert_action_group("win", grp) ...
w.activate_action("win.go-back", nil)   # => returns w itself; the action never fires
```

The identical sequence against a plain `Gtk::Window`, or a `type_register`'d
`Gtk::Window` subclass, fires correctly and returns `true`. Activating the
very same `Gio::SimpleActionGroup` directly
(`grp.activate_action("go-back", nil)`) also fires correctly. So the gap is
specifically in how `Gtk::Widget#activate_action` resolves an action group
through an `AdwApplicationWindow`'s action muxer in these bindings
(`gtk4` 4.4.0 / `adwaita` 4.4.0 / `gobject-introspection` 4.4.0, on
`gtk4-4.22.4`).

This does **not** affect the real app: a real Escape keypress, sent through
the X server with `xdotool` exactly as upstream's own `ACTION_ACCELS` table
binds it (`'win.go-back' => ['Escape']`), reaches `App#window_actions`'s
`go-back` action and calls `Window#unselect_drive` correctly — proven in
`test/drive_gnome_disk_utility.rb`'s "a real Escape keypress reaches
win.go-back" step. The gap is scoped to this one Ruby-level call, which is
why the drive script drives that action with a real key event (needing
`pkgs.xdotool`, added to `flake.nix`) rather than `activate_action`.

## Scaffold spec suite (unrelated to the port)

`spec/` has only `spec_helper.rb` (no example files), and that helper
requires `kettle/test/rspec`, which is not in the dev shell's runtime gem
closure (deliberately — the shell carries the app's runtime closure, not the
kettle-dev development bundle). Running the banner's spec command reports
`0 examples, ... 2 errors occurred outside of examples`. This predates this
run and is not something this pass changed.
