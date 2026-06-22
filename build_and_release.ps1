# build_and_release.ps1

$ErrorActionPreference = "Continue"

$repo        = "Sunthunder0813/remind-apk"
$tag         = "latest"
$apkSrc      = "build\app\outputs\flutter-apk\app-release.apk"
$assetName   = "app-release.apk"
$downloadUrl = "https://github.com/$repo/releases/download/$tag/$assetName"

# ── 1. Build ────────────────────────────────────────────────────────────────
Write-Host "==> Building full release APK (all ABIs)..." -ForegroundColor Cyan
flutter build apk --release

if (-not (Test-Path $apkSrc)) {
    Write-Host "ERROR: APK not found at $apkSrc — build may have failed." -ForegroundColor Red
    exit 1
}

# ── 2. (No copy needed — $apkSrc already matches the target asset name) ──────
$apkFixed = $apkSrc

# ── 3. Check whether the release tag already exists ─────────────────────────
Write-Host "==> Checking if '$tag' release exists..." -ForegroundColor Cyan
gh release view $tag --repo $repo 2>&1 | Out-Null
$releaseExists = ($LASTEXITCODE -eq 0)

# ── 4. Create or upload ──────────────────────────────────────────────────────
if (-not $releaseExists) {
    Write-Host "==> Creating '$tag' release for the first time..." -ForegroundColor Cyan
    gh release create $tag $apkFixed `
        --repo $repo `
        --title "Latest Build" `
        --notes "Auto-updated on every local release build. Always the most recent APK." `
        --latest
} else {
    Write-Host "==> Uploading new APK (overwriting previous)..." -ForegroundColor Cyan
    gh release upload $tag $apkFixed --repo $repo --clobber
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: gh command failed (exit code $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

# ── 5. Verify ────────────────────────────────────────────────────────────────
Write-Host "==> Verifying upload..." -ForegroundColor Cyan
gh release view $tag --repo $repo --json assets --jq '.assets[].name'

# ── 6. Print URL + QR code ──────────────────────────────────────────────────
Write-Host ""
Write-Host "==> Done! Stable download URL:" -ForegroundColor Green
Write-Host "    $downloadUrl" -ForegroundColor Yellow
Write-Host ""
Write-Host "==> QR code (open this URL to scan):" -ForegroundColor Cyan

# Generate QR as a PNG file and open it — more reliable than terminal rendering
$qrHtml = "build\qr_code.html"
$qrContent = @"
<!DOCTYPE html>
<html>
<head>
  <title>APK QR Code</title>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
  <style>
    body { font-family: sans-serif; display: flex; flex-direction: column; align-items: center; padding: 40px; background: #fff; }
    h2 { margin-bottom: 8px; }
    p { color: #555; font-size: 13px; word-break: break-all; max-width: 320px; text-align: center; }
    #qr { margin: 24px 0; }
  </style>
</head>
<body>
  <h2>Scan to install latest APK</h2>
  <div id="qr"></div>
  <p>$downloadUrl</p>
  <script>
    new QRCode(document.getElementById("qr"), {
      text: "$downloadUrl",
      width: 256,
      height: 256,
      colorDark: "#000000",
      colorLight: "#ffffff"
    });
  </script>
</body>
</html>
"@

$qrContent | Out-File -FilePath $qrHtml -Encoding UTF8
Write-Host "==> Opening QR code in browser..." -ForegroundColor Cyan
Start-Process $qrHtml

Write-Host ""
Write-Host "QR code saved to: $qrHtml" -ForegroundColor Green
Write-Host "Scan it with any phone camera to download the app." -ForegroundColor Green