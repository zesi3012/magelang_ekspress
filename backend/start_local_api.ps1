$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/health' -TimeoutSec 2
    if ($health.ok -eq $true) {
        Write-Warning 'Magelang Ekspres API is already running at http://127.0.0.1:8787.'
        Write-Host 'This script cannot update the running API process or its SMTP settings.'
        Write-Host 'Press Ctrl+C in the PowerShell window running the API, then run this script again.'
        exit 1
    }
} catch {
    # Start the local server when its health endpoint is unavailable.
}

function New-RuntimeSecret {
    $bytes = New-Object byte[] 48
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally {
        $generator.Dispose()
    }
}

function New-LocalVerificationCode {
    $bytes = New-Object byte[] 4
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [BitConverter]::ToString($bytes).Replace('-', '')
    } finally {
        $generator.Dispose()
    }
}

$env:APP_ENV = 'development'
$env:API_BIND_HOST = '127.0.0.1'
$env:STORE_PATH = 'backend\data\store.json'
$env:ADMIN_2FA_CODE = New-LocalVerificationCode
$env:DOWNLOAD_SIGNING_SECRET = New-RuntimeSecret

if ([string]::IsNullOrWhiteSpace($env:SMTP_USERNAME) -or
    [string]::IsNullOrWhiteSpace($env:SMTP_APP_PASSWORD)) {
    Write-Host 'Configure Gmail SMTP to enable email OTP for CMS admin logins.'
    if ([string]::IsNullOrWhiteSpace($env:SMTP_USERNAME)) {
        $env:SMTP_USERNAME = Read-Host 'Gmail sender address'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SMTP_USERNAME) -and
        [string]::IsNullOrWhiteSpace($env:SMTP_APP_PASSWORD)) {
        $secureAppPassword = Read-Host 'Gmail App Password (input hidden)' -AsSecureString
        $passwordPointer = [IntPtr]::Zero
        try {
            $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAppPassword)
            $env:SMTP_APP_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
        } finally {
            if ($passwordPointer -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
            }
            $secureAppPassword.Dispose()
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SMTP_USERNAME) -and
        -not [string]::IsNullOrWhiteSpace($env:SMTP_APP_PASSWORD)) {
        if ([string]::IsNullOrWhiteSpace($env:SMTP_HOST)) {
            $env:SMTP_HOST = 'smtp.gmail.com'
        }
        if ([string]::IsNullOrWhiteSpace($env:SMTP_PORT)) {
            $env:SMTP_PORT = '587'
        }
        if ([string]::IsNullOrWhiteSpace($env:SMTP_FROM_EMAIL)) {
            $env:SMTP_FROM_EMAIL = $env:SMTP_USERNAME
        }
        if ([string]::IsNullOrWhiteSpace($env:SMTP_FROM_NAME)) {
            $env:SMTP_FROM_NAME = 'Magelang Ekspres'
        }
    }
}

Write-Host "Temporary local verification code: $env:ADMIN_2FA_CODE"
Write-Host 'This development-only shared code is for reader verification only.'
if ([string]::IsNullOrWhiteSpace($env:SMTP_USERNAME) -or
    [string]::IsNullOrWhiteSpace($env:SMTP_APP_PASSWORD)) {
    Write-Warning 'Admin email OTP is unavailable until SMTP_USERNAME and SMTP_APP_PASSWORD are configured in this PowerShell session.'
}
Write-Host 'Starting the local API. Keep this PowerShell window open while using the website.'
& dart run backend/server.dart
if ($LASTEXITCODE -ne 0) {
    throw "The API stopped with exit code $LASTEXITCODE."
}
