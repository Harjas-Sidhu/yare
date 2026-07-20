#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RequiredCommands = @(
    'Invoke-WebRequest',
    'Get-FileHash',
    'Expand-Archive',
    'New-Item',
    'Move-Item',
    'Remove-Item',
    'Test-Path',
    'Join-Path',
    'Get-Content',
    'Sort-Object',
    'Get-Random'
)

$MissingCommands = @($RequiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($MissingCommands.Count -gt 0) {
    Write-Host "Error: the following required cmdlets are not available:"
    $MissingCommands | ForEach-Object { Write-Host "  - $_" }
    Write-Host "These ship with Windows PowerShell 5.1+ or PowerShell 7+ (pwsh)."
    Write-Host "Please re-run this script with a supported PowerShell version."
    exit 1
}

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-Host "Error: PowerShell 5.1 or later is required (found $($PSVersionTable.PSVersion))."
    exit 1
}

$ZigMirror         = "https://ziglang.org/download"
$ZigMirrorListUrl  = "https://ziglang.org/download/community-mirrors.txt"
$ZigRelease        = "0.16.0"

$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
switch ($arch) {
    'X64'   { $ZigArch = 'x86_64' }
    'Arm64' { $ZigArch = 'aarch64' }
    default {
        Write-Host "Error: $arch is an untested platform."
        Write-Host "Supported and tested architectures: aarch64, x86_64."
        Write-Host "To proceed anyway, please manually install Zig from: $ZigMirror"
        exit 1
    }
}

$ZigOs        = "windows"
$ZigExtension = ".zip"
$ZigBinExt    = ".exe"

# NB: Bumping ZigRelease requires adding a new hash per arch below.
# This is deliberate, Zig makes real breaking changes across versions,
# so a version bump should be a conscious, reviewable act (its own PR).

# Check the docs/experiments/q1-bootstraping-scripts.md to know the rationale behind
# hardcoded hashes present.
$ExpectedHashes = @{
    "x86_64"  = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"
    "aarch64" = "aee38316ee4111717900f45dd3130145c39289e105541d737eb8c5ed653c78ef"
}
$ExpectedHash = $ExpectedHashes[$ZigArch]
if (-not $ExpectedHash) {
    Write-Host "Something went wrong! Reached unreachable code."
    exit 1
}

$ZigArchiveName = "zig-$ZigArch-$ZigOs-$ZigRelease$ZigExtension"
$ZigArchive     = Join-Path "." "zig\cache\$ZigArchiveName"
$ZigDirectory   = [System.IO.Path]::GetFileNameWithoutExtension($ZigArchiveName)

function Test-FileHashMatch {
    param([string]$FilePath, [string]$ExpectedHash)
    $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    return $actual.ToLowerInvariant() -eq $ExpectedHash.ToLowerInvariant()
}

function Get-RemoteFile {
    param([string]$Url, [string]$OutputPath)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

function Get-MirrorList {
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        if (-not (Get-RemoteFile -Url $ZigMirrorListUrl -OutputPath $tempFile)) {
            return @()
        }
        $lines = Get-Content -Path $tempFile | Where-Object { $_.Trim() -ne "" }
        return @($lines | Sort-Object { Get-Random })
    } finally {
        Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
    }
}

function Invoke-DownloadWithFallback {
    param([string[]]$Candidates, [string]$OutputPath)

    $all = @($Candidates) + @($ZigMirror) | Where-Object { $_.Trim() -ne "" }

    foreach ($baseUrl in $all) {
        $candidateUrl = "$($baseUrl.TrimEnd('/'))/$ZigRelease/$ZigArchiveName"
        Write-Host "Trying $candidateUrl ..."

        if (Get-RemoteFile -Url $candidateUrl -OutputPath $OutputPath) {
            if (Test-FileHashMatch -FilePath $OutputPath -ExpectedHash $ExpectedHash) {
                return $true
            }
            Write-Host "Checksum mismatch from this source, trying next ..."
            Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
        } else {
            Write-Host "Download failed from this source, trying next ..."
            Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
        }
    }
    return $false
}

$SkipDownload = $false

if (Test-Path -Path $ZigArchive -PathType Leaf) {
    Write-Host "Found existing archive: $ZigArchive"
    Write-Host "Verifying hash..."

    if (Test-FileHashMatch -FilePath $ZigArchive -ExpectedHash $ExpectedHash) {
        Write-Host "Cached archive is valid. Skipping download."
        $SkipDownload = $true
    } else {
        Write-Host "Cached archive is corrupted (hash mismatch). Redownloading..."
        Remove-Item -Path $ZigArchive -ErrorAction SilentlyContinue
    }
}

if (-not $SkipDownload) {
    Write-Host "Downloading Zig $ZigRelease for $ZigOs-$ZigArch..."
    New-Item -ItemType Directory -Path "./zig/cache" -Force | Out-Null

    Write-Host "Checking community mirrors..."
    $mirrors = Get-MirrorList
    if ($mirrors.Count -eq 0) {
        Write-Host "No mirror list available, using $ZigMirror directly."
    }

    if (-not (Invoke-DownloadWithFallback -Candidates $mirrors -OutputPath $ZigArchive)) {
        Write-Host "Error: Could not download and verify Zig from any source."
        exit 1
    }
}

Write-Host "Extracting $ZigArchive..."
Expand-Archive -Path $ZigArchive -DestinationPath "./zig/cache" -Force

Remove-Item -Path "zig/doc" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "zig/lib" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "zig/zig$ZigBinExt" -Force -ErrorAction SilentlyContinue

$extractedDir = Join-Path "./zig/cache" $ZigDirectory
Move-Item -Path (Join-Path $extractedDir "LICENSE")    -Destination "zig/" -Force
Move-Item -Path (Join-Path $extractedDir "README.md")  -Destination "zig/" -Force
Move-Item -Path (Join-Path $extractedDir "doc")         -Destination "zig/" -Force
Move-Item -Path (Join-Path $extractedDir "lib")         -Destination "zig/" -Force
Move-Item -Path (Join-Path $extractedDir "zig$ZigBinExt") -Destination "zig/" -Force

# We expect to have now moved all files/dirs out of the extracted directory.
# No -Force / -ErrorAction SilentlyContinue here on purpose: if a future Zig
# release ships extra files we're not explicitly moving, this should error
# out loudly instead of silently deleting them.
Remove-Item -Path $extractedDir

$ZigBin = Join-Path (Get-Location) "zig\zig$ZigBinExt"
Write-Host "Zig $ZigRelease ready: $ZigBin"
