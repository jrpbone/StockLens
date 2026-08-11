[CmdletBinding()]
param(
    [Parameter()]
    [string]$AppName,

    [Parameter()]
    [string]$ApplicationId,

    [Parameter()]
    [string]$VersionName,

    [Parameter()]
    [int]$BuildNumber,

    [Parameter()]
    [ValidateSet('apk', 'appbundle')]
    [string]$Format,

    [Parameter()]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode,

    [Parameter()]
    [string]$OutputDirectory = 'dist',

    [Parameter()]
    [switch]$Clean,

    [Parameter()]
    [switch]$SkipPubGet,

    [Parameter()]
    [switch]$SkipChecks,

    [Parameter()]
    [switch]$Obfuscate,

    [Parameter()]
    [switch]$SplitPerAbi,

    [Parameter()]
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot
$previousDirectory = (Get-Location).Path
$manifestPath = Join-Path $projectDirectory 'android\app\src\main\AndroidManifest.xml'
$gradlePath = Join-Path $projectDirectory 'android\app\build.gradle.kts'
$pubspecPath = Join-Path $projectDirectory 'pubspec.yaml'
$originalManifest = $null
$originalGradle = $null
$metadataTemporarilyApplied = $false

function Read-DefaultValue {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [string]$DefaultValue
    )

    $answer = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $DefaultValue
    }
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
        $matchedChoice = $Choices | Where-Object { $_ -ieq $answer } | Select-Object -First 1
        if ($matchedChoice) {
            return $matchedChoice.ToLowerInvariant()
        }
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
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $DefaultValue
        }
        if ($answer -match '^(y|yes)$') {
            return $true
        }
        if ($answer -match '^(n|no)$') {
            return $false
        }
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
        $parsedValue = 0
        if ([int]::TryParse($answer, [ref]$parsedValue) -and $parsedValue -gt 0) {
            return $parsedValue
        }
        Write-Host 'Enter a positive whole number.' -ForegroundColor Yellow
    }
}

function Test-SymbolicLinkSupport {
    if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
        return $true
    }

    $testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "stocklens-symlink-test-$PID"
    $targetPath = Join-Path $testDirectory 'target.txt'
    $linkPath = Join-Path $testDirectory 'link.txt'
    $dartScriptPath = Join-Path $testDirectory 'test_symlink.dart'
    try {
        $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
        if (-not $flutterCommand) {
            return $false
        }
        $flutterBinDirectory = Split-Path -Parent $flutterCommand.Source
        $dartExecutable = Join-Path $flutterBinDirectory 'cache\dart-sdk\bin\dart.exe'
        if (-not (Test-Path -LiteralPath $dartExecutable)) {
            return $false
        }
        New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
        $dartScript = @'
import 'dart:io';

void main(List<String> arguments) {
  final target = File(arguments[0]);
  final link = Link(arguments[1]);
  target.writeAsStringSync('StockLens symlink capability test');
  link.createSync(target.path);
  if (!link.existsSync()) {
    exitCode = 1;
  }
}
'@
        [System.IO.File]::WriteAllText($dartScriptPath, $dartScript)
        $null = & $dartExecutable $dartScriptPath $targetPath $linkPath 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $testDirectory) {
            Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Confirm-SymbolicLinkSupport {
    param(
        [Parameter(Mandatory)] [bool]$AllowPrompt
    )

    if (Test-SymbolicLinkSupport) {
        return
    }

    $instructions = @'
Flutter plugins require permission to create local Windows symbolic links,
even when only producing an APK. This is unrelated to a phone connection,
Android debugging, or the APK build mode. Windows calls the setting that grants
this filesystem permission "Developer Mode".

No phone is needed. If you do not want to enable that Windows setting, cancel
and run this script from an Administrator PowerShell window instead.
'@

    if (-not $AllowPrompt) {
        throw "$instructions`nOpen the settings page with: start ms-settings:developers"
    }

    Write-Host "`n$instructions" -ForegroundColor Yellow
    if (-not (Read-YesNo -Prompt 'Open the Windows Developer Mode settings now?' -DefaultValue $true)) {
        throw 'Developer Mode is required before StockLens can build with Flutter plugins.'
    }

    Start-Process 'ms-settings:developers'
    while ($true) {
        Read-Host 'Enable Developer Mode in Settings, then press Enter to retry' | Out-Null
        if (Test-SymbolicLinkSupport) {
            Write-Host 'Symbolic-link support is enabled.' -ForegroundColor Green
            return
        }
        Write-Host 'Dart still cannot create a symbolic link.' -ForegroundColor Yellow
        Write-Host 'If Developer Mode was just enabled, close and reopen PowerShell before retrying.' -ForegroundColor Yellow
        if (-not (Read-YesNo -Prompt 'Retry after checking Developer Mode?' -DefaultValue $true)) {
            throw 'Developer Mode is still disabled. The build cannot continue.'
        }
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

try {
    Set-Location -LiteralPath $projectDirectory

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter was not found on PATH. Install Flutter and restart PowerShell.'
    }
    foreach ($requiredPath in @($pubspecPath, $manifestPath, $gradlePath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required project file was not found: $requiredPath"
        }
    }

    $pubspecContent = [System.IO.File]::ReadAllText($pubspecPath)
    $manifestContent = [System.IO.File]::ReadAllText($manifestPath)
    $gradleContent = [System.IO.File]::ReadAllText($gradlePath)

    $versionMatch = [regex]::Match($pubspecContent, '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$')
    $labelMatch = [regex]::Match($manifestContent, 'android:label="([^"]+)"')
    $applicationIdMatch = [regex]::Match($gradleContent, 'applicationId\s*=\s*"([^"]+)"')
    if (-not $versionMatch.Success -or -not $labelMatch.Success -or -not $applicationIdMatch.Success) {
        throw 'The current app name, version, build number, or application ID could not be read from the project.'
    }

    $currentVersionName = $versionMatch.Groups[1].Value
    $currentBuildNumber = [int]$versionMatch.Groups[2].Value
    $currentAppName = $labelMatch.Groups[1].Value
    $currentApplicationId = $applicationIdMatch.Groups[1].Value

    if ([string]::IsNullOrWhiteSpace($AppName)) { $AppName = $currentAppName }
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { $ApplicationId = $currentApplicationId }
    if ([string]::IsNullOrWhiteSpace($VersionName)) { $VersionName = $currentVersionName }
    if ($BuildNumber -le 0) { $BuildNumber = $currentBuildNumber }
    if ([string]::IsNullOrWhiteSpace($Format)) { $Format = 'apk' }
    if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'release' }

    $shouldClean = $Clean.IsPresent
    $shouldGetPackages = -not $SkipPubGet.IsPresent
    $shouldRunChecks = -not $SkipChecks.IsPresent
    $shouldObfuscate = $Obfuscate.IsPresent
    $shouldSplitPerAbi = $SplitPerAbi.IsPresent

    if (-not $NonInteractive) {
        Write-Host '========================================' -ForegroundColor Green
        Write-Host '       StockLens Build Assistant' -ForegroundColor Green
        Write-Host '========================================' -ForegroundColor Green
        Write-Host 'Press Enter to accept any displayed default.'

        $AppName = Read-DefaultValue -Prompt 'Application display name' -DefaultValue $AppName
        $ApplicationId = Read-DefaultValue -Prompt 'Android application ID' -DefaultValue $ApplicationId
        $VersionName = Read-DefaultValue -Prompt 'Version name (major.minor.patch)' -DefaultValue $VersionName
        $BuildNumber = Read-PositiveInteger -Prompt 'Build number' -DefaultValue $BuildNumber
        $Format = Read-Choice -Prompt 'Package format' -Choices @('apk', 'appbundle') -DefaultValue $Format
        $Mode = Read-Choice -Prompt 'Build mode' -Choices @('debug', 'profile', 'release') -DefaultValue $Mode
        $OutputDirectory = Read-DefaultValue -Prompt 'Artifact output directory' -DefaultValue $OutputDirectory
        $shouldClean = Read-YesNo -Prompt 'Run flutter clean before building?' -DefaultValue $shouldClean
        $shouldGetPackages = Read-YesNo -Prompt 'Restore packages with flutter pub get?' -DefaultValue $shouldGetPackages
        $shouldRunChecks = Read-YesNo -Prompt 'Run flutter analyze and flutter test?' -DefaultValue $true
        if ($Mode -eq 'release') {
            $shouldObfuscate = Read-YesNo -Prompt 'Obfuscate Dart code and save debug symbols?' -DefaultValue $shouldObfuscate
        } else {
            $shouldObfuscate = $false
        }
        if ($Format -eq 'apk') {
            $shouldSplitPerAbi = Read-YesNo -Prompt 'Create smaller per-ABI APK files?' -DefaultValue $shouldSplitPerAbi
        } else {
            $shouldSplitPerAbi = $false
        }
    }

    if ($AppName -notmatch '\S') {
        throw 'Application display name cannot be empty.'
    }
    if ($ApplicationId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
        throw "Application ID '$ApplicationId' is invalid. Use lowercase dot-separated identifiers such as com.company.stocklens."
    }
    if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version '$VersionName' is invalid. Use major.minor.patch, for example 0.2.0."
    }
    if ($BuildNumber -le 0) {
        throw 'Build number must be a positive integer.'
    }
    if ($shouldObfuscate -and $Mode -ne 'release') {
        throw 'Dart obfuscation is available only for release builds in this assistant.'
    }
    $usesDebugReleaseSigning = $Mode -eq 'release' -and
        $gradleContent -match 'release\s*\{[\s\S]*?signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'

    Write-Host "`nBuild summary" -ForegroundColor Green
    Write-Host '----------------------------------------'
    Write-Host "App name:          $AppName"
    Write-Host "Application ID:    $ApplicationId"
    Write-Host "Version:           $VersionName+$BuildNumber"
    Write-Host "Package:           $Format"
    Write-Host "Mode:              $Mode"
    Write-Host "Output:            $OutputDirectory"
    Write-Host "Clean:             $shouldClean"
    Write-Host "Restore packages:  $shouldGetPackages"
    Write-Host "Analyze and test:  $shouldRunChecks"
    Write-Host "Obfuscate:         $shouldObfuscate"
    Write-Host "Split per ABI:     $shouldSplitPerAbi"
    if ($usesDebugReleaseSigning) {
        Write-Host 'WARNING: Release builds currently use the debug signing key and are not store-ready.' -ForegroundColor Yellow
    }
    if ($ApplicationId -like 'com.example.*') {
        Write-Host 'WARNING: The example application ID should be replaced before publishing.' -ForegroundColor Yellow
    }

    if (-not $NonInteractive) {
        $confirmed = Read-YesNo -Prompt 'Proceed with this build?' -DefaultValue $true
        if (-not $confirmed) {
            Write-Host 'Build cancelled. No project metadata was changed.' -ForegroundColor Yellow
            exit 0
        }
    }

    Confirm-SymbolicLinkSupport -AllowPrompt (-not $NonInteractive)

    if ($shouldClean) {
        Invoke-FlutterStep -Title 'Cleaning previous build outputs...' -Arguments @('clean')
    }
    if ($shouldGetPackages) {
        Invoke-FlutterStep -Title 'Restoring Flutter packages...' -Arguments @('pub', 'get')
    }
    if ($shouldRunChecks) {
        Invoke-FlutterStep -Title 'Running static analysis...' -Arguments @('analyze')
        Invoke-FlutterStep -Title 'Running automated tests...' -Arguments @('test')
    }

    $originalManifest = $manifestContent
    $originalGradle = $gradleContent
    $escapedAppName = [System.Security.SecurityElement]::Escape($AppName)
    $temporaryManifest = [regex]::Replace(
        $manifestContent,
        'android:label="[^"]+"',
        "android:label=`"$escapedAppName`"",
        1
    )
    $temporaryGradle = [regex]::Replace(
        $gradleContent,
        'applicationId\s*=\s*"[^"]+"',
        "applicationId = `"$ApplicationId`"",
        1
    )
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($manifestPath, $temporaryManifest, $utf8WithoutBom)
    [System.IO.File]::WriteAllText($gradlePath, $temporaryGradle, $utf8WithoutBom)
    $metadataTemporarilyApplied = $true

    $symbolDirectory = Join-Path $projectDirectory "build\symbols\$VersionName+$BuildNumber"
    $buildArguments = @('build', $Format, "--$Mode", '--build-name', $VersionName, '--build-number', $BuildNumber.ToString())
    if ($shouldSplitPerAbi) {
        $buildArguments += '--split-per-abi'
    }
    if ($shouldObfuscate) {
        New-Item -ItemType Directory -Path $symbolDirectory -Force | Out-Null
        $buildArguments += @('--obfuscate', "--split-debug-info=$symbolDirectory")
    }
    Invoke-FlutterStep -Title 'Building StockLens...' -Arguments $buildArguments

    if ($Format -eq 'appbundle') {
        $builtArtifacts = @(Join-Path $projectDirectory "build\app\outputs\bundle\$Mode\app-$Mode.aab")
    } elseif ($shouldSplitPerAbi) {
        $apkDirectory = Join-Path $projectDirectory 'build\app\outputs\flutter-apk'
        $builtArtifacts = @(
            Join-Path $apkDirectory "app-armeabi-v7a-$Mode.apk"
            Join-Path $apkDirectory "app-arm64-v8a-$Mode.apk"
            Join-Path $apkDirectory "app-x86_64-$Mode.apk"
        )
    } else {
        $builtArtifacts = @(Join-Path $projectDirectory "build\app\outputs\flutter-apk\app-$Mode.apk")
    }

    foreach ($artifact in $builtArtifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) {
            throw "Expected build artifact was not found: $artifact"
        }
    }

    $outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory
    } else {
        Join-Path $projectDirectory $OutputDirectory
    }
    $safeAppName = ($AppName -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeAppName)) { $safeAppName = 'StockLens' }
    $releaseFolderName = "$safeAppName-v$VersionName+$BuildNumber-$Mode"
    $releaseDirectory = Join-Path $outputRoot $releaseFolderName
    if (Test-Path -LiteralPath $releaseDirectory) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $releaseDirectory = Join-Path $outputRoot "$releaseFolderName-$timestamp"
    }
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

    $artifactRecords = @()
    foreach ($artifact in $builtArtifacts) {
        $extension = [System.IO.Path]::GetExtension($artifact)
        $architecture = ''
        if ($artifact -match 'app-(armeabi-v7a|arm64-v8a|x86_64)-') {
            $architecture = "-$($Matches[1])"
        }
        $destinationName = "$safeAppName-v$VersionName+$BuildNumber-$Mode$architecture$extension"
        $destinationPath = Join-Path $releaseDirectory $destinationName
        Copy-Item -LiteralPath $artifact -Destination $destinationPath
        $hash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        $artifactRecords += [ordered]@{
            file = $destinationName
            bytes = (Get-Item -LiteralPath $destinationPath).Length
            sha256 = $hash
        }
    }

    $buildRecord = [ordered]@{
        applicationName = $AppName
        applicationId = $ApplicationId
        versionName = $VersionName
        buildNumber = $BuildNumber
        format = $Format
        mode = $Mode
        obfuscated = $shouldObfuscate
        splitPerAbi = $shouldSplitPerAbi
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        releaseSigningUsesDebugKey = $usesDebugReleaseSigning
        artifacts = $artifactRecords
    }
    $buildRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDirectory 'build-manifest.json') -Encoding utf8

    Write-Host "`nBuild completed successfully." -ForegroundColor Green
    Write-Host "Artifacts: $releaseDirectory"
    foreach ($record in $artifactRecords) {
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
        $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($manifestPath, $originalManifest, $utf8WithoutBom)
        [System.IO.File]::WriteAllText($gradlePath, $originalGradle, $utf8WithoutBom)
    }
    Set-Location -LiteralPath $previousDirectory
}
