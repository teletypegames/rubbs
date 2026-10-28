# CLAUDE.md

rubbs: the `bbs` gem, a Ruby library for telnet BBS servers. `README.md` is the
user guide; the API reference is the RDoc published to the wiki at
https://wiki.teletypegames.org/rdoc/bbs/latest/ on every release tag.

## Documenting code: write for RDoc

The API reference is generated from the source with RDoc, and CI fails below
100% coverage. Every change keeps the code fully documented:

- Every class, module, constant, attribute (`attr_*`) and public or protected
  method gets an RDoc comment directly above it. Private methods are not
  required, but document them when the behaviour is not obvious.
- Say what the thing is or does, its arguments, its return value, the
  exceptions it raises and side effects (output written to the session,
  state changed). Not its history: the why of a change goes in the commit.
- Use RDoc markup, not Markdown or YARD tags: `+code+` for a single word,
  `<tt>code with spaces</tt>`, `*bold*`, `_emphasis_`, cross-references by
  name (`BBS::Session`, `#render`), labelled lists for options:

    # Draws the window on +buffer+.
    #
    # [buffer]  the BBS::FrameBuffer to draw into
    # [focused] whether the window has the keyboard focus
    #
    # Returns +self+.

- Examples go in an indented block (two extra spaces after the `#`).
- One comment above an `attr_reader :a, :b` line documents all names on it;
  give each constant its own comment.
- Do not hide things from RDoc with `:nodoc:` to reach the coverage; make a
  helper `private` instead if it is not part of the API.
- Check before committing:

    rdoc -C lib          # must print 100.00% documented
    rdoc -o /tmp/bbs-doc --main README.md lib README.md   # look at the output

## Releases

The version lives in `bbs.gemspec`. A release is a version bump commit plus an
annotated tag `vX.Y.Z` matching it; pushing the tag publishes the RDoc. CI
rejects a tag that does not match the gemspec version.
