$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')

function Invoke-Stage {
  param(
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [scriptblock] $Action
  )

  Write-Host "`n== $Name ==" -ForegroundColor Cyan
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

Invoke-Stage 'Generate fixtures' { & pwsh -NoProfile -File tool/generate_fixtures.ps1 }
Invoke-Stage 'Dart format check' {
  & dart format --output=none --set-exit-if-changed lib test integration_test
}
Invoke-Stage 'Flutter analyze' { & flutter analyze --no-fatal-infos }
Invoke-Stage 'Flutter tests' { & flutter test }
Invoke-Stage 'Rust tests' { & cargo test --manifest-path rust/Cargo.toml }
Invoke-Stage 'Release APK' { & flutter build apk --release }

Write-Host "`nMVP verification passed. APK: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
