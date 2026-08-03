$ErrorActionPreference = 'Stop'

$fixtureRoot = (Join-Path $PSScriptRoot '..\test\fixtures' | Resolve-Path).Path
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

$png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')

function Write-ZipFixture {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [hashtable] $Entries
  )

  $absolutePath = Join-Path $fixtureRoot $Path
  $parent = Split-Path -Parent $absolutePath
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  if (Test-Path -LiteralPath $absolutePath) { Remove-Item -LiteralPath $absolutePath -Force }

  $stream = [System.IO.File]::Open($absolutePath, [System.IO.FileMode]::CreateNew)
  try {
    $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach ($entry in $Entries.GetEnumerator()) {
        $zipEntry = $archive.CreateEntry($entry.Key)
        $entryStream = $zipEntry.Open()
        try { $entryStream.Write($entry.Value, 0, $entry.Value.Length) }
        finally { $entryStream.Dispose() }
      }
    } finally { $archive.Dispose() }
  } finally { $stream.Dispose() }
}

$comicInfo = [Text.Encoding]::UTF8.GetBytes(@'
<ComicInfo>
  <Title>Fixture Metadata Title</Title>
  <Writer>Zephyr Test</Writer>
  <Year>2026</Year>
  <Genre>Test, Fixture</Genre>
  <Pages><Page Image="0" Type="FrontCover" /></Pages>
</ComicInfo>
'@.Trim())
$readme = [Text.Encoding]::UTF8.GetBytes('Generated test entry; no copyrighted content.')
$corrupt = [Text.Encoding]::UTF8.GetBytes('this is intentionally not an image')

Write-ZipFixture -Path 'natural-sort.cbz' -Entries @{
  '10.png' = $png
  '2.png' = $png
  'nested/001.png' = $png
  'ComicInfo.xml' = $comicInfo
  'notes.txt' = $readme
}
Write-ZipFixture -Path 'corrupt-page.cbz' -Entries @{
  '001.png' = $png
  '002.png' = $corrupt
}
Write-ZipFixture -Path 'unsupported.zip' -Entries @{
  'readme.txt' = $readme
  'page.gif' = $readme
}

Write-Output "Generated fixtures under $fixtureRoot"
