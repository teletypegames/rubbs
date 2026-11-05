# frozen_string_literal: true

module Rubbs
  module Common
    module Web
      class MediaWiki
        # The plain-text extract of an article (TextExtracts, <tt>explaintext</tt>,
        # <tt>exsectionformat=wiki</tt>) made into what a terminal shows: cut into
        # its sections, each in Markdown for Rubbs::Common::Text::Markdown, its formulas as
        # readable text. Pure functions, no I/O.
        module Extract
          # The sections nobody reads on a terminal, by default: references,
          # notes, links, in English, Hungarian and German. #sections leaves
          # them out.
          SKIP = ['see also', 'references', 'notes', 'footnotes', 'sources', 'external links', 'further reading',
                  'bibliography', 'jegyzetek', 'források', 'forrás', 'kapcsolódó szócikkek', 'további információk',
                  'irodalom', 'külső hivatkozások', 'siehe auch', 'literatur', 'weblinks', 'einzelnachweise',
                  'anmerkungen'].freeze

          # The TeX of a formula as plain text: its symbols, its functions.
          TEX = {
            'alpha'      => 'α',
            'beta'       => 'β',
            'gamma'      => 'γ',
            'Gamma'      => 'Γ',
            'delta'      => 'δ',
            'Delta'      => 'Δ',
            'epsilon'    => 'ε',
            'varepsilon' => 'ε',
            'theta'      => 'θ',
            'lambda'     => 'λ',
            'mu'         => 'μ',
            'pi'         => 'π',
            'rho'        => 'ρ',
            'sigma'      => 'σ',
            'Sigma'      => 'Σ',
            'tau'        => 'τ',
            'phi'        => 'φ',
            'varphi'     => 'φ',
            'Phi'        => 'Φ',
            'omega'      => 'ω',
            'Omega'      => 'Ω',
            'infty'      => '∞',
            'cdot'       => '·',
            'times'      => '×',
            'pm'         => '±',
            'div'        => '÷',
            'le'         => '≤',
            'leq'        => '≤',
            'ge'         => '≥',
            'geq'        => '≥',
            'ne'         => '≠',
            'neq'        => '≠',
            'approx'     => '≈',
            'equiv'      => '≡',
            'to'         => '→',
            'rightarrow' => '→',
            'Rightarrow' => '⇒',
            'in'         => '∈',
            'sum'        => 'Σ',
            'prod'       => 'Π',
            'int'        => '∫',
            'partial'    => '∂',
            'nabla'      => '∇',
            'ldots'      => '…',
            'cdots'      => '…',
            'dots'       => '…'
          }.freeze
          # The TeX functions a formula keeps as words.
          FUNCTIONS = %w[sin cos tan cot log ln exp lim max min det arg sinh cosh tanh].freeze

          module_function

          # The plain extract (the TextExtracts of the Action API,
          # <tt>explaintext</tt>) cut at its <tt>== level-2 ==</tt> headings, as
          # <tt>[heading, markdown]</tt> pairs; the deeper headings stay in their
          # section as Markdown headings, the lead is named +title+, and the
          # sections whose heading is in +skip+ (lowercase) are left out, as are
          # empty ones.
          #
          #   Rubbs::Common::Web::MediaWiki::Extract.sections('Ada', "Ada was…\n\n== Life ==\nBorn…")
          #   # => [["Ada", "Ada was…"], ["Life", "Born…"]]
          def sections(title, extract, skip: SKIP)
            parts(title, extract).filter_map do |name, lines|
              next if skip.include?(name.downcase)

              text = markdown(lines)
              [name, text] unless text.empty?
            end
          end

          # The extract's lines by level-2 section, as <tt>[heading, lines]</tt>
          # pairs, the lead under +title+.
          def parts(title, extract)
            formulas(extract.to_s).each_line(chomp: true).with_object([[title, []]]) do |line, parts|
              level, name = heading(line)
              if level == 2 then parts << [name, []]
              else parts.last[1] << (level ? "#{'#' * (level - 1)} #{name}" : line)
              end
            end
          end

          # The level and the name of a <tt>== heading ==</tt> +line+; nil for
          # any other line.
          def heading(line)
            m = line.match(/\A(={2,6})\s*(.*?)\s*=+\s*\z/)
            m && [m[1].size, m[2]]
          end

          # +lines+ of an extract as Markdown: one paragraph a line in the
          # extract, a blank line between them. A heading with nothing under it
          # before the next one of its level goes; a line the renderer would take
          # for a heading, a code fence or a quote is escaped.
          def markdown(lines)
            out = []
            lines.each do |line|
              line = line.gsub(/[ \t]{2,}/, ' ').strip
              next if line.empty?

              if (level = heading_level(line))
                out.pop while heading_level(out.last.to_s).to_i >= level
                out << line
              else
                out << escape(line)
              end
            end
            out.pop while heading_level(out.last.to_s)
            out.join("\n\n")
          end

          # The level of a Markdown heading +line+, nil for any other line.
          def heading_level(line) = line[/\A(#+) /, 1]&.size

          # +line+ with a backslash before a start the Markdown renderer would
          # take for a heading, a code fence or a quote.
          def escape(line) = line.match?(/\A(?:#|```|>)/) ? "\\#{line}" : line

          # +text+ with its formulas made readable. A formula comes in the plain text as its MathML, one token a line, and
          # then its TeX; it is put back in its line as the TeX, made readable.
          def formulas(text)
            text = text.gsub(/\n[ \t]+\n(?:[ \t]*[^\n]*\n)*?[ \t]*\{\\displaystyle ?([^\n]*)\}[ \t]*\n(?:[ \t]*\n)?/) do
              " #{tex(::Regexp.last_match(1))} "
            end.gsub(/ +(?=[,.;:)])/, '')
            text.gsub(/\{\\displaystyle ?([^\n]*?)\}(?=\s|\z)/) { tex(::Regexp.last_match(1)) }
          end

          # The TeX +source+ of a formula as plain text: symbols, fractions and
          # roots spelled out, the markup dropped.
          def tex(source)
            s = source.dup
            nil while s.gsub!(/\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}/, '(\1)/(\2)')
            nil while s.gsub!(/\\sqrt\{([^{}]*)\}/, '√(\1)')
            s = s.gsub(/\\([A-Za-z]+)/) do
              name = ::Regexp.last_match(1)
              TEX[name] || (FUNCTIONS.include?(name) ? " #{name} " : '')
            end
            s = s.gsub(/\\[,;:! ]/, ' ').gsub(/\s+([)}])/, '\1').gsub(/([_^])\{([^{}]{2,})\}/, '\1(\2)').delete('{}\\')
            s.gsub(/\s+/, ' ').strip
          end
        end
      end
    end
  end
end
