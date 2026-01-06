# Support GOOGLE_APPLICATION_CREDENTIALS Environment Variable

## Overview

Add support for the standard GCP `GOOGLE_APPLICATION_CREDENTIALS` environment
variable to all credential detection mechanisms (container, VM, integration
tests). This enables automatic credential propagation in nested VM scenarios
and simplifies integration test execution.

## Motivation

**Current problem:**

When running nested VMs or integration tests from within a VM, the scripts
ignore the `GOOGLE_APPLICATION_CREDENTIALS` environment variable that's
already set by the outer environment. Users must manually pass credentials via
CLI flags or rely on the default location, which may not exist in nested
scenarios.

**Example failure scenario:**

1. Start outer VM → credentials injected to
   `/etc/google/application_default_credentials.json`
2. Outer VM sets `GOOGLE_APPLICATION_CREDENTIALS=/etc/google/...`
3. User runs `./test-integration.sh --vm` from inside outer VM
4. Script ignores `GOOGLE_APPLICATION_CREDENTIALS`, looks for
   `~/.config/gcloud/application_default_credentials.json`
5. Fails: no credentials found

**Current inconsistencies:**

- Container: Only checks CLI flag → default location
- VM: Only checks custom env var `GCP_CREDENTIALS_PATH` → default location
- Integration tests: Only checks CLI flag → default location
- None respect the standard GCP `GOOGLE_APPLICATION_CREDENTIALS` variable

**Desired outcome:**

All scripts automatically detect credentials from
`GOOGLE_APPLICATION_CREDENTIALS` when set, following standard GCP conventions
and enabling seamless nested execution.

## Design Principles

### 1. Standard GCP Convention

Use `GOOGLE_APPLICATION_CREDENTIALS` as the primary environment variable,
matching the behavior of `gcloud` CLI and all GCP SDKs.

### 2. Explicit Override

CLI flags always take precedence over environment variables, allowing explicit
control when needed.

### 3. Consistent Precedence

All three scripts (container, VM, integration tests) use identical precedence
logic:

```text
1. CLI flag --gcp-credentials <path> (highest priority)
2. Environment variable GOOGLE_APPLICATION_CREDENTIALS
3. Default location ~/.config/gcloud/application_default_credentials.json
```

### 4. No Backward Compatibility

Remove the custom `GCP_CREDENTIALS_PATH` environment variable from `vm/vm-up.sh`
without deprecation warnings or transition period. Users must migrate to
`GOOGLE_APPLICATION_CREDENTIALS`.

**Rationale:** This is an internal development tool with few users. Clean break
is simpler than maintaining multiple env vars.

## Implementation

### 1. Container: `container/start-work`

**Current credential detection (lines 76-79, 154-157):**

```bash
GCP_CREDS_PATH=""  # Empty means auto-detect

# After CLI parsing...
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

**New implementation:**

```bash
# Initialize (line ~79)
GCP_CREDS_PATH=""

# After CLI parsing (after line ~101), apply precedence:
if [[ -z "$GCP_CREDS_PATH" ]]; then  # No --gcp-credentials flag
    if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
    else
        GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
    fi
fi
```

**Logic:**

- If `--gcp-credentials` flag provided, `GCP_CREDS_PATH` already set → use it
- Else if `GOOGLE_APPLICATION_CREDENTIALS` set → use it
- Else fall back to default location

**Testing:**

```bash
# Default
./container/start-work -b test

# Via env var
export GOOGLE_APPLICATION_CREDENTIALS=~/custom.json
./container/start-work -b test

# CLI override
export GOOGLE_APPLICATION_CREDENTIALS=~/from-env.json
./container/start-work --gcp-credentials ~/from-flag.json -b test
```

### 2. VM: `vm/vm-up.sh`

**Current credential detection (lines 12-14):**

```bash
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
GCP_CREDS_PATH="${GCP_CREDENTIALS_PATH:-$GCP_CREDS_DEFAULT}"
```

**New implementation:**

```bash
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"

# Apply precedence: GOOGLE_APPLICATION_CREDENTIALS → default
if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
else
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

**Changes:**

- Remove all references to `GCP_CREDENTIALS_PATH` (breaking change)
- Check `GOOGLE_APPLICATION_CREDENTIALS` before falling back to default
- No CLI flag support for `vm-up.sh` (not needed)

**Testing:**

```bash
# Default
cd vm && ./vm-up.sh

# Via env var
export GOOGLE_APPLICATION_CREDENTIALS=~/custom.json
cd vm && ./vm-up.sh

# From nested VM (automatic)
# GOOGLE_APPLICATION_CREDENTIALS already set by outer VM
cd vm && ./vm-up.sh
```

### 3. Integration Tests: `test-integration.sh`

**Current credential detection (lines 8-10, 114-116):**

```bash
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
GCP_CREDS_PATH=""

# After CLI parsing:
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

**New implementation:**

```bash
# After CLI parsing (around line 116):
if [[ -z "$GCP_CREDS_PATH" ]]; then  # No --gcp-credentials flag
    if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
    else
        GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
    fi
fi
```

**VM test section changes (lines 335-337):**

**Current:**

```bash
if [[ -n "$GCP_CREDS_PATH" ]] && [[ "$GCP_CREDS_PATH" != "$GCP_CREDS_DEFAULT" ]]; then
    export GCP_CREDENTIALS_PATH="$GCP_CREDS_PATH"
fi
```

**New:**

```bash
# Always export GOOGLE_APPLICATION_CREDENTIALS for vm-up.sh
export GOOGLE_APPLICATION_CREDENTIALS="$GCP_CREDS_PATH"
```

**Changes:**

- Add precedence check after CLI parsing
- Export `GOOGLE_APPLICATION_CREDENTIALS` (not `GCP_CREDENTIALS_PATH`) for
  vm-up.sh
- Always export (remove conditional check)

**Testing:**

```bash
# Default
./test-integration.sh --all

# Via env var
export GOOGLE_APPLICATION_CREDENTIALS=~/custom.json
./test-integration.sh --all

# CLI override
export GOOGLE_APPLICATION_CREDENTIALS=~/from-env.json
./test-integration.sh --container --gcp-credentials ~/from-flag.json

# From nested VM (automatic)
./test-integration.sh --vm
```

## Testing Strategy

### Unit-Level Testing (Manual)

**Test 1: Default location**

```bash
# Precondition: Credentials exist at default location
gcloud auth application-default login

# Verify default location
ls -la ~/.config/gcloud/application_default_credentials.json

# Test all scripts
./container/start-work -b test-default
cd vm && ./vm-up.sh && ./vm-connect.sh
./test-integration.sh --all
```

**Expected:** All scripts detect and use default location

**Test 2: GOOGLE_APPLICATION_CREDENTIALS set**

```bash
# Set custom location
export GOOGLE_APPLICATION_CREDENTIALS=~/my-test-creds.json

# Test all scripts
./container/start-work -b test-env
cd vm && ./vm-up.sh && ./vm-connect.sh
./test-integration.sh --all
```

**Expected:** All scripts use `~/my-test-creds.json`

**Test 3: CLI flag overrides environment**

```bash
# Set env var
export GOOGLE_APPLICATION_CREDENTIALS=~/creds-from-env.json

# Test container override
./container/start-work --gcp-credentials ~/creds-from-flag.json -b test-flag

# Test integration override
./test-integration.sh --container --gcp-credentials ~/creds-from-flag.json
```

**Expected:** CLI flag takes precedence, scripts use `~/creds-from-flag.json`

**Test 4: Nested VM scenario (primary use case)**

```bash
# Start outer VM
cd vm && ./vm-up.sh && ./vm-connect.sh

# Inside outer VM, verify env var set
echo $GOOGLE_APPLICATION_CREDENTIALS
# Expected: /etc/google/application_default_credentials.json

# Test nested VM
cd workspace/vm && ./vm-up.sh

# Test integration from nested context
cd workspace && ./test-integration.sh --vm
```

**Expected:** Nested VM and integration tests automatically use credentials
from outer VM

### Integration Test Validation

Run existing integration test suite with all scenarios:

```bash
# Scenario 1: Default
./test-integration.sh --all

# Scenario 2: Custom env var
export GOOGLE_APPLICATION_CREDENTIALS=~/test-creds.json
./test-integration.sh --all

# Scenario 3: From nested VM
# (requires manual VM startup and SSH)
```

**Pass criteria:** All integration tests pass in all scenarios

### Edge Cases

**Empty GOOGLE_APPLICATION_CREDENTIALS:**

```bash
export GOOGLE_APPLICATION_CREDENTIALS=""
./container/start-work -b test
```

**Expected:** Falls back to default location (empty string treated as unset)

**Invalid path in GOOGLE_APPLICATION_CREDENTIALS:**

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/nonexistent/path.json
./container/start-work -b test
```

**Expected:** Script reports "No GCP credentials file found" error

**Both env var and default exist:**

```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/custom.json
# Default also exists at ~/.config/gcloud/...
./container/start-work -b test
```

**Expected:** Uses `~/custom.json` (env var takes precedence)

## Breaking Changes

### vm-up.sh: Remove GCP_CREDENTIALS_PATH

**Impact:**

Scripts or documentation that use `GCP_CREDENTIALS_PATH` will break.

**Migration:**

```bash
# Old usage (will not work)
GCP_CREDENTIALS_PATH=~/my-creds.json ./vm-up.sh

# New usage
GOOGLE_APPLICATION_CREDENTIALS=~/my-creds.json ./vm-up.sh
```

**Affected files:**

- `vm/vm-up.sh` - implementation
- `vm/CLAUDE.md` - documentation (line 183-184)
- `vm/README.md` - documentation (if exists)

**Search for references:**

```bash
grep -r "GCP_CREDENTIALS_PATH" .
```

All references must be updated or removed.

## Documentation Updates

### 1. Root CLAUDE.md

No changes needed - already generic about credential mechanisms.

### 2. container/CLAUDE.md

Update credential injection section (lines 236-248):

**Add after line 226:**

```markdown
### GCP Credential Injection

Credentials are detected in this order:

1. `--gcp-credentials <path>` flag (highest priority)
2. `GOOGLE_APPLICATION_CREDENTIALS` environment variable
3. Default: `~/.config/gcloud/application_default_credentials.json`

For Vertex AI, use credential file injection:

```bash
# Auto-detect from default location
start-work -b feature

# Custom path via flag
start-work -b feature --gcp-credentials ~/my-sa.json

# Custom path via env var
export GOOGLE_APPLICATION_CREDENTIALS=~/my-sa.json
start-work -b feature
```

Credentials are ephemeral and deleted when container exits.
```

### 3. vm/CLAUDE.md

Update security considerations section (lines 181-186):

**Current:**

```markdown
## Security Considerations

- SSH keys auto-generated by Terraform (not in repo, stored locally)
- GCP credentials auto-detected and injected via `vm-up.sh` (not stored in
  repo)
- Constrained sudo access for AI agents
- Root access via SSH key only (no password)
```

**New:**

```markdown
## Security Considerations

- SSH keys auto-generated by Terraform (not in repo, stored locally)
- GCP credentials auto-detected and injected via `vm-up.sh`:
  - Checks `GOOGLE_APPLICATION_CREDENTIALS` env var first
  - Falls back to `~/.config/gcloud/application_default_credentials.json`
  - Never stored in repo
- Constrained sudo access for AI agents
- Root access via SSH key only (no password)
```

### 4. test-integration.sh help text

Update usage documentation (lines 38-56):

**Add after line 48:**

```bash
Credentials are detected in this order:
  1. --gcp-credentials <path> flag (highest priority)
  2. GOOGLE_APPLICATION_CREDENTIALS environment variable
  3. Default: ~/.config/gcloud/application_default_credentials.json
```

### 5. Integration tests design doc

Update credential handling section in
`docs/plans/2026-01-05-integration-tests-design.md` (lines 212-240):

**Add note about precedence:**

```markdown
### Credential Handling

**Philosophy:** Reuse exact same mechanisms as production scripts.

**Credential precedence (all scripts):**

1. CLI flag `--gcp-credentials <path>` (highest priority)
2. Environment variable `GOOGLE_APPLICATION_CREDENTIALS`
3. Default location `~/.config/gcloud/application_default_credentials.json`

**Container approach:**
[existing content...]

**VM approach:**
[existing content...]
```

## Success Criteria

Implementation is successful when:

1. **Container tests pass:**
   - Default location works
   - `GOOGLE_APPLICATION_CREDENTIALS` env var works
   - `--gcp-credentials` flag overrides env var

2. **VM tests pass:**
   - Default location works
   - `GOOGLE_APPLICATION_CREDENTIALS` env var works
   - `GCP_CREDENTIALS_PATH` removed completely

3. **Integration tests pass:**
   - All scenarios in testing strategy pass
   - Nested VM execution works automatically
   - CLI flag override works

4. **Documentation complete:**
   - All docs updated with new precedence
   - Examples show env var usage
   - Migration guide for `GCP_CREDENTIALS_PATH` removal

5. **No regression:**
   - Existing usage with default location continues to work
   - Existing usage with CLI flags continues to work

## Implementation Checklist

- [ ] Update `container/start-work` with precedence logic
- [ ] Update `vm/vm-up.sh` with precedence logic (remove
      `GCP_CREDENTIALS_PATH`)
- [ ] Update `test-integration.sh` with precedence logic
- [ ] Update `test-integration.sh` to export `GOOGLE_APPLICATION_CREDENTIALS`
- [ ] Search and remove all `GCP_CREDENTIALS_PATH` references
- [ ] Update `container/CLAUDE.md` documentation
- [ ] Update `vm/CLAUDE.md` documentation
- [ ] Update `test-integration.sh` usage text
- [ ] Update `docs/plans/2026-01-05-integration-tests-design.md`
- [ ] Test default location scenario
- [ ] Test `GOOGLE_APPLICATION_CREDENTIALS` scenario
- [ ] Test CLI flag override scenario
- [ ] Test nested VM scenario
- [ ] Run full integration test suite
- [ ] Commit changes with design doc
