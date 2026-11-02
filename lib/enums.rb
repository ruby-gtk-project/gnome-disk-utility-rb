# frozen_string_literal: true

# Enums gathers the enumerations and flag sets the rest of the port keys off.
#
# Ported from upstream's src/disks/gduenums.h (GduPowerStateFlags,
# GduDeviceTreeModelFlags), src/disks/gdu-item.h (GduFeature) and
# src/libgdu/enums.rs (GduFormatDurationFlags, ResizeFlags, UnitSize).
#
# Upstream declares these as GLib flags/enum types so they can travel through a
# GValue on a GObject property. Nothing in this port puts them in a GValue, so
# they are plain integer bitmasks with the predicate helpers in Flags instead.
#
module Enums
  # Bit tests shared by every flag set below. `features & GDU_FEATURE_FORMAT`
  # in C becomes `Enums::Flags.set?(features, Enums::Feature::FORMAT)`.
  module Flags
    def self.set?(value, flag) = !(value.to_i & flag.to_i).zero?

    def self.any?(value, *flags) = flags.flatten.any? { |flag| set?(value, flag) }

    def self.all?(value, *flags) = flags.flatten.all? { |flag| set?(value, flag) }

    # The flags of @names (a hash of name => bit) that @value carries, in the
    # order the hash lists them. Handy for debugging and for the specs.
    def self.names(value, names)
      names.select { |_name, flag| set?(value, flag) }.keys
    end
  end

  # GduFeature, from src/disks/gdu-item.h. Every action the drive view, the
  # drive header menu and the block row menu can offer is one of these bits;
  # Drive#features and Block#features compute the set, and the widgets enable
  # or disable their actions from it.
  module Feature
    NONE               = 0
    FORMAT             = 1 << 0
    CREATE_IMAGE       = 1 << 1
    RESTORE_IMAGE      = 1 << 2
    CREATE_PARTITION   = 1 << 3
    EDIT_PARTITION     = 1 << 4
    DELETE_PARTITION   = 1 << 5
    RESIZE_PARTITION   = 1 << 6
    CHECK_FILESYSTEM   = 1 << 7
    REPAIR_FILESYSTEM  = 1 << 8
    EDIT_LABEL         = 1 << 9
    CAN_SWAPON         = 1 << 10
    CAN_SWAPOFF        = 1 << 11
    CAN_MOUNT          = 1 << 12
    CAN_UNMOUNT        = 1 << 13
    CAN_LOCK           = 1 << 14
    CAN_UNLOCK         = 1 << 15
    CHANGE_PASSPHRASE  = 1 << 16
    TAKE_OWNERSHIP     = 1 << 17
    BENCHMARK          = 1 << 18
    CONFIGURE_FSTAB    = 1 << 19
    CONFIGURE_CRYPTTAB = 1 << 20
    SMART              = 1 << 21
    SETTINGS           = 1 << 22
    STANDBY            = 1 << 23
    WAKEUP             = 1 << 24
    POWEROFF           = 1 << 25
    EJECT              = 1 << 26
    DETACH             = 1 << 27

    ALL = {
      format:             FORMAT,
      create_image:       CREATE_IMAGE,
      restore_image:      RESTORE_IMAGE,
      create_partition:   CREATE_PARTITION,
      edit_partition:     EDIT_PARTITION,
      delete_partition:   DELETE_PARTITION,
      resize_partition:   RESIZE_PARTITION,
      check_filesystem:   CHECK_FILESYSTEM,
      repair_filesystem:  REPAIR_FILESYSTEM,
      edit_label:         EDIT_LABEL,
      can_swapon:         CAN_SWAPON,
      can_swapoff:        CAN_SWAPOFF,
      can_mount:          CAN_MOUNT,
      can_unmount:        CAN_UNMOUNT,
      can_lock:           CAN_LOCK,
      can_unlock:         CAN_UNLOCK,
      change_passphrase:  CHANGE_PASSPHRASE,
      take_ownership:     TAKE_OWNERSHIP,
      benchmark:          BENCHMARK,
      configure_fstab:    CONFIGURE_FSTAB,
      configure_crypttab: CONFIGURE_CRYPTTAB,
      smart:              SMART,
      settings:           SETTINGS,
      standby:            STANDBY,
      wakeup:             WAKEUP,
      poweroff:           POWEROFF,
      eject:              EJECT,
      detach:             DETACH,
    }.freeze
  end

  # GduPowerStateFlags, from src/disks/gduenums.h.
  module PowerStateFlags
    NONE     = 0
    STANDBY  = 1 << 0
    CHECKING = 1 << 1
    FAILED   = 1 << 2

    ALL = {
      standby:  STANDBY,
      checking: CHECKING,
      failed:   FAILED,
    }.freeze
  end

  # GduDeviceTreeModelFlags, from src/disks/gduenums.h.
  module DeviceTreeModelFlags
    NONE                = 0
    FLAT                = 1 << 0
    UPDATE_POWER_STATE  = 1 << 1
    UPDATE_PULSE        = 1 << 2
    ONE_LINE_NAME       = 1 << 3
    INCLUDE_DEVICE_NAME = 1 << 4
    INCLUDE_NONE_ITEM   = 1 << 5

    ALL = {
      flat:                FLAT,
      update_power_state:  UPDATE_POWER_STATE,
      update_pulse:        UPDATE_PULSE,
      one_line_name:       ONE_LINE_NAME,
      include_device_name: INCLUDE_DEVICE_NAME,
      include_none_item:   INCLUDE_NONE_ITEM,
    }.freeze
  end

  # GduFormatDurationFlags, from src/libgdu/enums.rs. Utils.format_duration_usec
  # takes these.
  module FormatDurationFlags
    NONE                = 0
    SUB_SECOND_PRECISION = 1 << 0
    NO_SECONDS           = 1 << 1

    ALL = {
      sub_second_precision: SUB_SECOND_PRECISION,
      no_seconds:           NO_SECONDS,
    }.freeze
  end

  # ResizeFlags, from src/libgdu/enums.rs — the same bits libblockdev reports
  # for a filesystem's resize support. Note the deliberate gap at bit 0: the
  # values start at `1 << 1`, exactly as upstream has them.
  module ResizeFlags
    NONE           = 0
    OFFLINE_SHRINK = 1 << 1
    OFFLINE_GROW   = 1 << 2
    ONLINE_SHRINK  = 1 << 3
    ONLINE_GROW    = 1 << 4

    ALL = {
      offline_shrink: OFFLINE_SHRINK,
      offline_grow:   OFFLINE_GROW,
      online_shrink:  ONLINE_SHRINK,
      online_grow:    ONLINE_GROW,
    }.freeze
  end

  # UnitSize, from src/libgdu/enums.rs. Upstream's comment — "Keep in sync with
  # Glade file" — refers to the unit combo rows in the create/resize dialogs,
  # whose model rows are in this order.
  module UnitSize
    BYTE    = :byte
    KBYTE   = :kbyte
    MBYTE   = :mbyte
    GBYTE   = :gbyte
    TBYTE   = :tbyte
    PBYTE   = :pbyte
    KIBYTE  = :kibyte
    MIBYTE  = :mibyte
    GIBYTE  = :gibyte
    TIBYTE  = :tibyte
    PIBYTE  = :pibyte

    ORDER = [
      BYTE,
      KBYTE,
      MBYTE,
      GBYTE,
      TBYTE,
      PBYTE,
      KIBYTE,
      MIBYTE,
      GIBYTE,
      TIBYTE,
      PIBYTE,
    ].freeze

    SIZE_IN_BYTES = {
      BYTE   => 1,
      KBYTE  => 1_000,
      MBYTE  => 1_000_000,
      GBYTE  => 1_000_000_000,
      TBYTE  => 1_000_000_000_000,
      PBYTE  => 1_000_000_000_000_000,
      KIBYTE => 1 << 10,
      MIBYTE => 1 << 20,
      GIBYTE => 1 << 30,
      TIBYTE => 1 << 40,
      PIBYTE => 1 << 50,
    }.freeze

    # The labels the unit combo rows show, in ORDER.
    DISPLAY_NAMES = {
      BYTE   => 'bytes',
      KBYTE  => 'kB',
      MBYTE  => 'MB',
      GBYTE  => 'GB',
      TBYTE  => 'TB',
      PBYTE  => 'PB',
      KIBYTE => 'KiB',
      MIBYTE => 'MiB',
      GIBYTE => 'GiB',
      TIBYTE => 'TiB',
      PIBYTE => 'PiB',
    }.freeze

    def self.size_in_bytes(unit) = SIZE_IN_BYTES.fetch(unit)

    def self.display_name(unit) = DISPLAY_NAMES.fetch(unit)

    def self.at(index) = ORDER.fetch(index)

    def self.index_of(unit) = ORDER.index(unit)
  end

  # GduLocalJobState and GduLocalJobResult, from src/disks/gdulocaljob.h. The
  # C side registers them as a GLib enum so GduJobRow can bind `notify::state`;
  # LocalJob notifies its observers directly, so symbols are enough.
  module LocalJobState
    QUEUED    = :queued
    RUNNING   = :running
    CANCELING = :canceling
    FINISHED  = :finished

    ORDER = [QUEUED, RUNNING, CANCELING, FINISHED].freeze
  end

  module LocalJobResult
    SUCCESS   = :success
    CANCELLED = :cancelled
    ERROR     = :error

    ORDER = [SUCCESS, CANCELLED, ERROR].freeze
  end
end
