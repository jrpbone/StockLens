[CmdletBinding()]
param(
    [Parameter()]
    [string]$Device,

    [Parameter()]
    [switch]$SkipPubGet,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArguments
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$previousDirectory = Get-Location

function Test-SymbolicLinkSupport {
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
    if (Test-SymbolicLinkSupport) {
        return
    }

    Write-Host @'
Flutter plugins require Windows symbolic-link support.
Enable Developer Mode under Settings > System > Advanced > For developers.
'@ -ForegroundColor Yellow

    $openSettings = Read-Host 'Open the Windows Developer Mode settings now? [Y/n]'
    if (-not [string]::IsNullOrWhiteSpace($openSettings) -and $openSettings -notmatch '^(y|yes)$') {
        throw 'Developer Mode is required before StockLens can run with Flutter plugins.'
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
    }
}

try {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter was not found on PATH. Install Flutter and restart PowerShell before running StockLens.'
    }

    $pubspecPath = Join-Path -Path $projectDirectory -ChildPath 'pubspec.yaml'
    if (-not (Test-Path -LiteralPath $pubspecPath)) {
        throw "StockLens pubspec.yaml was not found in '$projectDirectory'."
    }

    Set-Location -LiteralPath $projectDirectory

    Confirm-SymbolicLinkSupport

    if (-not $SkipPubGet) {
        Write-Host 'Restoring Flutter packages...' -ForegroundColor Cyan
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get failed with exit code $LASTEXITCODE."
        }
    }

    $runArguments = @('run')
    if (-not [string]::IsNullOrWhiteSpace($Device)) {
        $runArguments += @('--device-id', $Device)
    }
    if ($FlutterArguments) {
        $runArguments += $FlutterArguments
    }

    Write-Host 'Starting StockLens...' -ForegroundColor Green
    & flutter @runArguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed with exit code $LASTEXITCODE."
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Set-Location -LiteralPath $previousDirectory
}
