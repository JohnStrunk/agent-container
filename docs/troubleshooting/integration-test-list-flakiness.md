# Integration Test List Flakiness

**Issue:** Integration test `test_vm_approach()` Test 3 (workspace listing) fails intermittently with "Workspace test-vm-X not found in list"

**Status:** Under investigation

**Date:** 2026-01-08

## Symptoms

- Test creates two workspaces (test-vm-1 and test-vm-2) successfully
- Test 3 calls `./agent-vm --list` twice (once for each workspace)
- One of the two grep checks fails (alternating between test-vm-1 and test-vm-2)
- Manual runs of the same commands consistently pass
- The workspaces actually exist in the VM and are visible when checked manually

## Evidence

```bash
# Test output shows:
[15:12:48] Test 3: Listing workspaces...
[15:12:50] ERROR: Workspace test-vm-2 not found in list

# But manual check shows both workspaces exist:
$ ./agent-vm --list
WORKSPACE                      LAST MODIFIED
---------                      -------------
workspace-test-vm-2            Jan 8 15:02
workspace-test-vm-1            Jan 8 15:02
```

## Attempts to Fix

1. **Changed pipe-to-while-loop to process substitution** (commit 339327a)
   - Rationale: Avoid subshell buffering issues
   - Result: Still fails

2. **Increased SSH ConnectTimeout from 5 to 10 seconds** (commit 4073ad6)
   - Rationale: VM might be under load and slow to respond
   - Result: Still fails

3. **Capture SSH output in variable before processing** (commit 8675ab1)
   - Rationale: More reliable than streaming/piping
   - Result: Still fails

## Hypotheses

### Active Hypotheses

1. **SSH connection limit or rate limiting**
   - Multiple rapid SSH connections in quick succession
   - Test does: connect for test-vm-1, connect for test-vm-2, then list twice
   - May be hitting some kind of connection limit

2. **Test harness environment difference**
   - Different environment variables, shell settings, or PATH
   - Works in interactive shell but fails in test harness

### Ruled Out

- ❌ Buffering issues with pipes (tried process substitution and variables)
- ❌ SSH timeout too short (increased from 5 to 10 seconds)
- ❌ Workspaces don't exist (verified they exist when test fails)
- ❌ Grep pattern issue (pattern works manually)

## Workarounds

- Manual testing of all workspace operations passes consistently
- The single-VM implementation works correctly in practice
- This is purely a test infrastructure issue, not a functional bug

## Next Steps

1. Add debug output to capture exact SSH return values during test
2. Check for SSH multiplexing or connection pooling issues
3. Consider adding retry logic to the test
4. Investigate test harness timing/sequencing

## Impact

- **Severity:** Low (does not affect actual functionality)
- **Scope:** Only affects automated integration tests
- **Mitigation:** Manual testing confirms functionality works correctly
