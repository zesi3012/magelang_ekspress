# magelang_express

A new Flutter project.

 # Magelang Ekspres
 
 Flutter news portal for Magelang Ekspres with a local Dart API used during development.
 
 ## Current Architecture
 
 - `lib/main.dart`: application composition and existing feature screens.
 - `lib/core/design/`: centralized editorial colors, spacing, radius, typography, and breakpoints.
 - `lib/core/widgets/`: reusable Magelang Ekspres presentation widgets.
 - `lib/models/`, `lib/repositories/`, `lib/screens/`: domain and feature code already present in the project.
 - `backend/server.dart`: local JSON-backed API on port `8787`.
 - `backend/data/store.json`: development seed and local state.

 The API seeds the attached 13 August and 1 October 2026 newspaper editions as
 examples. The 13 August page 6 is highlighted as Kampung Inovatif. Public
 previews are low resolution; full scans and PDF downloads require an active
 subscription and use expiring signed URLs. Direct Apache access to private
 storage and source PDFs is denied.
 
The Flutter app bundles low-resolution previews for both editions (about 44 KB
total), so a default web preview opens without waiting for a local API. Offline
article previews are limited to the two Kampung Inovatif stories verified on
page 6 of the supplied 13 August edition; no fictional Koran Sekolah article
or generic newspaper edition is seeded. Connect to a backend explicitly with
`--dart-define=USE_API=true` and a valid `API_BASE_URL`.

 The CMS editor supports article slugs, SEO title/description, and HTTPS social
 links (YouTube, Instagram, TikTok, Facebook, and a website link). Premium
 article responses omit those links until a valid subscriber session unlocks
 the article. See
 [`docs/google-play-blueprint.md`](docs/google-play-blueprint.md) for the
 editorial/technical blueprint and the Google Play preparation checklist. Play
 Store release builds require a publisher-owned package ID and upload keystore;
 the project deliberately does not sign release builds with a debug key.
 
 The app currently uses explicit local repositories for development. It is not a claim that PostgreSQL, S3, a payment provider, or a Next.js website is deployed.
 
 ## Run Flutter
 
 ```powershell
 flutter pub get
 flutter run
 ```
 
 ## Run Backend

 From the repository root, configure secrets in the current PowerShell session.
 The API intentionally refuses to start with missing or example secrets:

 ```powershell
 function New-Secret {
   $bytes = New-Object byte[] 32
   $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
   try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
   [Convert]::ToBase64String($bytes)
 }
 $env:APP_ENV='development'
 $env:API_BIND_HOST='127.0.0.1'
 $env:ADMIN_2FA_CODE='replace-with-a-private-code'
 $env:DOWNLOAD_SIGNING_SECRET=New-Secret
 $env:ADMIN_BOOTSTRAP_TOKEN=New-Secret
 dart run backend/server.dart
 ```

 `ADMIN_2FA_CODE` is retained for the current reader verification flow; admin
 login OTPs are generated per challenge and emailed using the SMTP settings
 below. Bootstrap the first CMS administrator once, while no admin exists:

 ```powershell
 $headers = @{ 'X-Admin-Bootstrap-Key' = $env:ADMIN_BOOTSTRAP_TOKEN }
 $body = @{ email = 'editor@example.com'; password = 'use-a-unique-long-password'; role = 'Super Admin' } | ConvertTo-Json
 Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8787/api/admin/auth/register -Headers $headers -ContentType 'application/json' -Body $body
 ```

 Keep the bootstrap token private and remove it from the environment after
 provisioning. There is no built-in admin account. The API listens on
 `http://127.0.0.1:8787`.
 
 ## Local Environment
 
 - `API_BASE_URL`: Flutter admin client base URL. Defaults to `http://localhost:8787`.
 - `STORE_PATH`: optional JSON store location for isolated local/test runs;
   defaults to `backend/data/store.json`. It is ignored when `DB_DRIVER=mysql`.
 - `ADMIN_2FA_CODE`: private verification code for the current reader challenge
   flow. CMS admin OTPs are unique per login and delivered through Gmail SMTP.
 - `SMTP_HOST` / `SMTP_PORT`: SMTP server; defaults for admin login are
   `smtp.gmail.com` and `587`.
 - `SMTP_USERNAME` / `SMTP_APP_PASSWORD`: Gmail account and its App Password
   (not the regular account password).
 - `SMTP_FROM_EMAIL` / `SMTP_FROM_NAME`: optional sender address and display
   name; the address defaults to `SMTP_USERNAME`.
 - `ADMIN_BOOTSTRAP_TOKEN`: one-time setup credential needed only to create
   the first CMS administrator.
 - `DOWNLOAD_SIGNING_SECRET`: random signing secret, at least 32 characters.
 - `MIDTRANS_SERVER_KEY` and `MIDTRANS_IS_PRODUCTION`: optional until a
   publisher-owned Midtrans merchant account is available. Real checkout is
   enabled only when a server key is configured; production requires the
   production key and `MIDTRANS_IS_PRODUCTION=true`.
 - `ALLOWED_ORIGINS`: comma-separated exact browser origins; production accepts
   HTTPS origins only.

 Passwords are stored as PBKDF2-HMAC-SHA256 hashes and legacy hashes are
 upgraded on successful login. Verified access tokens are random opaque values;
 only their SHA-256 hashes are stored, and sessions persist across API restarts
 in JSON or MySQL/MariaDB. Login challenges are still in memory and the local
 reader verification code is shared, so production mode deliberately refuses
 to start until per-user reader email verification, password recovery, and
 non-shared reader MFA delivery exist. Admin MFA is delivered by email.
 
 ## API Surface
 
 The local server supports the existing `/api/*` routes and `/api/v1/*` aliases for:
 
 - `GET /health`
 - `GET /api/v1/home`
 - `GET /api/v1/articles`
 - `GET /api/v1/articles/:id`
 - `GET /api/v1/categories`
 - `GET /api/v1/search?q=...`
 - `GET /api/v1/epapers`
 - `POST /api/v1/auth/login`
 - `POST /api/v1/auth/verify`
 - selected admin article, publish, dashboard, and subscription-plan routes
 
 Versioned routes use the envelope `{ success, message, data, meta, errors }`. Premium article responses redact body/content and original asset fields for guests and inactive sessions.
 
 ## Tests and Analysis
 
 ```powershell
 flutter analyze
 flutter test
 dart analyze backend
 ```
 
 Repository tests cover article, e-paper, subscription, and widget behavior. Add API integration tests before treating the backend contract as production-ready.
 
 ## Production Migration
 
 The current JSON store is a local development adapter. A production deployment still requires:
 
 - Production database user/credentials, tested backup and recovery, and
   migration application. MySQL/MariaDB storage now uses upserts instead of
   wiping all tables on every save; deleted rows and multiple concurrent API
   instances still need integration testing.
 - Managed secret/configuration delivery and rotation; PBKDF2-HMAC-SHA256 is
   implemented, but production should review its password policy and operational
   parameters.
 - Private object storage with signed, expiring asset URLs and download logging.
 - A configured publisher-owned Midtrans merchant account, public HTTPS
   webhook at `/api/v1/payment/webhook`, and end-to-end sandbox/production
   transaction verification. The backend now creates Snap checkout sessions,
   validates webhook signatures and invoice totals, and rejects fake manual
   payment confirmation. No live merchant credentials are present in this
   workspace.
 - Verified email and actual password-reset email delivery, and per-user
   admin 2FA infrastructure. The current forgot-password response is not an
   implemented email workflow.
 - A separate SEO-capable website if server-rendered search indexing is required. Flutter Web is not represented as Next.js SEO production output.
 
 ## Known Limitations
 
 The current continuation focuses on aligning the Flutter shell with the supplied editorial reference and making the local v1 read API enforce premium redaction. Authentication, payments, e-paper protected downloads, CMS breadth, persistent saved items, and the full reference-by-reference screen pass still require implementation and integration tests.
