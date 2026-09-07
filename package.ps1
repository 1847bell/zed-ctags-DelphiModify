# package.ps1 — assemble the local Zed extension package (replaces the removed GitHub Actions packaging)
#
# Usage:
#   pwsh ./package.ps1                    # build wasm if needed + assemble dist/ctags/
#   pwsh ./package.ps1 -SkipWasmBuild     # only re-assemble with existing wasm
#
# Output: dist/ctags/  +  dist/ctags-zed-ctags-DelphiModify.zip  ready to upload
# as a Release attachment (Gitea and/or GitHub).

param(
    [switch]$SkipWasmBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
$distDir = Join-Path $repoRoot "dist\ctags"

# --- 1. Build the wasm component (the deployable artifact; plain cargo build is NOT) ---
if (-not $SkipWasmBuild) {
    Push-Location $repoRoot
    cargo component build --release --target wasm32-wasip1
    if ($LASTEXITCODE -ne 0) { throw "cargo component build failed" }
    Pop-Location
}

$wasmFile = Get-ChildItem -Path (Join-Path $repoRoot "target\wasm32-wasip1\release") -Filter "zed_ctags*.wasm" |
    Select-Object -First 1
if (-not $wasmFile) {
    throw "Could not find built zed_ctags wasm component under target\wasm32-wasip1\release"
}

# --- 2. Locate the prebuilt server binary (never downloaded; built from ctags-lsp-src) ---
$serverExe = Join-Path $env:LOCALAPPDATA "Zed\extensions\work\ctags\ctags-lsp-project\ctags-lsp.exe"
if (-not (Test-Path $serverExe)) {
    throw "ctags-lsp.exe not found at $serverExe — deploy it there first (see README_modify.md)"
}

# --- 3. Assemble dist/ctags/ ---
New-Item -ItemType Directory -Force -Path (Join-Path $distDir "server") | Out-Null
Copy-Item (Join-Path $repoRoot "extension.toml") (Join-Path $distDir "extension.toml") -Force
Copy-Item $wasmFile.FullName (Join-Path $distDir "extension.wasm") -Force
Copy-Item $serverExe (Join-Path $distDir "server\ctags-lsp.exe") -Force

# --- 4. Generated install.ps1 (copies into Zed's extension dirs) ---
$installPs1 = @'
$ErrorActionPreference = "Stop"
$installedTarget = Join-Path $env:LOCALAPPDATA "Zed\extensions\installed\ctags"
New-Item -ItemType Directory -Force -Path $installedTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "extension.toml") -Destination $installedTarget -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "extension.wasm") -Destination $installedTarget -Force

$serverSource = Join-Path $PSScriptRoot "server\ctags-lsp.exe"
if (Test-Path -LiteralPath $serverSource) {
    $serverTarget = Join-Path $env:LOCALAPPDATA "Zed\extensions\work\ctags\ctags-lsp-project"
    New-Item -ItemType Directory -Force -Path $serverTarget | Out-Null
    Copy-Item -LiteralPath $serverSource -Destination (Join-Path $serverTarget "ctags-lsp.exe") -Force
}

Write-Host "Installed ctags Zed extension to $installedTarget"
Write-Host "Restart Zed after installation."
'@
Set-Content -LiteralPath (Join-Path $distDir "install.ps1") -Value $installPs1 -Encoding UTF8

# --- 5. Zip for Release upload ---
$zipPath = Join-Path $repoRoot "dist\ctags-zed-ctags-DelphiModify.zip"
Compress-Archive -Path (Join-Path $distDir "*") -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "Package ready:"
Write-Host "  $distDir"
Write-Host "  $zipPath"
Write-Host ""
Write-Host "Release steps:"
Write-Host "  1. git tag vX.Y.Z && git push fork vX.Y.Z"
Write-Host "  2. Upload the zip as a Release attachment on Gitea and GitHub."
Write-Host "  3. Local install: run install.ps1 from the extracted zip, then restart Zed."
