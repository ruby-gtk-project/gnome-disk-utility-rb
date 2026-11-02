# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# A direct port of upstream's src/resources/ui/shortcuts-dialog.blp: an
# Adw.ShortcutsDialog with four sections — General, Disks, Drive, Partition —
# holding fourteen items between them. The titles and accelerators below are
# upstream's, unchanged.
#
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'General'   => [
      ['Help', 'F1'],
      ['Open the application menu', 'F10'],
      ['Keyboard shortcuts', '<Primary>question'],
      ['Quit', '<Primary>q'],
    ],
    'Disks'     => [
      ['Create a new empty disk image', '<Primary>n'],
      ['Attach an existing disk image', '<Primary>a'],
      ['Unselect current disk', 'Escape'],
    ],
    'Drive'     => [
      ['Open the drive menu', 'F9'],
      ['Format the drive', '<Primary>d'],
      ['Restore an image to the disk', '<Primary>r'],
      ['SMART data', '<Primary>s'],
      ['Drive settings', '<Primary>e'],
    ],
    'Partition' => [
      ['Open the volume menu', '<Shift>F9'],
      ['Format the selected volume', '<Primary>p'],
    ],
  }.freeze

  def initialize
    super()
    self.title = 'Keyboard Shortcuts'
  end

  def build
    tap do |dialog|
      SECTIONS.each do |title, items|
        dialog.add(section(title, items))
      end
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments — even though the error a no-argument
    # `new` raises advertises the signature as "title: utf8, accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
