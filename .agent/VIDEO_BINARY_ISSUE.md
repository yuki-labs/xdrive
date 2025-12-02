# Video Streaming Issue - Binary Response

## Current Status
✅ Range requests work (headers forwarded)
✅ Desktop sends 524KB chunks
✅ Mobile receives chunks
❌ Video player can't play

## Problem
The relay response is **base64-encoded binary video data** without HTTP headers.

Desktop → Relay: HTTP 206 response with video data
Relay → Mobile: Just the binary body (base64)

## Mobile receives:
```
responseBytes = base64.decode(responseData)  // Just video chunk, no headers!
```

## Video player needs:
```
HTTP/1.1 206 Partial Content
Content-Type: video/x-matroska
Content-Length: 524288
Content-Range: bytes 0-524287/157895840  ← FILE SIZE NEEDED!
Accept-Ranges: bytes

[binary data]
```

## Solution

The proxy server needs to know the **total file size** to construct proper Content-Range.

### Option 1: HEAD request first
```dart
// In StreamingProxyServer, before first range request:
1. Send HEAD request to get Content-Length
2. Store total file size
3. Use it in Content-Range headers
```

### Option 2: Parse from first response
```dart
// Desktop sends Content-Range in first chunk
// Parse it from the response to get total
```

### Option 3: Use wildcardsize (current workaround)
```dart
Content-Range: bytes 0-524287/*
```
This should work but some players reject it.

## Recommended Fix:

Add to `StreamingProxyServer`:

```dart
int? _fileSize;  // Cache file size

Future<int?> _getFileSize(ChunkedRelayFetcher fetcher) async {
  if (_fileSize != null) return _fileSize;
  
  // Request first byte to get size from Content-Range
  final result = await fetcher.fetchChunkWithHeaders(0, 0);
  if (result?['contentRange'] != null) {
    // Parse: "bytes 0-0/157895840"
    final match = RegExp(r'/(\d+)$').firstMatch(result!['contentRange']);
    if (match != null) {
      _fileSize = int.parse(match.group(1)!);
    }
  }
  return _fileSize;
}
```

Then use in Content-Range:
```dart
final totalSize = await _getFileSize(fetcher);
request.response.headers.set(
  'content-range', 
  'bytes $start-$end/${totalSize ?? "*"}'
);
```

---

**Status:** ChunkedRelayFetcher enhanced to parse headers
**Next:** Update Streaming

ProxyServer implementation
