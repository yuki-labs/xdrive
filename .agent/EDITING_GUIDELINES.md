# Code Editing Best Practices

## To Prevent File Corruption

### Before Every Edit:
1. **View the exact lines** you're about to edit using `view_file`
2. **Copy the EXACT text** including all whitespace
3. **Verify line numbers** match what you expect
4. **Make small, focused changes** - avoid replacing 100+ lines at once

### When Editing:
- ✅ DO: Replace 5-20 lines at a time
- ✅ DO: Copy target content character-for-character
- ✅ DO: Include leading whitespace in target content
- ❌ DON'T: Try to replace entire methods >50 lines
- ❌ DON'T: Assume whitespace - verify it
- ❌ DON'T: Edit multiple files in parallel if they depend on each other

### After Refactoring (Already Done):
- file_server.dart: 809 lines → 252 lines ✅
- Split into focused modules:
  - `request_handlers/` - HTTP request handling
  - `utils/` - Helper functions
  
### Recovery:
If a file gets corrupted:
```bash
git checkout <filename>  # Revert to last commit
```

### Git Strategy:
```bash
# Commit after each successful feature
git add .
git commit -m "Descriptive message"

# Before major refactoring
git checkout -b feature-name
```

## File-Specific Notes

### Large Files to Be Careful With:
- `lib/client/remote_file_provider.dart` (900+ lines) - Consider splitting further
- Any file >500 lines - View small sections, edit incrementally

### Already Modularized:
- `lib/server/file_server.dart` - Now clean and maintainable
- `lib/server/request_handlers/*` - Focused, single-responsibility modules
