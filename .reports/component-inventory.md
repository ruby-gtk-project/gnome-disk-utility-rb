# Upstream component inventory — gnome-disk-utility-rb

Surveyed against `origin/main` (`git ls-tree -r --name-only origin/main`) for
the full-parity port on `ruby`. No app code was written for this survey.

One row per port unit. "Kind" follows the `component-identification` skill's
classification (widget / dialog / page / row / model / service / resource).
"Present" is whether `lib/` on `ruby` already has the file.

## Application shell

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/disks/main.c`, `src/disks/gdu-application.c/.h` | `lib/main.rb` (+ `lib/gnome_disk_utility/application.rb`) | application | yes |
| `src/disks/gdu-manager.c/.h` | `lib/manager.rb` | service (UDisks client/model owner) | **no** |
| `src/disks/gdu-log.c/.h` | `lib/log.rb` | service (logging) | **no** |

## Main window

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/disks/gdu-window.c/.h`, `src/resources/ui/gdu-window.blp` | `lib/window.rb` | window | yes |
| `src/disks/gdu-drive-row.c/.h`, `src/resources/ui/gdu-drive-row.blp` | `lib/drive_row.rb` | row (sidebar) | yes |
| `src/disks/gdu-drive.c/.h` | `lib/drive.rb` | model | **no** |
| `src/disks/gdu-drive-header.c/.h`, `src/resources/ui/gdu-drive-header.blp` | `lib/drive_header.rb` | widget (drive-view header) | **no** |
| `src/disks/gdu-drive-view.c/.h`, `src/resources/ui/gdu-drive-view.blp` | `lib/drive_view.rb` | page (right pane) | **no** |
| `src/disks/gdu-block.c/.h` | `lib/block.rb` | model | **no** |
| `src/disks/gdu-block-row.c/.h`, `src/resources/ui/gdu-block-row.blp` | `lib/block_row.rb` | row (partition/volume row) | **no** |
| `src/disks/gdu-item.c/.h` | `lib/item.rb` | model (abstract base) | yes |
| `src/disks/gdu-space-allocation-bar.c/.h` | `lib/space_allocation_bar.rb` | widget | yes |
| `src/disks/gdu_combo_row.rs` | `lib/combo_row.rb` | widget | yes |
| `src/resources/ui/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | dialog | yes |

## Jobs

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/disks/gdu-job-manager.c/.h` | `lib/job_manager.rb` | service | yes |
| `src/disks/gdu-job-row.c/.h`, `src/resources/ui/gdu-job-row.blp` | `lib/job_row.rb` | row | yes |
| `src/disks/gdulocaljob.c/.h`, `src/disks/localjob.rs` | `lib/local_job.rb` | model | yes |
| `src/disks/gduestimator.c/.h`, `src/disks/estimator.rs` | `lib/estimator.rb` | model/helper | yes |

## Dialogs (one upstream `.c`/`.h` or `.rs` + its `.blp`/`.ui` per row)

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/disks/gdu-ata-smart-dialog.c/.h`, `src/resources/ui/gdu-ata-smart-dialog.ui` | `lib/ata_smart_dialog.rb` | dialog | **no** |
| `src/disks/gdu-attach-disk-image-dialog.c/.h`, `.../gdu-attach-disk-image-dialog.blp` | `lib/attach_disk_image_dialog.rb` | dialog | **no** |
| `src/disks/gdu-benchmark-dialog.c/.h`, `.../gdu-benchmark-dialog.blp` | `lib/benchmark_dialog.rb` | dialog | **no** |
| `src/disks/gdu-change-passphrase-dialog.c/.h`, `.../gdu-change-passphrase-dialog.blp` | `lib/change_passphrase_dialog.rb` | dialog | **no** |
| `src/disks/gdu-create-disk-image-dialog.c/.h`, `.../gdu-create-disk-image-dialog.blp` | `lib/create_disk_image_dialog.rb` | dialog (wizard host) | **no** |
| `src/disks/gdu-disk-settings-dialog.c/.h`, `.../gdu-disk-settings-dialog.blp` | `lib/disk_settings_dialog.rb` | dialog | **no** |
| `src/disks/gdu-edit-filesystem-dialog.c/.h`, `.../gdu-edit-filesystem-dialog.blp` | `lib/edit_filesystem_dialog.rb` | dialog | **no** |
| `src/disks/gdu-edit-partition-dialog.c/.h`, `.../gdu-edit-partition-dialog.blp` | `lib/edit_partition_dialog.rb` | dialog | **no** |
| `src/disks/gdu-encryption-options-dialog.c/.h`, `.../gdu-encryption-options-dialog.blp` | `lib/encryption_options_dialog.rb` | dialog | **no** |
| `src/disks/gdu-format-disk-dialog.c/.h`, `.../gdu-format-disk-dialog.blp` | `lib/format_disk_dialog.rb` | dialog | **no** |
| `src/disks/gdu-format-volume-dialog.c/.h`, `.../gdu-format-volume-dialog.blp` | `lib/format_volume_dialog.rb` | dialog | **no** |
| `src/disks/gdu-mount-options-dialog.c/.h`, `.../gdu-mount-options-dialog.blp` | `lib/mount_options_dialog.rb` | dialog | **no** |
| `src/disks/gdu-new-disk-image-dialog.c/.h`, `.../gdu-new-disk-image-dialog.blp` | `lib/new_disk_image_dialog.rb` | dialog | **no** |
| `src/disks/gdu-resize-volume-dialog.c/.h`, `.../gdu-resize-volume-dialog.blp` | `lib/resize_volume_dialog.rb` | dialog | **no** |
| `src/disks/restore_disk_image_dialog.rs`, `.../gdu-restore-disk-image-dialog.blp` | `lib/restore_disk_image_dialog.rb` | dialog | **no** |
| `src/disks/gdu-unlock-dialog.c/.h`, `.../gdu-unlock-dialog.blp` | `lib/unlock_dialog.rb` | dialog | **no** |
| `src/resources/ui/erase-multiple-disks-dialog.ui` (built in `gdu-window.c`; no standalone `.c`) | `lib/erase_multiple_disks_dialog.rb` | dialog | **no** |
| (built in `gdu-block-row.c`; no standalone `.c`) `.../gdu-take-ownership-dialog.blp` | `lib/take_ownership_dialog.rb` | dialog | yes |

## Create-volume wizard pages

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/disks/gdu-create-confirm-page.c/.h`, `.../gdu-create-confirm-page.blp` | `lib/create_confirm_page.rb` | page | yes |
| `src/disks/gdu-create-filesystem-page.c/.h`, `.../gdu-create-filesystem-page.blp` | `lib/create_filesystem_page.rb` | page | yes |
| `src/disks/gdu-create-other-page.c/.h`, `.../gdu-create-other-page.blp` | `lib/create_other_page.rb` | page | yes |
| `src/disks/gdu-create-partition-page.c/.h`, `.../gdu-create-partition-page.blp` | `lib/create_partition_page.rb` | page | yes |
| `src/disks/gdu-create-password-page.c/.h`, `.../gdu-create-password-page.blp` | `lib/create_password_page.rb` | page | **no** (gap: wizard is 5 pages upstream, port has 4) |

## Helpers / low-level support

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/libgdu/gduutils.c`, `src/libgdu/gduutils.rs` | `lib/utils.rb` | helper | yes |
| `src/disks/gduenums.h`, `src/disks/gdu-item.h`, `src/libgdu/enums.rs` | `lib/enums.rb` | enum/flags | yes |
| `src/resources/style.css` | `lib/style.rb` | stylesheet | yes |
| `src/disks/gdudvdsupport.c/.h` | `lib/dvd_support.rb` | helper (benchmark DVD read) | **no** |
| `src/disks/gduxzdecompressor.c/.h` | `lib/xz_decompressor.rb` | helper (`.img.xz` restore) | **no** |
| `src/disks/page_aligned_buffer.rs` | `lib/page_aligned_buffer.rb` | helper (O_DIRECT IO buffer) | **no** |

## Secondary binaries (separate GApplications in the same upstream tree)

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/disk-image-mounter/application.rs`, `src/disk-image-mounter/window.rs`, `src/resources/ui/gdu-image-mounter-window.blp` | *(no equivalent yet — would be its own `lib/disk_image_mounter/*.rb` + bin entry)* | application | **no** |
| `src/notify/main.c`, `src/notify/gdusdmonitor.c/.h` | *(no equivalent yet — `lib/notify/*.rb` + bin entry)* | application (background service) | **no** |

## Data: schemas, resource manifests, metadata, translations

| Upstream file(s) | → `lib/`/repo path | Kind | Present |
|---|---|---|---|
| `data/org.gnome.Disks.gschema.xml` | *(no GSettings schema in the port)* | GSettings schema | **no** |
| `src/resources/gnome-disks.gresource.xml` | *(no GResource bundle; `lib/style.rb` covers only the `style.css` entry of its ~31 files)* | GResource manifest | partial (style only) |
| `data/org.gnome.DiskUtility.desktop.in`, `data/org.gnome.DiskUtility.metainfo.xml.in`, `data/org.gnome.DiskUtility.service.in`, `data/gnome-disk-image-mounter.desktop.in` | *(no desktop/metainfo files in the port)* | app metadata | **no** |
| `po/*.po`, `po/POTFILES.in` (103 catalogues) | *(no `po/` directory in the port)* | translation catalogue | **no** |

## Summary

- 16 upstream component units already have a `lib/` file: `main.rb`,
  `window.rb`, `drive_row.rb`, `item.rb`, `space_allocation_bar.rb`,
  `combo_row.rb`, `shortcuts_dialog.rb`, `job_manager.rb`, `job_row.rb`,
  `local_job.rb`, `estimator.rb`, `create_confirm_page.rb`,
  `create_filesystem_page.rb`, `create_other_page.rb`,
  `create_partition_page.rb`, `take_ownership_dialog.rb`, plus the shared
  `utils.rb`, `enums.rb`, `style.rb`.
- 27 dialog/page/row/model/helper units have no `lib/` file yet, including
  every edit/format/resize/mount/benchmark/SMART dialog, the drive/block
  model objects (`Drive`, `Block`, `DriveHeader`, `DriveView`, `BlockRow`),
  `Manager` (the UDisks-facing object the window and rows depend on), and the
  fifth wizard page (`create-password-page`).
- 2 secondary GApplications (disk-image-mounter, the udisks-notify daemon)
  have no port presence at all.
- GSettings schema, GResource manifest, desktop/metainfo files and the `po/`
  catalogue are all unported.

This is a map of how much is left, not a punch list — pick one unit at a time
per the `component-identification` skill's scoping rule before writing code.
