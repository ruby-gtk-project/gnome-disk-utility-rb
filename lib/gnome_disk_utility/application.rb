# frozen_string_literal: true

require_relative "../main"

module GnomeDiskUtility
  # The gem-facing name for the application object.
  #
  # The port proper lives in flat files under lib/, one per upstream source
  # file, the way the pilot port at gnome-contacts-rb is laid out; this is the
  # namespaced entry point the gemspec's exe/ launcher and the Nix wrapper
  # expect to find.
  Application = ::App
end
