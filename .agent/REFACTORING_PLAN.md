# RemoteFileProvider Refactoring Plan

## Goal
Split `remote_file_provider.dart` (969 lines) into 4-5 focused modules to prevent file corruption and improve maintainability.

## Current Structure
- **Total:** 969 lines
- **Methods:** 37 functions
- **Complexity:** High - handles discovery, files, tags, relay, operations

## Proposed Modules

### ✅ 1. ConnectionManager (210 lines) - DONE
**Location:** `lib/client/connection_manager.dart`
**Responsibilities:**
- Network service discovery
- Local network connection  
- Relay connection
- Passphrase management
- Encryption key derivation

**Methods:**
- `startDiscovery()`
- `stopDiscovery()`  
- `connect ToService()`
- `connectViaRelay()`
- `savePassphrase()` / `getSavedPassphrase()`

### 🔄 2. FileOperationsManager (~150 lines)
**Location:** `lib/client/file_operations_manager.dart`
**Responsibilities:**
- File/folder CRUD operations
- File upload/download
- Move, rename, delete

**Methods:**
- `createFolder()`
- `createTextFile()`
- `deleteItem()`
- `renameItem()`
- `moveItem()`
- `uploadFile()`

### 🔄 3. TagManager (~250 lines)
**Location:** `lib/client/tag_manager.dart`
**Responsibilities:**
- Tag database operations
- Hash computation
- Tag sync (local ↔ server)
- Tag caching

**Methods:**
- `addTagToFile()`
- `removeTagFromFile()`
- `updateFileTags()`
- `ensureFileHasHash()`
- `_syncTagsToServer()`
- `_syncTagsFromServer()`

### 🔄 4. FileBrowserManager (~250 lines)
**Location:** `lib/client/file_browser_manager.dart`
**Responsibilities:**
- File listing
- Thumbnail/stream URLs
- Relay file fetching
- Response parsing

**Methods:**
- `fetchFiles()`
- `_fetchViaRelay()`
- `getStreamUrl()`
- `getThumbnailUrl()`
- `getThumbnailBytes()`
- `getStreamBytes()`

### 🔄 5. RemoteFileProvider (~150 lines) - Coordinator
**Location:** `lib/client/remote_file_provider.dart`
**Responsibilities:**
- ChangeNotifier implementation
- Coordinate between modules
- Expose unified API
- State management

**Composition:**
```dart
class RemoteFileProvider with ChangeNotifier {
  final ConnectionManager _connection;
  final FileOperationsManager _operations;
  final TagManager _tags;
  final FileBrowserManager _browser;
  
  // Delegate methods to appropriate managers
}
```

## Benefits

### Before:
- ❌ 969 lines - hard to edit safely
- ❌ High corruption risk
- ❌ Multiple responsibilities
- ❌ Difficult to test

### After:
- ✅ 5 files, ~150-250 lines each
- ✅ Minimal corruption risk
- ✅ Single responsibility
- ✅ Easy to test and maintain
- ✅ Clear separation of concerns

## Migration Strategy

1. ✅ **Create ConnectionManager** - Extract connection logic
2. **Create other managers** - Extract remaining logic
3. **Update RemoteFileProvider** - Make it a coordinator
4. **Update all imports** - Fix references throughout app
5. **Test thoroughly** - Ensure nothing broke
6. **Commit frequently** - After each working state

## Current Status

✅ ConnectionManager created (210 lines)
⏸️ Waiting for user approval to continue

## Estimated Time
Full refactoring: 30-45 minutes with careful testing

## Risk
Medium - requires updating many imports, but can be done incrementally with git safety net.
