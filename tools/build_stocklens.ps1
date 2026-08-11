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
    [ValidateSet('android', 'ios', 'both')]
    [string]$Target,

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
    [ValidateRange(5, 120)]
    [int]$RemoteIosTimeoutMinutes = 45,

    [Parameter()]
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$previousDirectory = (Get-Location).Path
$manifestPath = Join-Path $projectDirectory 'android/app/src/main/AndroidManifest.xml'
$gradlePath = Join-Path $projectDirectory 'android/app/build.gradle.kts'
$iosInfoPlistPath = Join-Path $projectDirectory 'ios/Runner/Info.plist'
$pubspecPath = Join-Path $projectDirectory 'pubspec.yaml'
$originalManifest = $null
$originalGradle = $null
$metadataTemporarilyApplied = $false
$iosWorkflowFile = 'ios-remote-build.yml'
$gitHubApiVersion = '2026-03-10'
$isMacOSHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)

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

function Read-BuildTarget {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('android', 'ios', 'both')]
        [string]$DefaultValue
    )

    $options = @(
        [pscustomobject]@{ Value = 'android'; Label = 'Android'; Description = 'Build an APK or Android App Bundle' }
        [pscustomobject]@{ Value = 'ios'; Label = 'iOS'; Description = 'Build locally on macOS or remotely with GitHub Actions' }
        [pscustomobject]@{ Value = 'both'; Label = 'Both'; Description = 'Build Android locally and iOS locally or through GitHub Actions' }
    )
    $defaultIndex = 0
    for ($index = 0; $index -lt $options.Count; $index++) {
        if ($options[$index].Value -eq $DefaultValue) {
            $defaultIndex = $index
            break
        }
    }

    while ($true) {
        Write-Host "`nSelect a build target" -ForegroundColor Cyan
        Write-Host '----------------------------------------'
        for ($index = 0; $index -lt $options.Count; $index++) {
            $marker = if ($index -eq $defaultIndex) { ' (default)' } else { '' }
            Write-Host "[$($index + 1)] $($options[$index].Label)$marker"
            Write-Host "    $($options[$index].Description)" -ForegroundColor DarkGray
        }

        $answer = Read-Host "Choose 1-$($options.Count) [default: $($defaultIndex + 1)]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $options[$defaultIndex].Value
        }

        $selectedNumber = 0
        if ([int]::TryParse($answer, [ref]$selectedNumber) -and
            $selectedNumber -ge 1 -and
            $selectedNumber -le $options.Count) {
            return $options[$selectedNumber - 1].Value
        }
        Write-Host "Enter a number from 1 to $($options.Count)." -ForegroundColor Yellow
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

function Get-GitHubAccessToken {
    param(
        [Parameter(Mandatory)] [bool]$AllowPrompt
    )

    foreach ($variableName in @('GITHUB_TOKEN', 'GH_TOKEN')) {
        $value = [Environment]::GetEnvironmentVariable($variableName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
    if (-not $AllowPrompt) {
        throw 'Remote iOS builds require GITHUB_TOKEN or GH_TOKEN in non-interactive mode.'
    }

    Write-Host @'

A GitHub fine-grained access token is required to request the macOS build.
Grant this repository Contents: Read and Actions: Read and write.
The token is used only for this run and is not saved.
'@ -ForegroundColor Yellow
    $secureToken = Read-Host 'GitHub token' -AsSecureString
    $token = [System.Net.NetworkCredential]::new('', $secureToken).Password
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'A GitHub token is required for a remote iOS build.'
    }
    return $token
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)] [ValidateSet('Get', 'Post')] [string]$Method,
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [Parameter()] [object]$Body
    )

    $request = @{
        Uri = $Uri
        Method = $Method
        Headers = $Headers
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Depth 8 -Compress
        $request.ContentType = 'application/json'
    }
    try {
        return Invoke-RestMethod @request
    }
    catch {
        throw "GitHub API request failed for '$Uri': $($_.Exception.Message)"
    }
}

function Get-RemoteIosContext {
    param(
        [Parameter(Mandatory)] [bool]$AllowPrompt,
        [Parameter(Mandatory)] [string]$WorkflowFile,
        [Parameter(Mandatory)] [string]$ApiVersion
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is required to identify the GitHub repository for a remote iOS build.'
    }
    $remotes = @(& git remote)
    if ($LASTEXITCODE -ne 0 -or $remotes -notcontains 'origin') {
        throw 'No Git origin is configured. Create a GitHub repository, add it as origin, then commit and push this workflow.'
    }
    $remoteUrl = (& git remote get-url origin | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
        throw 'The Git origin URL could not be read.'
    }
    $remoteUrl = $remoteUrl.Trim()
    if ($remoteUrl -notmatch 'github\.com[/:]([^/]+)/([^/]+)$') {
        throw "The origin remote is not a supported GitHub URL: $remoteUrl"
    }
    $owner = $Matches[1]
    $repository = $Matches[2] -replace '\.git$', ''
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repository)) {
        throw "The GitHub owner and repository could not be read from origin: $remoteUrl"
    }

    $branch = (& git branch --show-current 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        throw 'Remote iOS builds require a checked-out branch rather than a detached HEAD.'
    }
    $branch = $branch.Trim()
    $workingChanges = @(& git status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) {
        throw 'The Git working tree status could not be checked.'
    }
    if ($workingChanges.Count -gt 0) {
        throw 'Commit and push the current changes before requesting iOS. GitHub can only build files that exist in the remote repository.'
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $upstream = (& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Select-Object -First 1)
    $upstreamExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($upstreamExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($upstream)) {
        throw "Branch '$branch' has no upstream. Push it with: git push -u origin $branch"
    }
    $aheadBehind = (& git rev-list --left-right --count "$($upstream.Trim())...HEAD" 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($aheadBehind)) {
        throw 'The local branch could not be compared with its upstream.'
    }
    $counts = $aheadBehind.Trim() -split '\s+'
    if ($counts.Count -lt 2 -or [int]$counts[1] -gt 0) {
        throw "Branch '$branch' contains commits that have not been pushed. Push them before requesting iOS."
    }

    $token = Get-GitHubAccessToken -AllowPrompt $AllowPrompt
    $headers = @{
        Accept = 'application/vnd.github+json'
        Authorization = "Bearer $token"
        'X-GitHub-Api-Version' = $ApiVersion
        'User-Agent' = 'StockLens-Build-Assistant'
    }
    $encodedWorkflow = [Uri]::EscapeDataString($WorkflowFile)
    $workflowUri = "https://api.github.com/repos/$owner/$repository/actions/workflows/$encodedWorkflow"
    $null = Invoke-GitHubApi -Method Get -Uri $workflowUri -Headers $headers

    return [pscustomobject]@{
        Owner = $owner
        Repository = $repository
        Branch = $branch
        Headers = $headers
        WorkflowFile = $WorkflowFile
        ApiBase = "https://api.github.com/repos/$owner/$repository"
    }
}

function Invoke-RemoteIosBuild {
    param(
        [Parameter(Mandatory)] [pscustomobject]$Context,
        [Parameter(Mandatory)] [string]$VersionName,
        [Parameter(Mandatory)] [int]$BuildNumber,
        [Parameter(Mandatory)] [string]$Mode,
        [Parameter(Mandatory)] [string]$SafeAppName,
        [Parameter(Mandatory)] [bool]$Obfuscate,
        [Parameter(Mandatory)] [bool]$RunChecks,
        [Parameter(Mandatory)] [string]$DestinationDirectory,
        [Parameter(Mandatory)] [int]$TimeoutMinutes
    )

    $requestId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $artifactName = "stocklens-ios-$requestId"
    $iosFileName = "$SafeAppName-v$VersionName+$BuildNumber-$Mode-ios-unsigned-app.zip"
    $encodedWorkflow = [Uri]::EscapeDataString($Context.WorkflowFile)
    $dispatchUri = "$($Context.ApiBase)/actions/workflows/$encodedWorkflow/dispatches"
    $dispatchBody = [ordered]@{
        ref = $Context.Branch
        inputs = [ordered]@{
            request_id = $requestId
            version_name = $VersionName
            build_number = $BuildNumber.ToString()
            mode = $Mode
            artifact_name = $SafeAppName
            obfuscate = $Obfuscate.ToString().ToLowerInvariant()
            run_checks = $RunChecks.ToString().ToLowerInvariant()
        }
    }

    Write-Host "`nRequesting remote iOS build on GitHub Actions..." -ForegroundColor Cyan
    $dispatchResponse = Invoke-GitHubApi -Method Post -Uri $dispatchUri -Headers $Context.Headers -Body $dispatchBody
    $runId = $dispatchResponse.workflow_run_id
    if (-not $runId) {
        $expectedTitle = "StockLens iOS $requestId"
        $encodedBranch = [Uri]::EscapeDataString($Context.Branch)
        $runsUri = "$($Context.ApiBase)/actions/workflows/$encodedWorkflow/runs?event=workflow_dispatch&branch=$encodedBranch&per_page=20"
        for ($attempt = 0; $attempt -lt 12 -and -not $runId; $attempt++) {
            Start-Sleep -Seconds 5
            $runs = Invoke-GitHubApi -Method Get -Uri $runsUri -Headers $Context.Headers
            $matchingRun = $runs.workflow_runs | Where-Object { $_.display_title -eq $expectedTitle } | Select-Object -First 1
            if ($matchingRun) { $runId = $matchingRun.id }
        }
    }
    if (-not $runId) {
        throw 'GitHub accepted the workflow request, but its run could not be located.'
    }

    $runUri = "$($Context.ApiBase)/actions/runs/$runId"
    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    $lastStatus = $null
    do {
        $run = Invoke-GitHubApi -Method Get -Uri $runUri -Headers $Context.Headers
        if ($run.status -ne $lastStatus) {
            Write-Host "GitHub iOS build status: $($run.status)"
            if ($run.html_url) { Write-Host "  $($run.html_url)" -ForegroundColor DarkGray }
            $lastStatus = $run.status
        }
        if ($run.status -eq 'completed') { break }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "The GitHub iOS build did not finish within $TimeoutMinutes minutes. Continue monitoring: $($run.html_url)"
        }
        Start-Sleep -Seconds 10
    } while ($true)

    if ($run.conclusion -ne 'success') {
        throw "The GitHub iOS build concluded with '$($run.conclusion)'. Review: $($run.html_url)"
    }

    $artifactsUri = "$($Context.ApiBase)/actions/runs/$runId/artifacts"
    $artifact = $null
    for ($attempt = 0; $attempt -lt 6 -and -not $artifact; $attempt++) {
        $artifacts = Invoke-GitHubApi -Method Get -Uri $artifactsUri -Headers $Context.Headers
        $artifact = $artifacts.artifacts | Where-Object { $_.name -eq $artifactName -and -not $_.expired } | Select-Object -First 1
        if (-not $artifact) { Start-Sleep -Seconds 5 }
    }
    if (-not $artifact) {
        throw "The completed GitHub run did not publish the expected artifact '$artifactName'."
    }

    $downloadPath = Join-Path $DestinationDirectory ".$artifactName.zip"
    try {
        Write-Host 'Downloading remote iOS artifact...' -ForegroundColor Cyan
        $downloadRequest = @{
            Uri = $artifact.archive_download_url
            Headers = $Context.Headers
            OutFile = $downloadPath
            ErrorAction = 'Stop'
        }
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $downloadRequest.UseBasicParsing = $true
        }
        $null = Invoke-WebRequest @downloadRequest
        Expand-Archive -LiteralPath $downloadPath -DestinationPath $DestinationDirectory -Force
    }
    finally {
        if (Test-Path -LiteralPath $downloadPath) {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        }
    }

    $iosPath = Join-Path $DestinationDirectory $iosFileName
    $checksumPath = "$iosPath.sha256"
    if (-not (Test-Path -LiteralPath $iosPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
        throw 'The downloaded iOS artifact is incomplete.'
    }
    $expectedHash = (([System.IO.File]::ReadAllText($checksumPath)).Trim() -split '\s+')[0]
    $actualHash = (Get-FileHash -LiteralPath $iosPath -Algorithm SHA256).Hash
    if ($actualHash -ine $expectedHash) {
        throw 'The downloaded iOS artifact failed SHA-256 verification.'
    }

    return [ordered]@{
        platform = 'ios'
        file = $iosFileName
        bytes = (Get-Item -LiteralPath $iosPath).Length
        sha256 = $actualHash
        codeSigned = $false
        source = 'github-actions'
        workflowRunId = [long]$runId
        workflowRunUrl = $run.html_url
    }
}

try {
    Set-Location -LiteralPath $projectDirectory

    if ([string]::IsNullOrWhiteSpace($Target)) { $Target = 'android' }
    if (-not $NonInteractive) {
        Write-Host '========================================' -ForegroundColor Green
        Write-Host '       StockLens Build Assistant' -ForegroundColor Green
        Write-Host '========================================' -ForegroundColor Green
        Write-Host 'Press Enter to accept any displayed default.'
        $Target = Read-BuildTarget -DefaultValue $Target
    }

    $shouldBuildAndroid = $Target -in @('android', 'both')
    $shouldBuildIos = $Target -in @('ios', 'both')
    $shouldBuildIosLocally = $shouldBuildIos -and $isMacOSHost
    $shouldBuildIosRemotely = $shouldBuildIos -and -not $isMacOSHost
    $usesLocalFlutter = $shouldBuildAndroid -or $shouldBuildIosLocally
    if ($usesLocalFlutter -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter was not found on PATH. Install Flutter and restart PowerShell.'
    }
    $requiredPaths = @($pubspecPath)
    if ($shouldBuildAndroid) {
        $requiredPaths += @($manifestPath, $gradlePath)
    }
    if ($shouldBuildIos) {
        $requiredPaths += $iosInfoPlistPath
    }
    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required project file was not found: $requiredPath"
        }
    }

    $pubspecContent = [System.IO.File]::ReadAllText($pubspecPath)
    $versionMatch = [regex]::Match($pubspecContent, '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$')
    if (-not $versionMatch.Success) {
        throw 'The current version and build number could not be read from pubspec.yaml.'
    }
    $currentVersionName = $versionMatch.Groups[1].Value
    $currentBuildNumber = [int]$versionMatch.Groups[2].Value

    $manifestContent = $null
    $gradleContent = $null
    $currentApplicationId = $null
    $currentAppName = 'StockLens'
    if ($shouldBuildAndroid) {
        $manifestContent = [System.IO.File]::ReadAllText($manifestPath)
        $gradleContent = [System.IO.File]::ReadAllText($gradlePath)
        $labelMatch = [regex]::Match($manifestContent, 'android:label="([^"]+)"')
        $applicationIdMatch = [regex]::Match($gradleContent, 'applicationId\s*=\s*"([^"]+)"')
        if (-not $labelMatch.Success -or -not $applicationIdMatch.Success) {
            throw 'The Android app name or application ID could not be read from the project.'
        }
        $currentAppName = $labelMatch.Groups[1].Value
        $currentApplicationId = $applicationIdMatch.Groups[1].Value
    } elseif ($shouldBuildIos) {
        $iosInfoPlistContent = [System.IO.File]::ReadAllText($iosInfoPlistPath)
        $iosDisplayNameMatch = [regex]::Match(
            $iosInfoPlistContent,
            '<key>CFBundleDisplayName</key>\s*<string>([^<]+)</string>'
        )
        if ($iosDisplayNameMatch.Success) {
            $currentAppName = $iosDisplayNameMatch.Groups[1].Value
        }
    }

    if ([string]::IsNullOrWhiteSpace($AppName)) { $AppName = $currentAppName }
    if ($shouldBuildAndroid -and [string]::IsNullOrWhiteSpace($ApplicationId)) {
        $ApplicationId = $currentApplicationId
    }
    if ([string]::IsNullOrWhiteSpace($VersionName)) { $VersionName = $currentVersionName }
    if ($BuildNumber -le 0) { $BuildNumber = $currentBuildNumber }
    if ([string]::IsNullOrWhiteSpace($Format)) { $Format = 'apk' }
    if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'release' }

    $shouldClean = $Clean.IsPresent
    $shouldGetPackages = -not $SkipPubGet.IsPresent
    $shouldRunChecks = -not $SkipChecks.IsPresent
    $shouldObfuscate = $Obfuscate.IsPresent
    $shouldSplitPerAbi = $shouldBuildAndroid -and $Format -eq 'apk' -and $SplitPerAbi.IsPresent

    if (-not $NonInteractive) {
        if ($shouldBuildAndroid) {
            $AppName = Read-DefaultValue -Prompt 'Application display name' -DefaultValue $AppName
            $ApplicationId = Read-DefaultValue -Prompt 'Android application ID' -DefaultValue $ApplicationId
            $Format = Read-Choice -Prompt 'Android package format' -Choices @('apk', 'appbundle') -DefaultValue $Format
        } else {
            $AppName = Read-DefaultValue -Prompt 'Artifact name' -DefaultValue $AppName
        }
        $VersionName = Read-DefaultValue -Prompt 'Version name (major.minor.patch)' -DefaultValue $VersionName
        $BuildNumber = Read-PositiveInteger -Prompt 'Build number' -DefaultValue $BuildNumber
        $Mode = Read-Choice -Prompt 'Build mode' -Choices @('debug', 'profile', 'release') -DefaultValue $Mode
        $OutputDirectory = Read-DefaultValue -Prompt 'Artifact output directory' -DefaultValue $OutputDirectory
        if ($usesLocalFlutter) {
            $shouldClean = Read-YesNo -Prompt 'Run flutter clean before building?' -DefaultValue $shouldClean
            $shouldGetPackages = Read-YesNo -Prompt 'Restore packages with flutter pub get?' -DefaultValue $shouldGetPackages
        } else {
            $shouldClean = $false
            $shouldGetPackages = $false
        }
        $checksPrompt = if ($shouldBuildIosRemotely -and -not $shouldBuildAndroid) {
            'Run formatting, analysis, and tests on GitHub?'
        } else {
            'Run flutter analyze and flutter test?'
        }
        $shouldRunChecks = Read-YesNo -Prompt $checksPrompt -DefaultValue $true
        if ($Mode -eq 'release') {
            $shouldObfuscate = Read-YesNo -Prompt 'Obfuscate Dart code and save debug symbols?' -DefaultValue $shouldObfuscate
        } else {
            $shouldObfuscate = $false
        }
        if ($shouldBuildAndroid -and $Format -eq 'apk') {
            $shouldSplitPerAbi = Read-YesNo -Prompt 'Create smaller per-ABI APK files?' -DefaultValue $shouldSplitPerAbi
        } else {
            $shouldSplitPerAbi = $false
        }
    }

    if ($AppName -notmatch '\S') {
        throw 'Application display name cannot be empty.'
    }
    if ($shouldBuildAndroid -and $ApplicationId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
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
    if ($shouldBuildIosLocally) {
        if (-not (Get-Command xcodebuild -ErrorAction SilentlyContinue)) {
            throw 'An iOS build was requested, but Xcode was not found. Install Xcode or choose -Target android.'
        }
        if (-not (Get-Command ditto -ErrorAction SilentlyContinue)) {
            throw 'The macOS ditto utility was not found and the iOS application could not be packaged.'
        }
    }
    $usesDebugReleaseSigning = $shouldBuildAndroid -and $Mode -eq 'release' -and
        $gradleContent -match 'release\s*\{[\s\S]*?signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'

    Write-Host "`nBuild summary" -ForegroundColor Green
    Write-Host '----------------------------------------'
    Write-Host "Target:            $Target"
    Write-Host "Artifact name:     $AppName"
    if ($shouldBuildAndroid) {
        Write-Host "Application ID:    $ApplicationId"
        Write-Host "Android package:   $Format"
        Write-Host "Split per ABI:     $shouldSplitPerAbi"
    }
    if ($shouldBuildIos) {
        $iosBuildLocation = if ($shouldBuildIosLocally) { 'Local macOS/Xcode' } else { 'Remote GitHub Actions macOS runner' }
        Write-Host 'iOS package:       Unsigned device .app archive'
        Write-Host "iOS build:         $iosBuildLocation"
    }
    Write-Host "Version:           $VersionName+$BuildNumber"
    Write-Host "Mode:              $Mode"
    Write-Host "Output:            $OutputDirectory"
    Write-Host "Clean:             $shouldClean"
    Write-Host "Restore packages:  $shouldGetPackages"
    Write-Host "Analyze and test:  $shouldRunChecks"
    Write-Host "Obfuscate:         $shouldObfuscate"
    if ($usesDebugReleaseSigning) {
        Write-Host 'WARNING: Release builds currently use the debug signing key and are not store-ready.' -ForegroundColor Yellow
    }
    if ($shouldBuildAndroid -and $ApplicationId -like 'com.example.*') {
        Write-Host 'WARNING: The example application ID should be replaced before publishing.' -ForegroundColor Yellow
    }

    if (-not $NonInteractive) {
        $confirmed = Read-YesNo -Prompt 'Proceed with this build?' -DefaultValue $true
        if (-not $confirmed) {
            Write-Host 'Build cancelled. No project metadata was changed.' -ForegroundColor Yellow
            exit 0
        }
    }

    $remoteIosContext = $null
    if ($shouldBuildIosRemotely) {
        $remoteIosContext = Get-RemoteIosContext `
            -AllowPrompt (-not $NonInteractive) `
            -WorkflowFile $iosWorkflowFile `
            -ApiVersion $gitHubApiVersion
    }

    if ($shouldBuildAndroid) {
        Confirm-SymbolicLinkSupport -AllowPrompt (-not $NonInteractive)
    }

    if ($usesLocalFlutter -and $shouldClean) {
        Invoke-FlutterStep -Title 'Cleaning previous build outputs...' -Arguments @('clean')
    }
    if ($usesLocalFlutter -and $shouldGetPackages) {
        Invoke-FlutterStep -Title 'Restoring Flutter packages...' -Arguments @('pub', 'get')
    }
    if ($usesLocalFlutter -and $shouldRunChecks) {
        Invoke-FlutterStep -Title 'Running static analysis...' -Arguments @('analyze')
        Invoke-FlutterStep -Title 'Running automated tests...' -Arguments @('test')
    }

    $symbolRoot = Join-Path $projectDirectory "build/symbols/$VersionName+$BuildNumber"
    $builtArtifacts = @()
    if ($shouldBuildAndroid) {
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

        $androidSymbolDirectory = Join-Path $symbolRoot 'android'
        $buildArguments = @('build', $Format, "--$Mode", '--build-name', $VersionName, '--build-number', $BuildNumber.ToString())
        if ($shouldSplitPerAbi) {
            $buildArguments += '--split-per-abi'
        }
        if ($shouldObfuscate) {
            New-Item -ItemType Directory -Path $androidSymbolDirectory -Force | Out-Null
            $buildArguments += @('--obfuscate', "--split-debug-info=$androidSymbolDirectory")
        }
        Invoke-FlutterStep -Title 'Building StockLens for Android...' -Arguments $buildArguments

        if ($Format -eq 'appbundle') {
            $builtArtifacts = @(Join-Path $projectDirectory "build/app/outputs/bundle/$Mode/app-$Mode.aab")
        } elseif ($shouldSplitPerAbi) {
            $apkDirectory = Join-Path $projectDirectory 'build/app/outputs/flutter-apk'
            $builtArtifacts = @(
                Join-Path $apkDirectory "app-armeabi-v7a-$Mode.apk"
                Join-Path $apkDirectory "app-arm64-v8a-$Mode.apk"
                Join-Path $apkDirectory "app-x86_64-$Mode.apk"
            )
        } else {
            $builtArtifacts = @(Join-Path $projectDirectory "build/app/outputs/flutter-apk/app-$Mode.apk")
        }

        foreach ($artifact in $builtArtifacts) {
            if (-not (Test-Path -LiteralPath $artifact)) {
                throw "Expected build artifact was not found: $artifact"
            }
        }
    }

    $iosAppPath = $null
    if ($shouldBuildIosLocally) {
        $iosBuildArguments = @(
            'build',
            'ios',
            "--$Mode",
            '--no-codesign',
            '--build-name',
            $VersionName,
            '--build-number',
            $BuildNumber.ToString()
        )
        if ($shouldObfuscate) {
            $iosSymbolDirectory = Join-Path $symbolRoot 'ios'
            New-Item -ItemType Directory -Path $iosSymbolDirectory -Force | Out-Null
            $iosBuildArguments += @('--obfuscate', "--split-debug-info=$iosSymbolDirectory")
        }
        Invoke-FlutterStep -Title 'Building StockLens for iOS without code signing...' -Arguments $iosBuildArguments
        $iosAppPath = Join-Path $projectDirectory 'build/ios/iphoneos/Runner.app'
        if (-not (Test-Path -LiteralPath $iosAppPath -PathType Container)) {
            throw "Expected iOS application was not found: $iosAppPath"
        }
    }

    $outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory
    } else {
        Join-Path $projectDirectory $OutputDirectory
    }
    $safeAppName = ($AppName -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeAppName)) { $safeAppName = 'StockLens' }
    $releaseFolderName = "$safeAppName-v$VersionName+$BuildNumber-$Mode-$Target"
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
            platform = 'android'
            file = $destinationName
            bytes = (Get-Item -LiteralPath $destinationPath).Length
            sha256 = $hash
        }
    }

    if ($shouldBuildIosLocally) {
        $iosDestinationName = "$safeAppName-v$VersionName+$BuildNumber-$Mode-ios-unsigned-app.zip"
        $iosDestinationPath = Join-Path $releaseDirectory $iosDestinationName
        Write-Host "`nPackaging unsigned iOS application..." -ForegroundColor Cyan
        & ditto -c -k --sequesterRsrc --keepParent $iosAppPath $iosDestinationPath
        if ($LASTEXITCODE -ne 0) {
            throw "Packaging the iOS application failed with exit code $LASTEXITCODE."
        }
        if (-not (Test-Path -LiteralPath $iosDestinationPath -PathType Leaf)) {
            throw "Expected iOS archive was not found: $iosDestinationPath"
        }
        $iosHash = (Get-FileHash -LiteralPath $iosDestinationPath -Algorithm SHA256).Hash
        $artifactRecords += [ordered]@{
            platform = 'ios'
            file = $iosDestinationName
            bytes = (Get-Item -LiteralPath $iosDestinationPath).Length
            sha256 = $iosHash
            codeSigned = $false
            source = 'local-macos'
        }
    }

    if ($shouldBuildIosRemotely) {
        $remoteIosRecord = Invoke-RemoteIosBuild `
            -Context $remoteIosContext `
            -VersionName $VersionName `
            -BuildNumber $BuildNumber `
            -Mode $Mode `
            -SafeAppName $safeAppName `
            -Obfuscate $shouldObfuscate `
            -RunChecks $shouldRunChecks `
            -DestinationDirectory $releaseDirectory `
            -TimeoutMinutes $RemoteIosTimeoutMinutes
        $artifactRecords += $remoteIosRecord
    }

    $buildRecord = [ordered]@{
        applicationName = $AppName
        target = $Target
        applicationId = if ($shouldBuildAndroid) { $ApplicationId } else { $null }
        versionName = $VersionName
        buildNumber = $BuildNumber
        androidFormat = if ($shouldBuildAndroid) { $Format } else { $null }
        mode = $Mode
        obfuscated = $shouldObfuscate
        splitPerAbi = $shouldSplitPerAbi
        androidBuildIncluded = $shouldBuildAndroid
        iosBuildIncluded = $shouldBuildIos
        iosCodeSigned = if ($shouldBuildIos) { $false } else { $null }
        iosBuildSource = if ($shouldBuildIosLocally) { 'local-macos' } elseif ($shouldBuildIosRemotely) { 'github-actions' } else { $null }
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
