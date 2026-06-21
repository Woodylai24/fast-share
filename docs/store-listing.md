# Play Store Listing — Fast Share (v1.1.0)

## App details
- **App name:** Fast Share
- **Package:** `io.github.woodylai24.fastshare`
- **Category:** Tools (or Communication)
- **Content rating:** Everyone (no user-generated content, no sensitive material)
- **App type:** App
- **Price:** Free
- **Contains ads:** No
- **In-app purchases:** No

## Short description (≤80 chars)
Share files, photos & text between your PC and phone over Wi-Fi — fast and private.

## Full description (≤4000 chars)
Fast Share lets you instantly send files, photos, and text between your Windows PC and Android phone over your local Wi-Fi network — no cables, no cloud uploads, no size limits.

**Why Fast Share?**
• Direct device-to-device transfer over your Wi-Fi — fast, private, and no mobile data.
• End-to-end encryption (AES-GCM) keeps your files and messages secure in transit.
• Pair once with a QR code, then it auto-connects whenever both devices are on the same network.
• Offline message queueing with push notifications — your PC holds your messages and notifies your phone when it comes back online.
• Delivery confirmation shows you exactly when your message or file arrived.
• Supports all file types — documents, photos, videos, audio, and more.
• Share directly from any app via Android's share sheet.
• Built-in AI summarization (optional, bring your own API key).

**Perfect for:**
- Sending screenshots and photos from your phone to your PC
- Moving documents between devices without a USB cable
- Sharing links and text snippets quickly
- Keeping a private, encrypted channel between your own devices

**How it works:**
1. Install the PC client on your Windows computer.
2. Install the app on your Android phone.
3. Scan the QR code shown on your PC to pair your devices.
4. Start sharing — files, photos, and text flow directly between your devices over Wi-Fi.

Fast Share never uploads your files to any server. Everything stays on your devices and travels encrypted over your local network.

**Requirements:**
- PC: Windows 10/11 (x64)
- Phone: Android 6.0+
- Both devices connected to the same Wi-Fi network

## Privacy policy URL
Host `docs/privacy-policy.html` via GitHub Pages (repo Settings → Pages → deploy from `main` branch `/docs` folder), giving you:
`https://woodylai24.github.io/fast-share/privacy-policy.html`

## App icon & screenshots
- **Icon:** reuse `mobile_client` launcher icon (512×512 PNG required for Play Console).
- **Screenshots:** capture 2–8 screenshots on a phone showing: QR pairing, chat screen with file/image bubbles, settings page, share-sheet integration. Min 320px, max 3840px on the longest side.

## App signing
- Enroll in **Play App Signing** (recommended). Google holds the app signing key; your `upload-keystore.jks` only authenticates your uploads.
- If you ever lose the upload key, you can request a reset from Play Console (not possible without Play App Signing).

## Testing track strategy
1. Upload `app-release.aab` → **Internal Testing** → add yourself as a tester.
2. Install from the internal testing link on a real device, confirm it works.
3. Promote to **Production** when confident.
