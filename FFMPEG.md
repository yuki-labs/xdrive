# FFmpeg Binaries

FFmpeg binaries are excluded from this repository due to GitHub's 100MB file size limit.

## Download FFmpeg

### For Windows Development:
1. Download FFmpeg from: https://github.com/BtbN/FFmpeg-Builds/releases
2. Extract `ffmpeg.exe` 
3. Place it at: `assets/ffmpeg/windows/ffmpeg.exe`

### For macOS Development:
1. Download FFmpeg from: https://evermeet.cx/ffmpeg/
2. Extract `ffmpeg` binary
3. Place it at: `assets/ffmpeg/macos/ffmpeg`

### For Linux Development:
```bash
# Install via package manager
sudo apt install ffmpeg  # Debian/Ubuntu
# Or download from https://ffmpeg.org/download.html
```
4. Copy binary to: `assets/ffmpeg/linux/ffmpeg`

## Directory Structure

After downloading, your `assets/ffmpeg/` folder should look like:
```
assets/ffmpeg/
├── windows/
│   └── ffmpeg.exe
├── macos/
│   └── ffmpeg
└── linux/
    └── ffmpeg
```

## Note for End Users

The release builds will include FFmpeg bundled automatically. This manual setup is only needed for development.
