# frozen_string_literal: true

module BBS
  module Auth
    # How accounts compare names. A name is one account in any case (its
    # key), and two names that look the same on a screen share a skeleton:
    # "Tasi" and "Tаsi" with a Cyrillic а, or "TASl" with an l (a caller
    # types the case of the name they show, so I, i, l and 1 are one).
    module Names
      # Letters of other scripts that a terminal draws like a Latin one, and
      # the digits and marks that pass for letters.
      LOOK_ALIKES = {
        'а' => 'a',
        'в' => 'b',
        'е' => 'e',
        'ё' => 'e',
        'к' => 'k',
        'м' => 'm',
        'н' => 'h',
        'о' => 'o',
        'р' => 'p',
        'с' => 'c',
        'т' => 't',
        'у' => 'y',
        'х' => 'x',
        'ѕ' => 's',
        'і' => 'l',
        'ї' => 'l',
        'ј' => 'j',
        'һ' => 'h',
        'ԁ' => 'd',
        'ԛ' => 'q',
        'ԝ' => 'w',
        'ӏ' => 'l',
        'ү' => 'y',
        'ɡ' => 'g',
        'α' => 'a',
        'β' => 'b',
        'ε' => 'e',
        'ζ' => 'z',
        'η' => 'n',
        'ι' => 'l',
        'κ' => 'k',
        'μ' => 'm',
        'ν' => 'v',
        'ο' => 'o',
        'ρ' => 'p',
        'τ' => 't',
        'υ' => 'u',
        'χ' => 'x',
        'ϲ' => 'c',
        'ı' => 'l',
        '0' => 'o',
        '1' => 'l',
        '|' => 'l',
        'i' => 'l'
      }.freeze
      # Any one of LOOK_ALIKES.
      LOOK_ALIKE = Regexp.union(LOOK_ALIKES.keys)
      # What an account's name may be: a letter or digit first, then letters,
      # digits, spaces and <tt>._-</tt>, at most 20 in all.
      PATTERN = /\A[\p{L}\p{N}][\p{L}\p{N} ._-]{0,19}\z/

      module_function

      # The account +name+ belongs to, whatever its case.
      def key(name) = name.to_s.strip.downcase

      # What +name+ looks like: NFKC, case folded, the look-alikes mapped to
      # the Latin letter they pass for.
      def skeleton(name) = name.to_s.strip.unicode_normalize(:nfkc).downcase(:fold).gsub(LOOK_ALIKE, LOOK_ALIKES)

      # +raw+ as a name: valid UTF-8, trimmed, inner spaces single; +nil+
      # when it is not one PATTERN allows.
      def clean(raw)
        name = Text.utf8(raw.to_s).strip.gsub(/\s+/, ' ')
        name.match?(PATTERN) ? name : nil
      end
    end
  end
end
