# Spacedrive

A cross-platform file sharing and management application with end-to-end encryption, built with Flutter.

## Features

- **Cross-Platform**: Works on Windows, macOS, Linux, Android, and iOS
- **Local Network Discovery**: Automatically discover devices on your LAN
- **Relay Server Support**: Access files over the internet via relay server
- **End-to-End Encryption**: AES-256-GCM encryption for all data transfer
- **File Tagging**: Organize files with hash-based tags that sync across devices
- **Media Support**: 
  - Image thumbnails
  - Video thumbnails (FFmpeg on desktop, native on mobile)
  - Audio/video playback
- **File Operations**: Create, delete, move, and upload files remotely

## Architecture

### Mobile App (Flutter)
- `lib/client/` - Remote file provider and connection logic
- `lib/ui/` - User interface components
- `lib/storage/` - Local tag database (SQLite)

### Desktop Server (Flutter)
- `lib/server/` - HTTP file server with encryption
  - `request_handlers/` - Modular request handlers
  - `utils/` - Helper utilities (thumbnails, encryption)
- `lib/relay/` - Relay client for internet access

### Relay Server (Node.js)
- `relay-server/` - WebSocket relay for internet connectivity

## Getting Started

### Prerequisites
- Flutter SDK (3.0+)
- Node.js (16+) for relay server
- Visual Studio 2022 (for Windows builds)

### Running Locally

1. **Desktop App:**
   ```bash
   flutter run -d windows  # or macos/linux
   ```

2. **Mobile App:**
   ```bash
   flutter run -d android  # or ios
   ```

3. **Relay Server:**
   ```bash
   cd relay-server
   npm install
   node server.js
   ```

### Building

**Windows:**
```bash
flutter build windows --release
```

**Android:**
```bash
flutter build apk
```

## Usage

### Local Network
1. Run desktop app, enable "Local Network" in settings
2. On mobile, tap "Local Network" tab
3. Select discovered device and enter passphrase
4. Browse files!

### Internet (via Relay)
1. Run relay server on a public VPS
2. Desktop: Enable "Internet Access", copy Room ID
3. Mobile: Tap "Internet" tab, enter Room ID and passphrase
4. Access files from anywhere!

## Security

- All file transfers encrypted with AES-256-GCM
- Passphrase-based key derivation (PBKDF2)
- End-to-end encryption - relay server never sees plaintext
- Deterministic salt derivation from passphrase

## Project Structure

```
spacedrive_attempt/
├── lib/
│   ├── client/          # Mobile client code
│   ├── server/          # Desktop server code
│   │   ├── request_handlers/
│   │   └── utils/
│   ├── relay/           # Relay client
│   ├── crypto/          # Encryption services
│   ├── storage/         # SQLite tag database
│   ├── models/          # Data models
│   └── ui/              # UI components
├── relay-server/        # Node.js WebSocket relay
└── assets/              # Images, FFmpeg binaries

```

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

[Add your license here]

## Acknowledgments

- FFmpeg for video thumbnail generation
- Flutter team for excellent cross-platform framework
- All contributors and testers
