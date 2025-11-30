# Code Editing Best Practices

## 🚨 CRITICAL RULES - ALWAYS FOLLOW

### Before Every Edit:
1. **View the exact lines** you're about to edit using `view_file`
2. **Copy the EXACT text** including all whitespace
3. **Verify line numbers** match what you expect
4. **Make small, focused changes** - avoid replacing 100+ lines at once

### File Size Rules:
- **< 200 lines:** Safe to edit larger chunks
- **200-500 lines:** Edit 20-30 lines at a time maximum
- **500-1000 lines:** Edit 10-20 lines at a time ONLY
- **> 1000 lines:** View and edit 5-10 lines at a time, NEVER MORE

### When Editing:
- ✅ DO: Replace 5-20 lines at a time
- ✅ DO: Copy target content character-for-character
- ✅ DO: Include leading whitespace in target content
- ✅ DO: Use `view_file` to verify BEFORE editing
- ❌ DON'T: Try to replace entire methods >50 lines
- ❌ DON'T: Assume whitespace - verify it
- ❌ DON'T: Edit multiple files in parallel if they depend on each other

## 🔒 Critical Files (Handle with Extreme Care)

### `remote_file_provider.dart` (980+ lines)
- **Rule:** Edit MAX 10 lines at a time
- **Strategy:** View, edit small section, test, commit
- **If corrupted:** `git checkout lib/client/remote_file_provider.dart`

### `file_card_widget.dart` (325 lines)
- **Rule:** Edit MAX 20 lines at a time
- **Strategy:** Always verify TargetContent is unique

### Large UI files (>300 lines)
- **Rule:** View method first with `view_code_item`
- **Strategy:** Replace single methods only

## 💾 Commit Strategy - MANDATORY

### After Each Feature:
```bash
git add -A
git commit -m "Descriptive message"
```

### Commit Frequency:
- **Every working feature** - Even small ones
- **Before risky edits** - To any file >500 lines
- **After testing** - When something works

### Recovery:
```bash
# Revert single file
git checkout <filename>

# Check what changed
git diff

# See recent commits
git log --oneline -10
```

## 📋 File-Specific Guidelines

### Already Modularized (Safe):
- `lib/server/file_server.dart` (252 lines) - Now clean and maintainable
- `lib/server/request_handlers/*` - Focused, single-responsibility
- `lib/server/utils/*` - Small helper files

### Refactoring Complete:
Server: 809 lines → 6 focused modules ✅

## 🎯 Editing Workflow

1. **Plan:** Know exactly what you're changing
2. **View:** Use `view_file` on exact line range
3. **Copy:** Copy TargetContent with ALL whitespace
4. **Edit:** Make the small, focused change
5. **Verify:** Check the diff in response
6. **Test:** Run or build to verify
7. **Commit:** Save working state

## ⚠️ Warning Signs

If you see these, STOP and commit first:
- Editing >50 lines in one replace
- Multiple edits to same file in parallel
- Uncertain about TargetContent uniqueness
- File >1000 lines

## 🛡️ Safety Measures Implemented

1. ✅ Frequent git commits
2. ✅ Small, focused files (server refactored)
3. ✅ Documentation of file sizes
4. ✅ This guidelines document

## 📊 Current Safe State

Last commit: "Added getStreamBytes method for image viewing over relay"
- 6 commits ahead of origin
- All files compile
- No uncommitted changes
- Safe to continue development

**REMEMBER:** Small edits, frequent commits, always verify! 🎯
