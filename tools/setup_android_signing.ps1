[CmdletBinding()]
param(
    [Parameter()]
    [string]$Alias = 'stocklens',

    [Parameter()]
    [string]$CommonName = 'jrpbone',

    [Parameter()]
    [string]$Organization = 'jrpbone',

    [Parameter()]
    [string]$City = 'Ligao City',

    [Parameter()]
    [string]$State = 'Albay',

    [Parameter()]
    [ValidatePattern('^[A-Za-z]{2}$')]
    [string]$CountryCode = 'PH',

    [Parameter()]
    [ValidateRange(365, 36500)]
    [int]$ValidityDays = 10000,

    [Parameter()]
    [switch]$GeneratePassword
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$androidDirectory = Join-Path $projectDirectory 'android'
$keystorePath = Join-Path $androidDirectory 'app\stocklens-release.jks'
$propertiesPath = Join-Path $androidDirectory 'key.properties'
$createdKeystore = $false
$createdProperties = $false

function ConvertFrom-PrivateSecureString {
    param([Parameter(Mandatory)] [Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function New-RandomPassword {
    $bytes = New-Object byte[] 32
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }
    return ([Convert]::ToBase64String($bytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Find-Keytool {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $javaHomeKeytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
        if (Test-Path -LiteralPath $javaHomeKeytool) {
            return $javaHomeKeytool
        }
    }
    $androidStudioKeytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    if (Test-Path -LiteralPath $androidStudioKeytool) {
        return $androidStudioKeytool
    }
    throw 'keytool was not found. Install Android Studio or a Java Development Kit and retry.'
}

try {
    if (Test-Path -LiteralPath $keystorePath) {
        throw "Refusing to overwrite the existing keystore: $keystorePath"
    }
    if (Test-Path -LiteralPath $propertiesPath) {
        throw "Refusing to overwrite the existing signing configuration: $propertiesPath"
    }

    $password = if ($GeneratePassword) {
        New-RandomPassword
    }
    else {
        $first = ConvertFrom-PrivateSecureString (Read-Host 'New keystore password' -AsSecureString)
        $second = ConvertFrom-PrivateSecureString (Read-Host 'Confirm keystore password' -AsSecureString)
        if ([string]::IsNullOrWhiteSpace($first) -or $first.Length -lt 12) {
            throw 'The keystore password must contain at least 12 characters.'
        }
        if ($first -cne $second) {
            throw 'The passwords did not match.'
        }
        $first
    }

    $keytoolPath = Find-Keytool
    $distinguishedName = "CN=$CommonName, OU=StockLens, O=$Organization, L=$City, ST=$State, C=$($CountryCode.ToUpperInvariant())"
    $env:STOCKLENS_KEYSTORE_PASSWORD = $password

    Write-Host 'Creating the StockLens Android upload keystore...' -ForegroundColor Cyan
    & $keytoolPath `
        -genkeypair `
        -v `
        -keystore $keystorePath `
        -storetype PKCS12 `
        '-storepass:env' STOCKLENS_KEYSTORE_PASSWORD `
        '-keypass:env' STOCKLENS_KEYSTORE_PASSWORD `
        -alias $Alias `
        -keyalg RSA `
        -keysize 2048 `
        -validity $ValidityDays `
        -dname $distinguishedName
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $keystorePath)) {
        throw "keytool failed to create the keystore (exit code $LASTEXITCODE)."
    }
    $createdKeystore = $true

    $properties = @(
        "storePassword=$password"
        "keyPassword=$password"
        "keyAlias=$Alias"
        'storeFile=stocklens-release.jks'
        ''
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText(
        $propertiesPath,
        $properties,
        [Text.UTF8Encoding]::new($false)
    )
    $createdProperties = $true

    & $keytoolPath `
        -list `
        -keystore $keystorePath `
        '-storepass:env' STOCKLENS_KEYSTORE_PASSWORD `
        -alias $Alias | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The created keystore could not be verified (exit code $LASTEXITCODE)."
    }

    Write-Host 'Android release signing configured successfully.' -ForegroundColor Green
    Write-Host "Keystore:  $keystorePath"
    Write-Host "Properties: $propertiesPath"
    Write-Host 'Back up both files together in a secure password manager or encrypted archive.' -ForegroundColor Yellow
    Write-Host 'Neither file should ever be committed to Git.' -ForegroundColor Yellow
}
catch {
    if ($createdProperties -and (Test-Path -LiteralPath $propertiesPath)) {
        Remove-Item -LiteralPath $propertiesPath -Force -ErrorAction SilentlyContinue
    }
    if ($createdKeystore -and (Test-Path -LiteralPath $keystorePath)) {
        Remove-Item -LiteralPath $keystorePath -Force -ErrorAction SilentlyContinue
    }
    Write-Error $_
    exit 1
}
finally {
    Remove-Item Env:STOCKLENS_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
    $password = $null
}
