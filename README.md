# Fast Share 🚀

Cross-platform file and text sharing between your PC and phone — fast, encrypted, and private.

Scan a QR code, and you're connected. No accounts, no cloud, no nonsense.

---

## ✨ Features

- **QR Code Pairing** — Scan to connect instantly. No setup wizards.
- **File Sharing** — Send any file between PC and mobile via drag & drop or file picker.
- **Image Sharing** — Images display inline with preview. Tap/click to open.
- **Text Messaging** — Send text back and forth with link detection.
- **Clipboard Sync** — Copy on one device, paste on the other. Works both ways.
- **End-to-End Encryption** — All communication encrypted with AES-GCM via ECDH key exchange.
- **AI Summarization** — Summarize text, PDFs, DOCX, and images using OpenAI-compatible APIs (OpenRouter, etc.).
- **OS Context Menu Sharing** — Share files directly from Windows right-click menu or Android share sheet.
- **Message History** — Conversations persist across sessions on PC.
- **No Cloud Required** — Everything runs on your local network. Your data stays on your devices.

---

## 📸 Screenshots

> _Coming soon_

---

## 🖥️ PC Client

Built with **Electron + React + Vite + TypeScript**.

### Download

Grab the latest `Fast-Share-Setup-1.0.0.exe` from [Releases](https://github.com/Woodylai24/fast-share/releases).

### Install from Source

```bash
cd pc_client
npm install
npm run dev
```

### Build Installer

```bash
npm run dist
```

Output: `pc_client/release/Fast-Share-Setup-1.0.0.exe`

---

## 📱 Mobile Client

Built with **Flutter (Dart)** for Android.

### Download

Grab the latest `fast-share-1.0.0.apk` from [Releases](https://github.com/Woodylai24/fast-share/releases).

### Install from Source

```bash
cd mobile_client
flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --release
```

Output: `mobile_client/build/app/outputs/flutter-apk/app-release.apk`

---

## 🔐 How It Works

1. **PC acts as server** — Starts WebSocket + HTTP server on your local network.
2. **Mobile scans QR code** — Encodes the PC's IP and port for instant pairing.
3. **E2EE handshake** — Devices exchange ECDH public keys, derive a shared AES-GCM key.
4. **Share away** — Files, text, and clipboard data flow through the encrypted WebSocket channel.

All data stays on your local network. No third-party servers involved.

---

## 🤖 AI Summarization

Fast Share can summarize text, PDFs, DOCX documents, and images using any OpenAI-compatible API.

1. Open **Settings** (⚙️ gear icon) on the PC client.
2. Enter your API key and endpoint (e.g., [OpenRouter](https://openrouter.ai)).
3. Right-click any message → **🤖 Summarize**.

---

## 🛠️ Tech Stack

| Component | Tech |
|-----------|------|
| PC Client | Electron, React, Vite, TypeScript |
| Mobile Client | Flutter, Dart |
| Communication | WebSocket (encrypted) |
| Encryption | ECDH + AES-GCM |
| AI | OpenAI-compatible API (OpenRouter) |

---

## 📋 Requirements

- **PC:** Windows 10/11 (x64)
- **Mobile:** Android 6.0+ (API 23+)
- **Network:** Both devices on the same Wi-Fi network

---

## 📜 License

MIT

---

## 🙋 Author

**Woody Lai** — [woodylai.com](https://woodylai.com) · [GitHub](https://github.com/Woodylai24)
