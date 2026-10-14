# start_server.ps1
# Jalankan server Magelang Ekspress untuk development

function New-Secret {
  $bytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  [Convert]::ToBase64String($bytes)
}

$env:APP_ENV = 'development'
$env:API_BIND_HOST = '0.0.0.0'
$env:ADMIN_2FA_CODE = 'kode-rahasia-anda-123'
$env:DOWNLOAD_SIGNING_SECRET = (New-Secret)
$env:ADMIN_BOOTSTRAP_TOKEN = (New-Secret)

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host "  Magelang Ekspress API - Development Mode" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Menjalankan server di http://0.0.0.0:8787" -ForegroundColor Yellow
Write-Host "OTP login admin akan muncul di console ini." -ForegroundColor Yellow
Write-Host ""

dart run backend/server.dart