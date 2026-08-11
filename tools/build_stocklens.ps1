[CmdletBinding()]
param(
    [Parameter()] [string]$AppName,
    [Parameter()] [string]$ApplicationId,
    [Parameter()] [string]$VersionName,
    [Parameter()] [int]$BuildNumber,
    [Parameter()] [ValidateSet('apk', 'appbundle')] [string]$Format,
    [Parameter()] [ValidateSet('debug', 'profile', 'release')] [string]$Mode,
    [Parameter()] [string]$OutputDirectory = 'dist',
    [Parameter()] [switch]$Clean,
    [Parameter()] [switch]$SkipPubGet,
    [Parameter()] [switch]$SkipChecks,
    [Parameter()] [switch]$Obfuscate,
    [Parameter()] [switch]$SplitPerAbi,
    [Parameter()] [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$previousDirectory = (Get-Location).Path
$manifestPath = Join-Path $projectDirectory 'android/app/src/main/AndroidManifest.xml'
$gradlePath = Join-Path $projectDirectory 'android/app/build.gradle.kts'
$pubspecPath = Join-Path $projectDirectory 'pubspec.yaml'
$keyPropertiesPath = Join-Path $projectDirectory 'android/key.properties'
$originalManifest = $null
$originalGradle = $null
$metadataTemporarilyApplied = $false

function Read-DefaultValue {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [string]$DefaultValue
    )
    $answer = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultValue }
    return $answer.Trim()
}

function Read-Choice {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [string[]]$Choices,
        [Parameter(Mandatory)] [string]$DefaultValue
    )
    while ($true) {
        $answer = Read-DefaultValue -Prompt "$Prompt ($($Choices -join '/'))" -DefaultValue $DefaultValue
        $match = $Choices | Where-Object { $_ -ieq $answer } | Select-Object -First 1
        if ($match) { return $match.ToLowerInvariant() }
        Write-Host "Choose one of: $($Choices -join ', ')." -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [bool]$DefaultValue
    )
    $defaultText = if ($DefaultValue) { 'Y' } else { 'N' }
    while ($true) {
        $answer = Read-Host "$Prompt [Y/N, default: $defaultText]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultValue }
        if ($answer -match '^(y|yes)$') { return $true }
        if ($answer -match '^(n|no)$') { return $false }
        Write-Host 'Enter Y or N.' -ForegroundColor Yellow
    }
}

function Read-PositiveInteger {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [int]$DefaultValue
    )
    while ($true) {
        $answer = Read-DefaultValue -Prompt $Prompt -DefaultValue $DefaultValue.ToString()
        $parsed = 0
        if ([int]::TryParse($answer, [ref]$parsed) -and $parsed -gt 0) { return $parsed }
        Write-Host 'Enter a positive whole number.' -ForegroundColor Yellow
    }
}

function Invoke-FlutterStep {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string[]]$Arguments
    )
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host "> flutter $($Arguments -join ' ')" -ForegroundColor DarkGray
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Title failed with exit code $LASTEXITCODE."
    }
}

function Test-SymbolicLinkSupport {
    if ($env:OS -ne 'Windows_NT') { return $true }
    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) "stocklens-symlink-test-$PID"
    $targetPath = Join-Path $testDirectory 'target.txt'
    $linkPath = Join-Path $testDirectory 'link.txt'
    $scriptPath = Join-Path $testDirectory 'test_symlink.dart'
    try {
        $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
        if (-not $flutterCommand) { return $false }
        $dartExecutable = Join-Path (Split-Path -Parent $flutterCommand.Source) 'cache\dart-sdk\bin\dart.exe'
        if (-not (Test-Path -LiteralPath $dartExecutable)) { return $false }
        New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
        [IO.File]::WriteAllText($scriptPath, @'
import 'dart:io';
void main(List<String> args) {
  File(args[0]).writeAsStringSync('StockLens symlink test');
  Link(args[1]).createSync(args[0]);
}
'@)
        & $dartExecutable $scriptPath $targetPath $linkPath 2>$null
        return $LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $linkPath)
    }
    catch { return $false }
    finally {
        if (Test-Path -LiteralPath $testDirectory) {
            Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Confirm-SymbolicLinkSupport {
    param([Parameter(Mandatory)] [bool]$AllowPrompt)
    if (Test-SymbolicLinkSupport) { return }
    if (-not $AllowPrompt) {
        throw 'Windows Developer Mode or an elevated PowerShell session is required for Flutter plugins.'
    }
    Write-Host 'Flutter plugins require Windows symbolic-link support.' -ForegroundColor Yellow
    if (Read-YesNo -Prompt 'Open Windows Developer Mode settings now?' -DefaultValue $true) {
        Start-Process 'ms-settings:developers'
    }
    while ($true) {
        Read-Host 'Enable Developer Mode, then press Enter to retry' | Out-Null
        if (Test-SymbolicLinkSupport) { return }
        if (-not (Read-YesNo -Prompt 'Retry?' -DefaultValue $true)) {
            throw 'Symbolic-link support is still unavailable.'
        }
    }
}

try {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter was not found on PATH.'
    }
    foreach ($requiredPath in @($manifestPath, $gradlePath, $pubspecPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required project file was not found: $requiredPath"
        }
    }

    $manifestContent = [IO.File]::ReadAllText($manifestPath)
    $gradleContent = [IO.File]::ReadAllText($gradlePath)
    $pubspecContent = [IO.File]::ReadAllText($pubspecPath)
    $nameMatch = [regex]::Match($manifestContent, 'android:label="([^"]+)"')
    $idMatch = [regex]::Match($gradleContent, 'applicationId\s*=\s*"([^"]+)"')
    $versionMatch = [regex]::Match($pubspecContent, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
    if (-not $nameMatch.Success -or -not $idMatch.Success -or -not $versionMatch.Success) {
        throw 'Current Android application metadata could not be read.'
    }

    if ([string]::IsNullOrWhiteSpace($AppName)) { $AppName = $nameMatch.Groups[1].Value }
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { $ApplicationId = $idMatch.Groups[1].Value }
    if ([string]::IsNullOrWhiteSpace($VersionName)) { $VersionName = $versionMatch.Groups[1].Value }
    if ($BuildNumber -le 0) { $BuildNumber = [int]$versionMatch.Groups[2].Value }
    if ([string]::IsNullOrWhiteSpace($Format)) { $Format = 'apk' }
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        $Mode = if (Test-Path -LiteralPath $keyPropertiesPath) { 'release' } else { 'debug' }
    }

    $shouldClean = $Clean.IsPresent
    $shouldGetPackages = -not $SkipPubGet.IsPresent
    $shouldRunChecks = -not $SkipChecks.IsPresent
    $shouldObfuscate = $Obfuscate.IsPresent
    $shouldSplitPerAbi = $Format -eq 'apk' -and $SplitPerAbi.IsPresent

    if (-not $NonInteractive) {
        $AppName = Read-DefaultValue -Prompt 'Application display name' -DefaultValue $AppName
        $ApplicationId = Read-DefaultValue -Prompt 'Android application ID' -DefaultValue $ApplicationId
        $Format = Read-Choice -Prompt 'Android package format' -Choices @('apk', 'appbundle') -DefaultValue $Format
        $VersionName = Read-DefaultValue -Prompt 'Version name' -DefaultValue $VersionName
        $BuildNumber = Read-PositiveInteger -Prompt 'Build number' -DefaultValue $BuildNumber
        $Mode = Read-Choice -Prompt 'Build mode' -Choices @('debug', 'profile', 'release') -DefaultValue $Mode
        $OutputDirectory = Read-DefaultValue -Prompt 'Artifact output directory' -DefaultValue $OutputDirectory
        $shouldClean = Read-YesNo -Prompt 'Run flutter clean first?' -DefaultValue $shouldClean
        $shouldGetPackages = Read-YesNo -Prompt 'Restore packages?' -DefaultValue $shouldGetPackages
        $shouldRunChecks = Read-YesNo -Prompt 'Run analysis and tests?' -DefaultValue $true
        if ($Mode -eq 'release') {
            $shouldObfuscate = Read-YesNo -Prompt 'Obfuscate Dart code?' -DefaultValue $shouldObfuscate
        }
        if ($Format -eq 'apk') {
            $shouldSplitPerAbi = Read-YesNo -Prompt 'Create per-ABI APKs?' -DefaultValue $shouldSplitPerAbi
        }
    }

    if ($ApplicationId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
        throw "Invalid Android application ID: $ApplicationId"
    }
    if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid version name: $VersionName"
    }
    if ($Mode -eq 'release' -and -not (Test-Path -LiteralPath $keyPropertiesPath)) {
        throw 'Release signing is not configured. Run tools/setup_android_signing.ps1, then retry.'
    }
    if ($shouldObfuscate -and $Mode -ne 'release') {
        throw 'Dart obfuscation is supported only for release builds.'
    }
    if ($Format -eq 'appbundle') { $shouldSplitPerAbi = $false }

    Write-Host "`nStockLens Android build" -ForegroundColor Green
    Write-Host '----------------------------------------'
    Write-Host "Application:    $AppName"
    Write-Host "Application ID: $ApplicationId"
    Write-Host "Artifact:       $Format"
    Write-Host "Version:        $VersionName+$BuildNumber"
    Write-Host "Mode:           $Mode"
    Write-Host "Output:         $OutputDirectory"
    if (-not $NonInteractive -and
        -not (Read-YesNo -Prompt 'Proceed?' -DefaultValue $true)) {
        Write-Host 'Build cancelled.' -ForegroundColor Yellow
        exit 0
    }

    Confirm-SymbolicLinkSupport -AllowPrompt (-not $NonInteractive)
    Set-Location -LiteralPath $projectDirectory
    if ($shouldClean) { Invoke-FlutterStep -Title 'Cleaning build outputs...' -Arguments @('clean') }
    if ($shouldGetPackages) { Invoke-FlutterStep -Title 'Restoring packages...' -Arguments @('pub', 'get') }
    if ($shouldRunChecks) {
        Invoke-FlutterStep -Title 'Running static analysis...' -Arguments @('analyze')
        Invoke-FlutterStep -Title 'Running automated tests...' -Arguments @('test')
    }

    $originalManifest = $manifestContent
    $originalGradle = $gradleContent
    $escapedName = [Security.SecurityElement]::Escape($AppName)
    $temporaryManifest = [regex]::Replace(
        $manifestContent,
        'android:label="[^"]+"',
        "android:label=`"$escapedName`"",
        1
    )
    $temporaryGradle = [regex]::Replace(
        $gradleContent,
        'applicationId\s*=\s*"[^"]+"',
        "applicationId = `"$ApplicationId`"",
        1
    )
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($manifestPath, $temporaryManifest, $utf8)
    [IO.File]::WriteAllText($gradlePath, $temporaryGradle, $utf8)
    $metadataTemporarilyApplied = $true

    $symbolDirectory = Join-Path $projectDirectory "build/symbols/$VersionName+$BuildNumber/android"
    $arguments = @('build', $Format, "--$Mode", '--build-name', $VersionName, '--build-number', $BuildNumber.ToString())
    if ($shouldSplitPerAbi) { $arguments += '--split-per-abi' }
    if ($shouldObfuscate) {
        New-Item -ItemType Directory -Path $symbolDirectory -Force | Out-Null
        $arguments += @('--obfuscate', "--split-debug-info=$symbolDirectory")
    }
    Invoke-FlutterStep -Title 'Building StockLens for Android...' -Arguments $arguments

    if ($Format -eq 'appbundle') {
        $artifacts = @(Join-Path $projectDirectory "build/app/outputs/bundle/$Mode/app-$Mode.aab")
    }
    elseif ($shouldSplitPerAbi) {
        $apkDirectory = Join-Path $projectDirectory 'build/app/outputs/flutter-apk'
        $artifacts = @(
            Join-Path $apkDirectory "app-armeabi-v7a-$Mode.apk"
            Join-Path $apkDirectory "app-arm64-v8a-$Mode.apk"
            Join-Path $apkDirectory "app-x86_64-$Mode.apk"
        )
    }
    else {
        $artifacts = @(Join-Path $projectDirectory "build/app/outputs/flutter-apk/app-$Mode.apk")
    }
    foreach ($artifact in $artifacts) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
            throw "Expected artifact was not found: $artifact"
        }
    }

    $outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
        [IO.Path]::GetFullPath($OutputDirectory)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $projectDirectory $OutputDirectory))
    }
    $safeName = ($AppName -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'StockLens' }
    $releaseDirectory = Join-Path $outputRoot "$safeName-v$VersionName+$BuildNumber-$Mode-android"
    if (Test-Path -LiteralPath $releaseDirectory) {
        $releaseDirectory += "-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

    $records = @()
    foreach ($artifact in $artifacts) {
        $extension = [IO.Path]::GetExtension($artifact)
        $architecture = if ($artifact -match 'app-(armeabi-v7a|arm64-v8a|x86_64)-') { "-$($Matches[1])" } else { '' }
        $fileName = "$safeName-v$VersionName+$BuildNumber-$Mode$architecture$extension"
        $destination = Join-Path $releaseDirectory $fileName
        Copy-Item -LiteralPath $artifact -Destination $destination
        $records += [ordered]@{
            file = $fileName
            bytes = (Get-Item -LiteralPath $destination).Length
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        }
    }

    [ordered]@{
        applicationName = $AppName
        applicationId = $ApplicationId
        versionName = $VersionName
        buildNumber = $BuildNumber
        format = $Format
        mode = $Mode
        releaseSigned = $Mode -eq 'release'
        obfuscated = $shouldObfuscate
        splitPerAbi = $shouldSplitPerAbi
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        artifacts = $records
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDirectory 'build-manifest.json') -Encoding utf8

    Write-Host "`nBuild completed successfully." -ForegroundColor Green
    Write-Host "Artifacts: $releaseDirectory"
    foreach ($record in $records) {
        Write-Host "  $($record.file)"
        Write-Host "    SHA256: $($record.sha256)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($metadataTemporarilyApplied) {
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($manifestPath, $originalManifest, $utf8)
        [IO.File]::WriteAllText($gradlePath, $originalGradle, $utf8)
    }
    Set-Location -LiteralPath $previousDirectory
}
