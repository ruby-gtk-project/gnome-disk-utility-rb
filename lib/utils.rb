# frozen_string_literal: true

require 'adwaita'
require 'json'
require 'uri'
require 'fileutils'
require_relative 'enums'

# Utils holds the helpers the rest of the app shares, plus the three dialogs
# every part of it raises: an error, a message, and a confirmation.
#
# Ported from upstream's src/libgdu/gduutils.c and src/libgdu/gduutils.rs (the
# two are kept in sync upstream; the C file carries the comment saying so).
#
# Three deliberate differences, all forced by libudisks having no Ruby binding:
#
#   * The helpers upstream hands a UDisksBlock, UDisksDrive or
#     UDisksPartitionTable take the plain values they actually read instead —
#     the Configuration array, the MediaCompatibility strv, a list of
#     PartitionInfo. The algorithms are unchanged.
#
#   * gdu_utils_get_unused_for_block and gdu_utils_get_total_size_for_block call
#     statvfs(2) on the filesystem's first mount point. Ruby's standard library
#     has no statvfs, so #unused_for_mount_point and #total_size_for_mount_point
#     ask GIO for filesystem::free and filesystem::size, which is the same
#     statvfs call one layer up.
#
#   * gdu_utils_file_chooser_for_disk_images_set_default_folder writes the
#     org.gnome.Disks `image-dir-uri` GSettings key. A GSettings key needs a
#     compiled schema installed system-wide, which would make the port
#     unrunnable from a checkout, so the same key is kept in a small JSON file
#     under XDG_CONFIG_HOME.
#
module Utils
  USEC_PER_SEC = 1_000_000
  USEC_PER_MINUTE = USEC_PER_SEC * 60
  USEC_PER_HOUR = USEC_PER_MINUTE * 60
  USEC_PER_DAY = USEC_PER_HOUR * 24
  USEC_PER_YEAR = USEC_PER_DAY * 365.25
  USEC_PER_MONTH = USEC_PER_YEAR / 12.0
  USEC_PER_MSEC = 1_000

  # The UDisks service, and the one object on it the helpers below talk to.
  UDISKS_NAME = 'org.freedesktop.UDisks2'
  UDISKS_MANAGER_PATH = '/org/freedesktop/UDisks2/Manager'
  UDISKS_MANAGER_INTERFACE = 'org.freedesktop.UDisks2.Manager'
  PROPERTIES_INTERFACE = 'org.freedesktop.DBus.Properties'
  DBUS_TIMEOUT_DEFAULT = -1

  FormatDurationFlags = Enums::FormatDurationFlags
  UnitSize = Enums::UnitSize

  # The subset of a UDisks Partition interface the partition-geometry helpers
  # below read. Block builds these from its D-Bus properties.
  PartitionInfo = Data.define(
    :offset,
    :size,
    :number,
    :container,
    :contained,
  ) do
    def container? = container
    def contained? = contained
  end

  # The fields upstream's ConfirmationDialogData struct carries.
  ConfirmationDialogData = Data.define(
    :message,
    :description,
    :response_verb,
    :response_appearance,
  )

  # --- Block configuration ------------------------------------------------

  # gdu_utils_has_configuration (). @configuration is the Block interface's
  # Configuration property: an array of [type, details] pairs. Returns
  # [configured, has_passphrase]; has_passphrase is only ever true for
  # "crypttab" entries whose passphrase-path is set and does not live in /dev.
  def self.has_configuration(configuration, type)
    Array(configuration).find { |config_type, _details| config_type == type }.then do |entry|
      if entry.nil?
        [false, false]
      else
        [true, crypttab_passphrase?(type, entry[1])]
      end
    end
  end

  # The "crypttab" half of gdu_utils_has_configuration: a passphrase counts
  # only when passphrase-path is set and does not point into /dev.
  def self.crypttab_passphrase?(type, details)
    if type == 'crypttab'
      byte_string(details&.[]('passphrase-path')).then do |passphrase_path|
        !passphrase_path.empty? && !passphrase_path.start_with?('/dev')
      end
    else
      false
    end
  end

  # gdu_utils_has_userspace_mount_option (). @options is the Block interface's
  # UserspaceMountOptions property.
  def self.userspace_mount_option?(options, option)
    Array(options).include?(option)
  end

  # --- Paths and URIs -----------------------------------------------------

  # gdu_utils_unfuse_path (): maps a GVfs FUSE path back to the URI it stands
  # for, then shortens $HOME to "~".
  def self.unfuse_path(path)
    Gio::File.new_for_path(path).uri.then do |uri|
      if uri.start_with?('file:')
        shorten_home(path)
      else
        shorten_home(URI::DEFAULT_PARSER.unescape(uri))
      end
    end
  end

  # gdu_utils_get_pretty_uri ().
  def self.pretty_uri(file)
    if file.native?
      shorten_home(file.path)
    else
      URI::DEFAULT_PARSER.unescape(file.uri)
    end
  end

  # The "$HOME -> ~" rewrite both of the two above do. Upstream only rewrites
  # when the remainder starts at a path separator, so "/home/nathanielle" is
  # left alone for a $HOME of "/home/nathan".
  def self.shorten_home(path)
    GLib.home_dir.chomp('/').then do |home|
      if home.length > 2 && path.start_with?("#{home}/")
        "~/#{path[(home.length + 1)..]}"
      else
        path
      end
    end
  end

  # --- The disk-image file dialog -----------------------------------------

  # gdu_utils_configure_file_dialog_for_disk_images ().
  def self.configure_file_dialog_for_disk_images(file_dialog, set_file_types: true, allow_compressed: true)
    file_dialog.tap do |dialog|
      dialog.initial_folder = Gio::File.new_for_path(documents_dir)

      if set_file_types
        disk_image_filter(allow_compressed).then do |disk_images|
          dialog.filters = Gio::ListStore.new(Gtk::FileFilter).tap do |filters|
            filters.append(all_files_filter)
            filters.append(disk_images)
          end
          dialog.default_filter = disk_images
        end
      end
    end
  end

  def self.all_files_filter
    Gtk::FileFilter.new.tap do |filter|
      filter.name = 'All Files'
      filter.add_pattern('*')
    end
  end

  def self.disk_image_filter(allow_compressed)
    Gtk::FileFilter.new.tap do |filter|
      if allow_compressed
        filter.name = 'Disk Images (*.img, *.img.xz, *.iso)'
      else
        filter.name = 'Disk Images (*.img, *.iso)'
      end

      filter.add_mime_type('application/x-raw-disk-image')

      if allow_compressed
        filter.add_mime_type('application/x-raw-disk-image-xz-compressed')
      end

      filter.add_mime_type('application/x-cd-image')
    end
  end

  def self.documents_dir
    GLib.get_user_special_dir(GLib::UserDirectory::DIRECTORY_DOCUMENTS) || GLib.home_dir
  end

  # gdu_utils_file_chooser_for_disk_images_set_default_folder (): remembers
  # where the user last picked a disk image.
  def self.image_dir_uri=(folder)
    write_setting('image-dir-uri', folder.uri)
  end

  def self.image_dir_uri = read_setting('image-dir-uri')

  # The stand-in for the org.gnome.Disks and org.gnome.Disks.window-state
  # GSettings schemas: one JSON file, the same keys. Window keeps its geometry
  # here under "window-initial-state".
  def self.settings_path
    File.join(GLib.user_config_dir, 'gnome-disk-utility-rb', 'settings.json')
  end

  def self.read_setting(key, default = nil)
    settings.fetch(key, default)
  end

  def self.write_setting(key, value)
    settings.merge(key => value).then do |updated|
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.pretty_generate(updated))
      @settings = updated
      value
    end
  end

  def self.settings
    @settings ||= JSON.parse(File.read(settings_path))
  rescue Errno::ENOENT, JSON::ParserError
    @settings = {}
  end

  # --- The seat -----------------------------------------------------------

  # gdu_utils_get_seat (). Upstream asks logind for this session's seat through
  # sd_pid_get_session/sd_session_get_seat when built with HAVE_LOGIND, and
  # returns NULL otherwise. There is no sd-login binding for Ruby, so this
  # reads the XDG_SEAT variable logind sets on every seat-attached session; the
  # answer is the same string, and an unset variable gives upstream's NULL.
  def self.seat
    ENV['XDG_SEAT'].then do |seat|
      if seat.nil? || seat.empty?
        nil
      else
        seat
      end
    end
  end

  # --- Durations ----------------------------------------------------------

  # gdu_utils_format_duration_usec ().
  def self.format_duration_usec(usec, flags = FormatDurationFlags::NONE)
    split_duration(usec.to_i).then do |parts|
      duration_phrase(parts, flags)
    end
  end

  # The cascade of floor-and-subtract gdu_utils_format_duration_usec opens with.
  def self.split_duration(usec)
    remaining = usec
    parts = {}

    [
      [:years, USEC_PER_YEAR],
      [:months, USEC_PER_MONTH],
      [:days, USEC_PER_DAY],
      [:hours, USEC_PER_HOUR],
      [:minutes, USEC_PER_MINUTE],
      [:seconds, USEC_PER_SEC],
    ].each do |name, unit|
      parts[name] = (remaining / unit).floor
      remaining -= parts[name] * unit
    end

    parts[:milliseconds] = (remaining / USEC_PER_MSEC).floor
    parts
  end

  # The if/else ladder that picks which units to name. The strings, the commas
  # and the "and" are upstream's, one translation context per branch.
  def self.duration_phrase(parts, flags)
    no_seconds = Enums::Flags.set?(flags, FormatDurationFlags::NO_SECONDS)
    sub_second = Enums::Flags.set?(flags, FormatDurationFlags::SUB_SECOND_PRECISION)

    if parts[:years].positive?
      "#{plural(parts[:years], 'year')}, #{plural(parts[:months], 'month')} and #{plural(parts[:days], 'day')}"
    elsif parts[:months].positive?
      "#{plural(parts[:months], 'month')} and #{plural(parts[:days], 'day')}"
    elsif parts[:days].positive?
      "#{plural(parts[:days], 'day')} and #{plural(parts[:hours], 'hour')}"
    elsif parts[:hours].positive?
      "#{plural(parts[:hours], 'hour')} and #{plural(parts[:minutes], 'minute')}"
    elsif parts[:minutes].positive?
      minutes_phrase(parts, no_seconds)
    elsif parts[:seconds].positive? || !sub_second || no_seconds
      seconds_phrase(parts, no_seconds)
    else
      plural(parts[:milliseconds], 'milli-second')
    end
  end

  def self.minutes_phrase(parts, no_seconds)
    if no_seconds
      plural(parts[:minutes], 'minute')
    else
      "#{plural(parts[:minutes], 'minute')} and #{plural(parts[:seconds], 'second')}"
    end
  end

  def self.seconds_phrase(parts, no_seconds)
    if no_seconds
      'Less than a minute'
    else
      plural(parts[:seconds], 'second')
    end
  end

  # g_dngettext (GETTEXT_PACKAGE, "%d thing", "%d things", value).
  def self.plural(value, singular)
    if value == 1
      "#{value} #{singular}"
    else
      "#{value} #{singular}s"
    end
  end

  # --- Drives and partitions ----------------------------------------------

  # gdu_utils_is_flash (): @media_compatibility is the Drive interface's
  # MediaCompatibility property.
  def self.flash?(media_compatibility)
    Array(media_compatibility).any? { |media| media.start_with?('flash') }
  end

  # gdu_utils_count_primary_dos_partitions ().
  def self.count_primary_dos_partitions(partitions)
    partitions.count { |partition| !partition.contained? }
  end

  # gdu_utils_have_dos_extended ().
  def self.dos_extended?(partitions)
    partitions.any?(&:container?)
  end

  # gdu_utils_is_inside_dos_extended ().
  def self.inside_dos_extended?(partitions, offset)
    partitions.any? do |partition|
      partition.container? && offset >= partition.offset && offset < partition.offset + partition.size
    end
  end

  # gdu_utils_calc_space_to_grow (): how far @partition could be grown before
  # it would run into the next thing on the disk.
  def self.calc_space_to_grow(table_size, partitions, partition)
    current_end = partition.offset + partition.size
    next_pos = table_size

    partitions.each do |other|
      if other.number != partition.number
        start = other.offset
        finish = start + other.size

        if finish > current_end && finish < next_pos
          next_pos = finish
        end

        if start >= current_end && start < next_pos
          next_pos = start
        end
      end
    end

    next_pos - partition.offset
  end

  # gdu_utils_calc_space_to_shrink_extended (): the smallest an extended
  # partition can get without cutting into the logical partitions inside it.
  def self.calc_space_to_shrink_extended(partitions, partition)
    minimum = partition.offset + 1
    maximum = minimum + partition.size

    partitions.each do |other|
      if other.number != partition.number
        (other.offset + other.size).then do |finish|
          if finish > minimum && finish <= maximum
            minimum = finish
          end
        end
      end
    end

    minimum - partition.offset
  end

  # gdu_util_is_same_size (): whether a set of block sizes is close enough to
  # treat as equal. Returns [same, min_size].
  def self.same_size?(sizes)
    if sizes.empty?
      [false, nil]
    else
      sizes.min.then do |min_size|
        sizes.max.then do |max_size|
          spread = max_size - min_size
          [!(spread > min_size * 101 / 100 && spread > 1_048_576), min_size]
        end
      end
    end
  end

  # gdu_utils_get_unused_for_block () / gdu_utils_get_total_size_for_block ():
  # -1 when the filesystem is not mounted or cannot be looked at.
  def self.unused_for_mount_point(mount_point)
    filesystem_attribute(mount_point, 'filesystem::free')
  end

  def self.total_size_for_mount_point(mount_point)
    filesystem_attribute(mount_point, 'filesystem::size')
  end

  def self.filesystem_attribute(mount_point, attribute)
    if mount_point.nil? || mount_point.empty?
      -1
    else
      begin
        Gio::File.new_for_path(mount_point)
          .query_filesystem_info(attribute, nil)
          .get_attribute_uint64(attribute)
      # Gio's errors descend from Gio::Error, which is a StandardError rather
      # than a GLib::Error in these bindings.
      rescue StandardError
        -1
      end
    end
  end

  # --- Filesystem capabilities --------------------------------------------

  # gdu_utils_can_take_ownership ().
  def self.can_take_ownership?(fstype)
    !['ntfs', 'vfat', 'exfat'].include?(fstype)
  end

  # gdu_utils_can_format (): whether mkfs for @fstype is installed on the
  # daemon side, and the name of the missing utility when it is not. Returns
  # [available, missing_util].
  #
  # Upstream reads UDisksManager's SupportedFilesystems property and calls
  # CanFormat once per entry, caching the answers for the lifetime of the
  # process unless asked to flush. There is no libudisks binding here, so the
  # two go straight to the bus — they are a property read and a method call on
  # org.freedesktop.UDisks2.Manager, and need nothing a UDisksClient adds.
  #
  # A filesystem UDisks does not list, or a bus that cannot be reached, gives
  # [false, nil] — the same answer upstream's cache miss gives.
  def self.can_format(fstype, flush: false)
    if flush
      @can_format_cache = nil
    end

    can_format_cache.fetch(fstype, [false, nil])
  end

  def self.can_format?(fstype) = can_format(fstype).first

  def self.can_format_cache
    @can_format_cache ||= supported_filesystems.to_h { |fs_type| [fs_type, query_can_format(fs_type)] }
  end

  # UDisksManager's SupportedFilesystems property.
  def self.supported_filesystems
    Array(udisks_manager_property('SupportedFilesystems'))
  end

  # UDisksManager.CanFormat (s) → (bs).
  def self.query_can_format(fs_type)
    call_udisks_manager('CanFormat', fs_type).then do |reply|
      if reply.nil?
        [false, nil]
      else
        reply.first
      end
    end
  end

  def self.udisks_manager_property(name)
    call_udisks_manager(
      'Get',
      UDISKS_MANAGER_INTERFACE,
      name,
      interface: PROPERTIES_INTERFACE,
    ).then do |reply|
      reply&.first
    end
  end

  # A synchronous call on the UDisks Manager object, or nil when the daemon is
  # not there. Errors are swallowed because every caller treats "no answer" and
  # "no support" alike, exactly as the cache miss above does.
  def self.call_udisks_manager(method, *arguments, interface: UDISKS_MANAGER_INTERFACE)
    system_bus&.call_sync(
      UDISKS_NAME,
      UDISKS_MANAGER_PATH,
      interface,
      method,
      argument_tuple(arguments),
      nil,
      :none,
      DBUS_TIMEOUT_DEFAULT,
      nil,
    )
  rescue StandardError
    nil
  end

  # GDBus wants the arguments as a tuple variant, and the Ruby bindings build a
  # tuple only from its GVariant text form.
  def self.argument_tuple(arguments)
    if arguments.empty?
      nil
    else
      arguments.map { |argument| argument.to_s.inspect }.then do |parts|
        GLib::Variant.parse("(#{parts.join(',')}#{one_tuple_comma(parts)})")
      end
    end
  end

  # A one-element tuple's text form needs the trailing comma that tells it
  # apart from a parenthesised value; a longer one must not have it.
  def self.one_tuple_comma(parts)
    if parts.one?
      ','
    else
      ''
    end
  end

  def self.system_bus
    @system_bus ||= Gio.bus_get_sync(:system, nil)
  rescue StandardError
    nil
  end

  # gdu_utils_get_max_label_length (). G_MAXUINT means "no limit"; nil says the
  # same thing without pretending to a number.
  def self.max_label_length(fstype)
    case fstype
    when 'exfat' then 15
    when 'vfat' then 11
    end
  end

  # _gtk_entry_buffer_truncate_bytes (): trims a buffer to @max_bytes without
  # splitting a UTF-8 sequence. Returns true when it had to cut something.
  def self.truncate_entry_buffer_bytes(buffer, max_bytes)
    max_utf8_length = max_bytes

    while buffer.bytes > max_bytes
      buffer.delete_text(max_utf8_length, -1)
      max_utf8_length -= 1
    end

    max_utf8_length != max_bytes
  end

  # gdu_utils_get_default_unit (): the unit the size entries should start in.
  def self.default_unit(size)
    if size > UnitSize.size_in_bytes(UnitSize::TBYTE) * 10
      UnitSize::TBYTE
    elsif size > UnitSize.size_in_bytes(UnitSize::GBYTE) * 10
      UnitSize::GBYTE
    elsif size > UnitSize.size_in_bytes(UnitSize::MBYTE) * 10
      UnitSize::MBYTE
    elsif size > UnitSize.size_in_bytes(UnitSize::KBYTE) * 10
      UnitSize::KBYTE
    else
      UnitSize::BYTE
    end
  end

  # --- The mount-options entry helpers ------------------------------------

  # has_option (), the static helper the two update functions below share.
  # Returns [found, value]; value is only set when @check_prefix is true.
  def self.option?(options_text, option, check_prefix: false)
    options_text.to_s.split(',').find { |candidate| option_matches?(candidate, option, check_prefix) }.then do |found|
      if found.nil?
        [false, nil]
      elsif check_prefix
        [true, found[option.length..]]
      else
        [true, nil]
      end
    end
  end

  def self.option_matches?(candidate, option, check_prefix)
    if check_prefix
      candidate.start_with?(option)
    else
      candidate == option
    end
  end

  # add_option ().
  def self.add_option(options_entry, prefix, option, add_to_front)
    options_entry.text.then do |text|
      separator = ''

      if text.length.positive?
        separator = ','
      end

      if add_to_front
        options_entry.text = "#{option}#{separator}#{prefix}#{text}"
      else
        options_entry.text = "#{text}#{separator}#{prefix}#{option}"
      end
    end
  end

  # remove_option ().
  def self.remove_option(options_entry, option, check_prefix)
    options_entry.text.split(',').reject do |candidate|
      if check_prefix
        candidate.start_with?(option)
      else
        candidate == option
      end
    end.then { |kept| options_entry.text = kept.join(',') }
  end

  # gdu_options_update_check_option (): keeps a switch row and the free-form
  # options entry in step, whichever of the two the user just touched.
  def self.update_check_option(options_entry, option, widget, check_button, negate: false, add_to_front: false)
    opts, = option?(options_entry.text, option)
    ui = check_button.active?

    if (!negate && opts != ui) || (negate && opts == ui)
      if widget == check_button
        sync_entry_from_switch(
          options_entry,
          option,
          ui,
          negate,
          add_to_front,
        )
      else
        sync_switch_from_entry(check_button, opts, negate)
      end
    end
  end

  def self.sync_entry_from_switch(options_entry, option, ui, negate, add_to_front)
    if (!negate && ui) || (negate && !ui)
      add_option(
        options_entry,
        '',
        option,
        add_to_front,
      )
    else
      remove_option(options_entry, option, false)
    end
  end

  def self.sync_switch_from_entry(check_button, opts, negate)
    if negate
      check_button.active = !opts
    else
      check_button.active = opts
    end
  end

  # gdu_options_update_entry_option (): the same dance for an option that
  # carries a value, like "uid=1000".
  def self.update_entry_option(options_entry, option, widget, entry)
    _found, value = option?(options_entry.text, option, check_prefix: true)
    opts = value.to_s
    ui_escaped = URI::DEFAULT_PARSER.escape(entry.text)

    if opts != ui_escaped
      if widget == entry
        rewrite_entry_option(options_entry, option, ui_escaped)
      else
        entry.text = URI::DEFAULT_PARSER.unescape(opts)
      end
    end
  end

  def self.rewrite_entry_option(options_entry, option, ui_escaped)
    remove_option(options_entry, option, true)

    if ui_escaped.length.positive?
      add_option(
        options_entry,
        option,
        ui_escaped,
        false,
      )
    end
  end

  # --- The three shared dialogs -------------------------------------------

  # gdu_utils_show_message ().
  def self.show_message(title, message, parent_window)
    Adwaita::AlertDialog.new(title, message).tap do |dialog|
      dialog.add_response('close', '_Close')
      dialog.close_response = 'close'
      dialog.default_response = 'close'
      dialog.present(parent_window)
    end
  end

  # gdu_utils_show_error (). Both of the two errors upstream swallows — the user
  # dismissing the polkit prompt, and the user cancelling the operation — arrive
  # as remote D-Bus errors, so they are matched on the remote error name.
  SILENT_ERRORS = [
    'org.freedesktop.UDisks2.Error.NotAuthorizedDismissed',
    'org.freedesktop.UDisks2.Error.Cancelled',
  ].freeze

  def self.show_error(parent_window, title, error)
    remote_error_name(error).then do |name|
      unless SILENT_ERRORS.include?(name)
        show_message(title, error_message(error, name), parent_window)
      end
    end
  end

  # g_dbus_error_is_remote_error () / g_dbus_error_get_remote_error (). GDBus
  # prefixes the message of a remote error with "GDBus.Error:<name>: ", and that
  # prefix is the only place the Ruby bindings surface the name.
  def self.remote_error_name(error)
    error.message.to_s[/\AGDBus\.Error:([^:]+):/, 1]
  end

  # The "%s (%s, %d)" upstream builds after stripping the remote prefix.
  def self.error_message(error, name)
    stripped = error.message.to_s.sub(/\AGDBus\.Error:[^:]+:\s*/, '')
    domain = name || error.class.name

    "#{stripped} (#{domain}, #{error_code(error)})"
  end

  def self.error_code(error)
    if error.respond_to?(:code)
      error.code
    else
      0
    end
  end

  # gdu_utils_show_confirmation (). Upstream passes the response through a
  # GAsyncReadyCallback; here the block is called with the chosen response.
  def self.show_confirmation(parent_window, data, extra_child = nil, &callback)
    Adwaita::AlertDialog.new(data.message, data.description).tap do |dialog|
      dialog.add_response('cancel', '_Cancel')
      dialog.add_response('confirm', data.response_verb)
      dialog.close_response = 'cancel'
      dialog.set_response_appearance('confirm', data.response_appearance)
      dialog.default_response = default_confirmation_response(data.response_appearance)

      if extra_child
        dialog.extra_child = extra_child
      end

      dialog.choose(parent_window, nil) do |_source, result|
        callback&.call(dialog.choose_finish(result))
      end
    end
  end

  def self.default_confirmation_response(response_appearance)
    if response_appearance == :suggested
      'confirm'
    else
      'cancel'
    end
  end

  # The byte-string ("ay") values UDisks uses for paths come back as an array of
  # bytes with a trailing NUL.
  def self.byte_string(value)
    case value
    when nil then ''
    when String then value.sub(/\0\z/, '')
    when Array then value.pack('C*').sub(/\0\z/, '')
    else value.to_s
    end
  end
end
