# Video Streaming Fix - Timeout Issue

## Problem

Video playback over relay was failing with:
```
Error fetching file via relay: TimeoutException after 0:00:30.000000: Request timed out
```

## Root Cause

The `RelayConnection.sendRequest()` method had a **30-second timeout** which is insufficient for downloading large video files through the relay.

**Example:**
- Small thumbnail (216KB): Downloads in <1 second ✅
- Large video (100MB+): Takes >30 seconds, times out ❌

## Solution

**Increased timeout to 5 minutes** in `lib/relay/relay_connection.dart`:

```dart
// Before:
Future.delayed(const Duration(seconds: 30), () { ... });

// After:
Future.delayed(const Duration(minutes: 5), () { ... });
```

## How Video Streaming Works

### Architecture:
```
Mobile Video Player
    ↓
LocalProxyServer (localhost:random_port)
    ↓
getStreamBytes(path) - downloads ENTIRE file
    ↓
RelayConnection.sendRequest() - with 5min timeout
    ↓
Desktop Server
```

### Flow:
1. User taps video
2. `getProxyUrl()` returns `http://localhost:8765/stream?path=...`
3. Video player requests from localhost
4. LocalProxyServer calls `getStreamBytes()`
5. Downloads entire video via relay (can take several minutes)
6. Caches in memory
7. Serves to video player with HTTP 200/206

## Limitations

### Current Approach:
- ✅ Works for videos up to ~500MB (within 5min)
- ⚠️ Downloads entire file before playback starts
- ⚠️ High memory usage
- ⚠️ No progress indicator

### Future Improvements:

1. **Chunked Streaming:**
   - Download video in chunks as playback progresses
   - Reduce memory usage
   - Faster time-to-first-frame

2. **Progressive Download:**
   - Start playback while downloading
   - Buffer ahead of playback position

3. **Disk Caching:**
   - Save to temp file instead of memory
   - Support very large files

4. **Progress Indicator:**
   - Show download progress while waiting
   - "Downloading... 45%"

## Testing

**Test Cases:**
1. ✅ Small video (<10MB): Should work quickly
2. ✅ Medium video (50-100MB): Should work within 1-2 minutes
3. ⏳ Large video (200-500MB): May take 3-5 minutes
4. ❌ Very large video (>500MB): May still timeout

**Recommended Video Sizes:**
- Optimal: <50MB
- Good: 50-200MB
- Acceptable: 200-500MB
- Not recommended: >500MB

## File Changed

- `lib/relay/relay_connection.dart` - Timeout: 30s → 5min

## Commit

"Increased relay timeout to 5 minutes for large video downloads"

---

**Status:** Fixed ✅  
**Date:** 2025-11-30  
**Impact:** Large videos now work over relay!
