# frozen_string_literal: true

require 'adwaita'

# Style is the application stylesheet.
#
# Ported from upstream's src/resources/style.css, which GduApplication loads
# through its GResource bundle. There is no GResource here, so the same twelve
# rules are carried as a string and installed on the default display.
#
# The rules, in upstream's order:
#
#   .explanation-label            the small print under a dialog's controls
#   levelbar .strength-weak       the four passphrase-strength level bar colours
#   levelbar .strength-low
#   levelbar .strength-medium/good/high
#   .space-allocation-bar         the rounded clip SpaceAllocationBar draws in
#   .partition-row                the colour dot on a block row
#   .partition-bin                the gradient on a space-allocation segment
#   .grey .blue .green .yellow .orange .red .purple .brown
#                                 the eight partition colours Drive cycles
#                                 through, each redefined for the dark scheme
#
class Style
  CSS = <<~CSS
    .explanation-label {
    	font-size: small;
    }

    levelbar .strength-weak {
      background-color: #cc0000;
      border-color: #cc0000;
    }

    levelbar .strength-low {
      background-color: #f5ce00;
      border-color: #f5ce00;
    }

    levelbar .strength-medium,
    levelbar .strength-good,
    levelbar .strength-high {
      background-color: #73d216;
      border-color: #73d216;
    }

    .space-allocation-bar {
      border-radius: 6px;
    }

    .partition-row {
      background: var(--main-color);
      border-radius: 100%;
    }

    .partition-bin {
      background: linear-gradient(to top, var(--main-color), oklch(from var(--main-color) calc(l + 0.1) c h));
    }

    .grey {
      --main-color: #afafaf;
    }

    .blue {
      --main-color: var(--blue-4);
    }

    .green {
      --main-color: var(--green-4);
    }

    .yellow {
      --main-color: var(--yellow-4);
    }

    .orange {
      --main-color: var(--orange-4);
    }

    .red {
      --main-color: var(--red-4);
    }

    .purple {
      --main-color: var(--purple-4);
    }

    .brown {
      --main-color: var(--brown-4);
    }

    @media (prefers-color-scheme: dark) {
      .grey {
        --main-color: #808080;
      }

      .blue {
        --main-color: var(--blue-5);
      }

      .green {
        --main-color: var(--green-5);
      }

      .yellow {
        --main-color: var(--yellow-5);
      }

      .orange {
        --main-color: var(--orange-5);
      }

      .red {
        --main-color: var(--red-5);
      }

      .purple {
        --main-color: var(--purple-5);
      }

      .brown {
        --main-color: var(--brown-5);
      }
    }
  CSS

  # The eight colour classes .partition-row and .partition-bin pick their
  # --main-color from. Drive cycles through PARTITION_COLORS and hands "grey"
  # to a free-space block.
  PARTITION_COLORS = %w[blue green yellow orange red purple brown].freeze
  FREE_SPACE_COLOR = 'grey'
  COLORS = ([FREE_SPACE_COLOR] + PARTITION_COLORS).freeze

  # The level bar classes the passphrase-strength meters add.
  STRENGTH_CLASSES = %w[strength-weak strength-low strength-medium strength-good strength-high].freeze

  # Installs the stylesheet on @display, defaulting to the one the app is on.
  # Safe to call more than once: a second call replaces the first provider
  # rather than stacking another copy on top of it.
  def self.apply(display = Gdk::Display.default)
    new.apply(display)
  end

  def apply(display = Gdk::Display.default)
    display.then do |target|
      if target
        Gtk::StyleContext.remove_provider_for_display(target, provider)
        Gtk::StyleContext.add_provider_for_display(
          target,
          provider,
          Gtk::StyleProvider::PRIORITY_APPLICATION,
        )
      end
    end
  end

  def provider
    @provider ||= Gtk::CssProvider.new.tap do |css|
      css.load_from_string(CSS)
    end
  end
end
