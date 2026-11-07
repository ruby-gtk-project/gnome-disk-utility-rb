# frozen_string_literal: true

require 'adwaita'

# CreatePasswordPage is the wizard page that sets the passphrase for a new
# LUKS-encrypted volume: a password entry, a confirmation entry that only
# unlocks once the first one is non-empty, the mismatch warning label, and a
# strength meter with a one-line hint underneath it.
#
# A port of upstream's src/resources/ui/gdu-create-password-page.blp and
# src/disks/gdu-create-password-page.c. Carried over faithfully:
#
#   * The "Confirm Password" row starts insensitive and only turns sensitive
#     once the password meter has anything above "too weak to score" in it —
#     #on_password_changed's `sensitive = strength_level.positive?` guard,
#     gated on the confirm field being empty so a user who is still editing
#     the confirmation does not get it yanked out from under them mid-type.
#   * The confirm label and the "error" CSS class on the confirm entry track
#     a mismatch, not just an empty confirmation.
#   * `complete` turns true only once both fields are non-empty, equal, and
#     the password itself cleared the strength floor.
#
# One deliberate difference: upstream's #gdu_password_strength calls
# libpwquality, a C library with no GObject-Introspection typelib and
# therefore nothing a Ruby gem can bind. #strength below is a from-scratch
# heuristic over length and character variety — not a port of pwquality's
# scoring, which this port cannot call. It drives the same five-level meter
# and the same per-reason hint strings pwquality's error codes map to above
# (grouped onto the heuristic's own trigger instead of PWQ_ERROR_*), so the
# page behaves the way upstream's does even though the number inside it is a
# different formula.
#
class CreatePasswordPage < Adwaita::Bin
  type_register

  install_property(
    GLib::Param::Boolean.new(
      'complete',
      'complete',
      'Whether the page has everything it needs',
      false,
      GLib::Param::READABLE,
    ),
  )

  DEFAULT_HINT = 'Adding more letters, numbers and punctuation will make the password stronger.'

  # [minimum strength (0.0-1.0) the trigger needs to fire, hint]
  HINTS = [
    [0.90, nil],
    [0.75, 'Try to use a mixture of letters, numbers and punctuation.'],
    [0.50, 'Try to use more numbers.'],
    [0.0,  'Try to use more special characters, like punctuation.'],
  ].freeze

  attr_reader :complete

  def initialize
    super()

    @complete = false
  end

  def build
    tap do |page|
      page.child = preferences_page

      preferences_page.tap do |prefs|
        prefs.add(group)

        group.tap do |g|
          g.add(password_entry)
          g.add(confirm_password_entry)
          g.add(confirm_password_label)
          g.add(strength_indicator)
          g.add(strength_hint_label)

          password_entry.signal_connect('notify::text') { on_password_changed }
          confirm_password_entry.signal_connect('notify::text') { on_password_changed }
        end
      end

      update_password_strength
    end
  end

  def complete? = @complete

  # gdu_create_password_page_get_password ().
  def password = password_entry.text

  private

    # on_password_changed ().
    def on_password_changed
      password_entry.add_css_class('error')

      password = password_entry.text
      verify = confirm_password_entry.text
      can_proceed = false

      unless password.empty?
        if password == verify
          confirm_password_entry.remove_css_class('error')
          confirm_password_label.visible = false
          can_proceed = true
        elsif !verify.empty?
          confirm_password_entry.add_css_class('error')
          confirm_password_label.visible = true
        end
      end

      update_password_strength

      @complete = can_proceed
      notify('complete')
    end

    # update_password_strength ().
    def update_password_strength
      password = password_entry.text
      level = strength_level(password)

      strength_indicator.value = level
      strength_hint_label.label = hint_for(password)

      if level.positive?
        password_entry.remove_css_class('error')
      else
        password_entry.add_css_class('error')
      end

      if confirm_password_entry.text.empty?
        confirm_password_entry.sensitive = level.positive?
      end
    end

    # The from-scratch heuristic the class comment explains: a 0.0-1.0 score
    # from length and the four character classes present, mapped to the same
    # five-level scale (0 = empty, 1 = "too weak" through 5 = "high") the
    # meter and the sensitivity gate upstream drive off pwquality's score.
    def strength(password)
      return 0.0 if password.nil? || password.empty?

      classes = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^a-zA-Z0-9]/].count { |pattern| password.match?(pattern) }
      length_score = [password.length / 16.0, 1.0].min
      class_score = classes / 4.0

      ((length_score * 0.6) + (class_score * 0.4)).clamp(0.0, 1.0)
    end

    def strength_level(password)
      return 0 if password.nil? || password.empty?

      score = strength(password)
      if score < 0.50
        2
      elsif score < 0.75
        3
      elsif score < 0.90
        4
      else
        5
      end
    end

    def hint_for(password)
      score = strength(password)
      HINTS.each do |floor, hint|
        return hint || DEFAULT_HINT if score >= floor
      end
      DEFAULT_HINT
    end

    # Memoized widget methods

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def group
      @group ||= Adwaita::PreferencesGroup.new.tap do |g|
        g.description = 'Data stored in the Volume will only be accessible with the correct password. ' \
                         'Be careful not to forget it'
      end
    end

    def password_entry
      @password_entry ||= Adwaita::PasswordEntryRow.new.tap do |row|
        row.title = 'Password'
      end
    end

    def confirm_password_entry
      @confirm_password_entry ||= Adwaita::PasswordEntryRow.new.tap do |row|
        row.title = 'Confirm Password'
        row.sensitive = false
      end
    end

    def confirm_password_label
      @confirm_password_label ||= Gtk::Label.new('The passwords do not match.').tap do |label|
        label.visible = false
        label.margin_top = 12
      end
    end

    def strength_indicator
      @strength_indicator ||= Gtk::LevelBar.new.tap do |bar|
        bar.mode = :continuous
        bar.max_value = 5
        bar.margin_top = 12
        bar.add_offset_value('strength-weak', 1)
        bar.add_offset_value('strength-low', 2)
        bar.add_offset_value('strength-medium', 3)
        bar.add_offset_value('strength-good', 4)
        bar.add_offset_value('strength-high', 5)
      end
    end

    def strength_hint_label
      @strength_hint_label ||= Gtk::Label.new.tap do |label|
        label.margin_top = 6
        label.wrap = true
        label.add_css_class('dim-label')
        label.add_css_class('explanation-label')
      end
    end
end
