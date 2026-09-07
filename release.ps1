# release.ps1 — one command: build package -> tag -> push -> create Release + upload zip
# on BOTH Gitea (git.1847bell.xyz, source of truth) and GitHub (push-mirror).
#
# Usage:
#   pwsh ./release.ps1 v0.1.0-fix3
#   pwsh ./release.ps1 v0.1.0-fix3 -SkipWasmBuild     # reuse existing wasm
#   pwsh ./release.ps1 v0.1.0-fix3 -DryRun            # show what would run, do nothing
#
# Tokens come from .release-env in the repo root (gitignored):
#   GITEA_TOKEN=<token>      Gitea personal access token (repo write)
#   GIT_TOKEN=<token>        GitHub fine-grained PAT (Contents: read/write, this repo only)

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,                 # tag name, e.g. v0.1.0-fix3
    [switch]$SkipWasmBuild,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot

# --- 0. Load tokens from .release-env (KEY=VALUE lines) ---
$envFile = Join-Path $repoRoot ".release-env"
if (-not (Test-Path $envFile)) { throw ".release-env not found in $repoRoot (GITEA_TOKEN=... / GIT_TOKEN=...)" }
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$' -and -not $line.TrimStart().StartsWith("#")) {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
    }
}
$giteaToken = [Environment]::GetEnvironmentVariable("GITEA_TOKEN", "Process")
$gitToken   = [Environment]::GetEnvironmentVariable("GIT_TOKEN",   "Process")
if (-not $giteaToken) { throw "GITEA_TOKEN missing in .release-env" }
if (-not $gitToken)   { throw "GIT_TOKEN missing in .release-env" }

$giteaHost   = "git.1847bell.xyz"
$owner       = "1847bell"
$repo        = "zed-ctags-DelphiModify"
$releaseName = "$repo $Version"
$zipPath     = Join-Path $repoRoot "dist\ctags-zed-ctags-DelphiModify.zip"
$zipName     = Split-Path $zipPath -Leaf

# read the server binary's own build version (baked at Go build time via -X main.version)
$serverVersion = "(unknown)"
$distExe = Join-Path $repoRoot "dist\ctags\server\ctags-lsp.exe"
if (-not $SkipWasmBuild -or (Test-Path $distExe)) {
    $v = & $distExe --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) { $serverVersion = ($v -join " ") }
}

# --- 1. Build + assemble package (delegates to package.ps1) ---
if ($DryRun) {
    Write-Host "[dry-run] would run: package.ps1 -SkipWasmBuild:$SkipWasmBuild"
} else {
    $pkgArgs = @()
    if ($SkipWasmBuild) { $pkgArgs += "-SkipWasmBuild" }
    & (Join-Path $repoRoot "package.ps1") @pkgArgs
    if ($LASTEXITCODE -ne 0) { throw "package.ps1 failed" }
    if (-not (Test-Path $zipPath)) { throw "zip missing: $zipPath" }
}

# --- 2. Tag + push (Gitea is the remote; GitHub gets the tag via push-mirror) ---
if (git -C $repoRoot rev-parse -q --verify "refs/tags/$Version" 2>$null) {
    throw "tag $Version already exists locally — pick a new version"
}
if ($DryRun) {
    Write-Host "[dry-run] would run: git tag $Version; git push fork $Version"
} else {
    git -C $repoRoot tag $Version
    if ($LASTEXITCODE -ne 0) { throw "git tag failed" }
    git -C $repoRoot push fork $Version
    if ($LASTEXITCODE -ne 0) { throw "git push failed — delete the local tag with: git tag -d $Version" }
}

# --- 3. Create Release + upload zip asset ---
# curl.exe (Schannel, ships with Windows) does the multipart uploads;
# Invoke-RestMethod handles the JSON create calls.
function New-Release($Platform, $CreateUri, $CheckUri, $Headers) {
    Write-Host ""
    Write-Host "== $Platform =="

    # idempotency: reuse the existing release for this tag if present
    $release = $null
    try {
        $release = Invoke-RestMethod -Method Get -Uri $CheckUri -Headers $Headers
        Write-Host "release for $Version already exists — attaching asset to it"
    } catch { }

    if (-not $release) {
        if ($DryRun) {
            Write-Host "[dry-run] would POST $CreateUri (tag $Version)"
            Write-Host "[dry-run] would upload $zipName"
            return
        }
        $body = @{
            tag_name   = $Version
            name       = $releaseName
            body       = "ctags-lsp server build: $serverVersion`n`nContains: extension.toml + extension.wasm + server\ctags-lsp.exe + install.ps1"
            draft      = $false
            prerelease = $false
        } | ConvertTo-Json
        $release = Invoke-RestMethod -Method Post -Uri $CreateUri -Headers $Headers -Body $body -ContentType "application/json"
        Write-Host "created release $Version (server build: $serverVersion)"
    }

    if ($DryRun) { return }

    # platform-specific upload URL
    if ($Platform -eq "Gitea") {
        $uploadUri = "https://$giteaHost/api/v1/repos/$owner/$repo/releases/$($release.id)/assets?name=$zipName"
        $uploadHeaders = @{ Authorization = "token $giteaToken" }
    } else {
        $uploadUri = "https://uploads.github.com/repos/$owner/$repo/releases/$($release.id)/assets?name=$zipName"
        $uploadHeaders = @{ Authorization = "Bearer $gitToken"; Accept = "application/vnd.github+json"; "User-Agent" = "release.ps1" }
    }

    Write-Host "uploading $zipName ..."
    # build header args explicitly (avoids quoting pitfalls)
    $hdrArgs = @()
    foreach ($k in $uploadHeaders.Keys) { $hdrArgs += "-H"; $hdrArgs += "$k`: $($uploadHeaders[$k])" }

    & curl.exe -sS -f -X POST @hdrArgs -H "Content-Type: application/zip" --data-binary "@$zipPath" "$uploadUri" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Platform asset upload failed (curl exit $LASTEXITCODE)" }
    Write-Host "$Platform done."
}

New-Release -Platform "Gitea" `
    -CreateUri "https://$giteaHost/api/v1/repos/$owner/$repo/releases" `
    -CheckUri "https://$giteaHost/api/v1/repos/$owner/$repo/releases/tags/$Version" `
    -Headers @{ Authorization = "token $giteaToken" }

New-Release -Platform "GitHub" `
    -CreateUri "https://api.github.com/repos/$owner/$repo/releases" `
    -CheckUri "https://api.github.com/repos/$owner/$repo/releases/tags/$Version" `
    -Headers @{ Authorization = "Bearer $gitToken"; Accept = "application/vnd.github+json"; "User-Agent" = "release.ps1" }

Write-Host ""
Write-Host "All done: $Version released on Gitea + GitHub, asset $zipName uploaded."
