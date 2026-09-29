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
Invoke-Stage 'Generate Rust bindings' {
  # Regenerate from scratch: stale files left behind by removed API modules
  # would otherwise survive and make a fresh clone differ from a warm tree.
  Remove-Item -Recurse -Force lib/src/rust, rust/src/frb_generated.rs -ErrorAction SilentlyContinue
  & flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
}
Invoke-Stage 'Dart format check' {
  & dart format --output=none --set-exit-if-changed lib test integration_test
}
Invoke-Stage 'Flutter analyze' { & flutter analyze --no-fatal-infos }
Invoke-Stage 'Flutter tests' { & flutter test }
Invoke-Stage 'Rust tests' { & cargo test --manifest-path rust/Cargo.toml }
Invoke-Stage 'Rust lints' {
  & cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
}
Invoke-Stage 'Release APK' {
  & flutter build apk --release --android-skip-build-dependency-validation
}

Write-Host "`nMVP verification passed. APK: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
