# Test fixtures

The CBZ/ZIP files in this directory are generated from a 1×1 PNG and short
text strings by `tool/generate_fixtures.ps1`; they contain no copyrighted
comic material. Regenerate them after changing the fixture definitions:

```powershell
pwsh -File tool/generate_fixtures.ps1
```

Generation is byte-reproducible: entries are written in a fixed order and every
entry carries the same 1980-01-01 timestamp. Regenerating without changing any
definition must therefore leave `git status` clean — if it does not, the
generator has lost its determinism and that is the bug to fix.

Fixtures cover natural filename ordering, nested paths, `ComicInfo.xml`, a
page-local corrupt image, and archives containing unsupported entries.
