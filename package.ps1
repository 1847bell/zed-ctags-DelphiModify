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
# Zed extension id — must equal `id` in extension.toml. It names both the
# installed/ dir and the work/ dir that holds the server binary.
$extId = "pascal-ctags"

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
$serverExe = Join-Path $env:LOCALAPPDATA "Zed\extensions\work\$extId\ctags-lsp-project\ctags-lsp.exe"
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
$installedTarget = Join-Path $env:LOCALAPPDATA "Zed\extensions\installed\__EXT_ID__"
New-Item -ItemType Directory -Force -Path $installedTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "extension.toml") -Destination $installedTarget -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "extension.wasm") -Destination $installedTarget -Force

$serverSource = Join-Path $PSScriptRoot "server\ctags-lsp.exe"
if (Test-Path -LiteralPath $serverSource) {
    $serverTarget = Join-Path $env:LOCALAPPDATA "Zed\extensions\work\__EXT_ID__\ctags-lsp-project"
    New-Item -ItemType Directory -Force -Path $serverTarget | Out-Null
    Copy-Item -LiteralPath $serverSource -Destination (Join-Path $serverTarget "ctags-lsp.exe") -Force
}

Write-Host "Installed ctags Zed extension to $installedTarget"
Write-Host "Restart Zed after installation."
'@
Set-Content -LiteralPath (Join-Path $distDir "install.ps1") -Value ($installPs1 -replace "__EXT_ID__", $extId) -Encoding UTF8

# --- 4b. Generated uninstall.ps1 (removes the file-installed copy) ---
$uninstallPs1 = @'
# uninstall.ps1 — remove the Pascal Ctags Zed extension (local file-installed copy).
#
# Usage:
#   pwsh ./uninstall.ps1                    # remove extension files only
#   pwsh ./uninstall.ps1 -RemoveSettings    # also drop the Pascal language_servers block
#                                           # from %APPDATA%\Zed\settings.json (backed up)
#   pwsh ./uninstall.ps1 -DryRun            # preview, change nothing
#
# Notes:
#   - Close Zed first. The running ctags-lsp.exe locks the work\ directory; if a
#     removal fails, quit Zed and re-run (the script is idempotent).
#   - This targets the file-installed copy made by install.ps1. A dev-extension
#     install (zed: install dev extension) is tracked by Zed itself — remove it
#     from the Extensions panel instead.

param(
    [switch]$RemoveSettings,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$extId = "__EXT_ID__"

Write-Host "== Uninstall Pascal Ctags Zed extension ($extId) =="
if (Get-Process -Name "Zed" -ErrorAction SilentlyContinue) {
    Write-Host "Note: Zed appears to be running. Close it if a removal below fails."
}

# --- 1. Remove installed/ + work/ dirs ---
foreach ($sub in @("installed", "work")) {
    $dir = Join-Path $env:LOCALAPPDATA "Zed\extensions\$sub\$extId"
    if (Test-Path -LiteralPath $dir) {
        if ($DryRun) {
            Write-Host "[dry-run] would remove $dir"
        } else {
            try {
                Remove-Item -LiteralPath $dir -Recurse -Force
                Write-Host "removed  $dir"
            } catch {
                Write-Host "WARN: could not remove $dir"
                Write-Host "      $($_.Exception.Message)"
                Write-Host "      -> close Zed, then re-run this script."
            }
        }
    } else {
        Write-Host "skipped  $dir (already gone)"
    }
}

# --- 2. Optionally clean the Pascal language_servers block from settings.json ---
$settingsPath = Join-Path $env:APPDATA "Zed\settings.json"
if ($RemoveSettings) {
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Host "settings.json not found: $settingsPath"
    } else {
        $raw = Get-Content -LiteralPath $settingsPath -Raw
        if ($raw -notmatch "pascal-ctags-lsp") {
            Write-Host "settings.json does not reference pascal-ctags-lsp - nothing to clean."
        } elseif ($DryRun) {
            Write-Host "[dry-run] would remove the Pascal language_servers block from $settingsPath"
        } else {
            # Remove the "languages": { "Pascal": { ... } } block plus the // comment lines above it.
            $pattern = '(?m)(?:^[ \t]*//[^\r\n]*\r?\n)*^\s*"languages"\s*:\s*\{\s*"Pascal"\s*:\s*\{\s*"language_servers"\s*:\s*\[[^\]]*\]\s*\}\s*\}\s*,?'
            $new = [regex]::Replace($raw, $pattern, {
                param($m)
                if ($m.Value -match "pascal-ctags-lsp") { "" } else { $m.Value }
            })
            if ($new -ne $raw -and $new -notmatch "pascal-ctags-lsp") {
                try {
                    $null = $new | ConvertFrom-Json   # PowerShell 7.2+ tolerates // comments and trailing commas
                    Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.uninstall.bak" -Force
                    [System.IO.File]::WriteAllText($settingsPath, $new, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "updated $settingsPath (backup: $settingsPath.uninstall.bak)"
                } catch {
                    Write-Host "WARN: cleaned settings would not parse as JSON - left settings.json unchanged."
                    Write-Host "      Remove the Pascal block manually (search for pascal-ctags-lsp)."
                }
            } else {
                Write-Host "Pascal language_servers block not matched - remove it manually:"
                Write-Host '      "languages": { "Pascal": { "language_servers": ["pascal-ctags-lsp", "!omnipascal"] } },'
            }
        }
    }
} else {
    Write-Host ""
    Write-Host "settings.json untouched. If you also want to drop the Pascal language_servers entry,"
    Write-Host "re-run with -RemoveSettings (or edit manually: search for pascal-ctags-lsp)."
}

Write-Host ""
Write-Host "Done. Restart Zed if it was running."
'@
Set-Content -LiteralPath (Join-Path $distDir "uninstall.ps1") -Value ($uninstallPs1 -replace "__EXT_ID__", $extId) -Encoding UTF8

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
