# Critical Fix Needed for Video Streaming

## Problem

Videos fail to stream over relay with error: **"Host disconnected"**

## Root Cause

The desktop server's relay request handler (`file_server.dart` lines 219-224) **does not forward HTTP headers** (especially the `Range` header) when creating Request objects.

## Current Code (BROKEN):

```dart
} else if (uri.path == '/stream') {
  final queryParams = uri.queryParameters;
  response = await _fileHandlers.handleStreamFile(Request(
    method,
    Uri.http('localhost', '/stream', queryParams),  // ❌ NO HEADERS!
  ));
}
```

## Required Fix:

**Step 1:** Parse headers from HTTP request (after line 189):

```dart
// Parse headers from HTTP request
final Map<String, String> headers = {};
for (int i = 1; i < lines.length; i++) {
  if (lines[i].isEmpty) break; // Empty line marks end of headers
  final colonIndex = lines[i].indexOf(':');
  if (colonIndex > 0) {
    final key = lines[i].substring(0, colonIndex).trim().toLowerCase();
    final value = lines[i].substring(colonIndex + 1).trim();
    headers[key] = value;
  }
}
```

**Step 2:** Forward headers in Request (line 219-224):

```dart
} else if (uri.path == '/stream') {
  final queryParams = uri.queryParameters;
  response = await _fileHandlers.handleStreamFile(Request(
    method,
    Uri.http('localhost', '/stream', queryParams),
    headers: headers,  // ✅ PASS HEADERS INCLUDING RANGE!
  ));
}
```

## Why This Fixes It:

1. **Mobile sends:** `Range: bytes=0-524287` (request first 512KB)
2. **Current code:** Strips headers, desktop receives request without Range
3. **Desktop response:** Tries to send ENTIRE video file
4. **Result:** Memory overload → crash → "Host disconnected"

5. **With fix:** Range header preserved
6. **Desktop response:** Sends only requested 512KB chunk  
7. **Result:** Fast streaming, no crash! ✅

## Manual Fix Instructions:

1. Open `lib/server/file_server.dart`
2. Find line 189 (after parsing request line)
3. Add header parsing code
4. Find lines 219-224 (stream handler)
5. Add `headers: headers` parameter
6. Save and rebuild

## File Location:
`X:\User_Files\Antigravity_Projects\spacedrive_attempt\lib\server\file_server.dart`

Lines to modify: 189-192 (add parsing), 219-224 (add headers param)

---

**This is the ONLY fix needed for video streaming to work!**
