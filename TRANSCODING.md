# Server Transcoding Setup

The server now supports on-the-fly transcoding for videos with unsupported codecs.

## Supported Codecs (Native):
- H.264/AVC
- H.265/HEVC
- VP8, VP9
- AV1

## Transcoded Codecs (Requires FFmpeg):
- DivX, XviD
- MPEG-2, MPEG-4
- WMV, FLV
- AC3, DTS audio
- Any other codec FFmpeg supports

## FFmpeg Installation:

### Windows:
1. Download from: https://www.gyan.dev/ffmpeg/builds/
2. Extract to `C:\ffmpeg`
3. Add `C:\ffmpeg\bin` to PATH
4. Verify: `ffmpeg -version`

### macOS:
```bash
brew install ffmpeg
```

### Linux:
```bash
sudo apt install ffmpeg
```

## How It Works:

### Automatic Detection:
1. Client requests `/file-info` for video
2. Server probes codec with `ffprobe`
3. Response includes `needsTranscoding: true` if needed
4. Client appends `?transcode=true` when streaming

### Manual Override:
Add `?transcode=true` to any video URL to force transcoding:
```
http://localhost:8080/stream?path=/video.avi&transcode=true
```

## Performance:

- **No transcoding:** Direct streaming, no CPU usage
- **With transcoding:** ~50-200% CPU per stream (depends on preset)
- **Preset:** `veryfast` (can change to `fast`, `medium`, `slow` for better quality)

## Limitations:

- Transcoded streams don't support seeking (yet)
- First frame may take 1-2 seconds to appear
- Multiple transcodes = high CPU usage

## Future Improvements:

- Cache transcoded segments
- Support seeking in transcoded streams
- Adaptive bitrate based on network speed
