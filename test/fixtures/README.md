# Test fixtures

The CBZ/ZIP files in this directory are generated from a 1×1 PNG and short
text strings by `tool/generate_fixtures.ps1`; they contain no copyrighted
comic material. Regenerate them after changing the fixture definitions:

```powershell
pwsh -File tool/generate_fixtures.ps1
```

Fixtures cover natural filename ordering, nested paths, `ComicInfo.xml`, a
page-local corrupt image, and archives containing unsupported entries.
