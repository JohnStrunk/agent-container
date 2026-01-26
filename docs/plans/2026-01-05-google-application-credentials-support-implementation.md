# GOOGLE_APPLICATION_CREDENTIALS Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Add support for the standard GCP `GOOGLE_APPLICATION_CREDENTIALS`
environment variable to all scripts (container, VM, integration tests) with
consistent precedence ordering.

**Architecture:** Update credential detection logic in three shell scripts to
check CLI flags first, then `GOOGLE_APPLICATION_CREDENTIALS` env var, then
default location. Remove custom `GCP_CREDENTIALS_PATH` env var.

**Tech Stack:** Bash shell scripts, Git

---

## Task 1: Update container/agent-container with precedence logic

**Files:**
- Modify: `container/agent-container:154-157`

**Step 1: Locate current credential detection code**

Open `container/agent-container` and find lines 154-157:

```bash
# Auto-detect if not specified
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

**Step 2: Replace with precedence logic**

Replace lines 154-157 with:

```bash
# Apply credential precedence: CLI flag → env var → default
if [[ -z "$GCP_CREDS_PATH" ]]; then  # No --gcp-credentials flag
    if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
    else
        GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
    fi
fi
```

**Step 3: Verify syntax**

Run shellcheck to verify no syntax errors:

```bash
shellcheck container/agent-container
```

Expected: No errors (existing warnings are fine)

**Step 4: Test default location behavior**

```bash
# Ensure GCP_CREDS_PATH and GOOGLE_APPLICATION_CREDENTIALS are unset
unset GCP_CREDS_PATH
unset GOOGLE_APPLICATION_CREDENTIALS

# Add debug output temporarily
echo "Testing: GCP_CREDS_PATH should use default"
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
```

Expected: Logic falls through to default location

**Step 5: Commit**

```bash
git add container/agent-container
git commit -m "feat(container): add GOOGLE_APPLICATION_CREDENTIALS precedence

Update credential detection to check GOOGLE_APPLICATION_CREDENTIALS
environment variable before falling back to default location.

Precedence: CLI flag → GOOGLE_APPLICATION_CREDENTIALS → default"
```

---

## Task 2: Update vm/vm-up.sh with precedence logic

**Files:**
- Modify: `vm/vm-up.sh:12-14`

**Step 1: Locate current credential detection code**

Open `vm/vm-up.sh` and find lines 12-14:

```bash
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
GCP_CREDS_PATH="${GCP_CREDENTIALS_PATH:-$GCP_CREDS_DEFAULT}"
```

**Step 2: Replace with precedence logic**

Replace line 14 with:

```bash
# Apply credential precedence: GOOGLE_APPLICATION_CREDENTIALS → default
if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
else
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

Result should look like:

```bash
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"

# Apply credential precedence: GOOGLE_APPLICATION_CREDENTIALS → default
if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
else
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

**Step 3: Verify syntax**

```bash
shellcheck vm/vm-up.sh
```

Expected: No errors (existing warnings are fine)

**Step 4: Commit**

```bash
git add vm/vm-up.sh
git commit -m "feat(vm): add GOOGLE_APPLICATION_CREDENTIALS precedence

Replace custom GCP_CREDENTIALS_PATH with standard
GOOGLE_APPLICATION_CREDENTIALS environment variable.

BREAKING CHANGE: GCP_CREDENTIALS_PATH no longer supported.
Use GOOGLE_APPLICATION_CREDENTIALS instead.

Precedence: GOOGLE_APPLICATION_CREDENTIALS → default"
```

---

## Task 3: Update test-integration.sh credential precedence

**Files:**
- Modify: `test-integration.sh:114-116`

**Step 1: Locate current credential detection code**

Open `test-integration.sh` and find lines 114-116:

```bash
# Set default credentials path if not provided
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi
```

**Step 2: Replace with precedence logic**

Replace lines 114-116 with:

```bash
# Apply credential precedence: CLI flag → env var → default
if [[ -z "$GCP_CREDS_PATH" ]]; then  # No --gcp-credentials flag
    if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
    else
        GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
    fi
fi
```

**Step 3: Verify syntax**

```bash
shellcheck test-integration.sh
```

Expected: No errors (existing warnings are fine)

**Step 4: Commit**

```bash
git add test-integration.sh
git commit -m "feat(integration): add GOOGLE_APPLICATION_CREDENTIALS precedence

Update credential detection to check GOOGLE_APPLICATION_CREDENTIALS
before falling back to default location.

Precedence: CLI flag → GOOGLE_APPLICATION_CREDENTIALS → default"
```

---

## Task 4: Update test-integration.sh VM test export

**Files:**
- Modify: `test-integration.sh:335-337`

**Step 1: Locate VM test credential export code**

Open `test-integration.sh` and find lines 335-337 in the `test_vm()` function:

```bash
# Set GCP credentials path if custom
if [[ -n "$GCP_CREDS_PATH" ]] && [[ "$GCP_CREDS_PATH" != "$GCP_CREDS_DEFAULT" ]]; then
    export GCP_CREDENTIALS_PATH="$GCP_CREDS_PATH"
fi
```

**Step 2: Replace with unconditional GOOGLE_APPLICATION_CREDENTIALS export**

Replace lines 335-337 with:

```bash
# Export GOOGLE_APPLICATION_CREDENTIALS for vm-up.sh
export GOOGLE_APPLICATION_CREDENTIALS="$GCP_CREDS_PATH"
```

**Step 3: Verify syntax**

```bash
shellcheck test-integration.sh
```

Expected: No errors

**Step 4: Commit**

```bash
git add test-integration.sh
git commit -m "feat(integration): export GOOGLE_APPLICATION_CREDENTIALS to VM test

Replace GCP_CREDENTIALS_PATH export with standard
GOOGLE_APPLICATION_CREDENTIALS to match vm-up.sh expectations.

Always export (no conditional check needed)."
```

---

## Task 5: Search and verify GCP_CREDENTIALS_PATH removal

**Files:**
- Verify: All files in repository

**Step 1: Search for remaining GCP_CREDENTIALS_PATH references**

```bash
grep -r "GCP_CREDENTIALS_PATH" . --exclude-dir=.git
```

Expected output: Should only appear in:
- Design document (docs/plans/2026-01-05-google-application-credentials-support.md)
- This implementation plan

**Step 2: Verify no code references remain**

```bash
grep -r "GCP_CREDENTIALS_PATH" . --exclude-dir=.git \
  --exclude-dir=docs/plans | grep -v "Binary file"
```

Expected: No output (all code references removed)

**Step 3: Document verification**

No commit needed - this is a verification step.

---

## Task 6: Update container/CLAUDE.md documentation

**Files:**
- Modify: `container/CLAUDE.md:236-248`

**Step 1: Read current credential injection section**

Open `container/CLAUDE.md` and locate the "GCP Credential Injection" section
around lines 236-248.

**Step 2: Add precedence documentation**

After line 226 (before the existing credential section), add:

```markdown
### GCP Credential Injection

Credentials are detected in this order:

1. `--gcp-credentials <path>` flag (highest priority)
2. `GOOGLE_APPLICATION_CREDENTIALS` environment variable
3. Default: `~/.config/gcloud/application_default_credentials.json`

Examples:

```bash
# Auto-detect from default location
agent-container -b feature

# Custom path via flag
agent-container -b feature --gcp-credentials ~/my-sa.json

# Custom path via env var
export GOOGLE_APPLICATION_CREDENTIALS=~/my-sa.json
agent-container -b feature
```

Credentials are ephemeral and deleted when container exits.
```

**Step 3: Update existing section (lines 236-248)**

Replace the existing "GCP Credential Injection" section (lines 236-248) with
the content from Step 2. The old section says:

```markdown
For Vertex AI, use credential file injection instead of mounting:

```bash
# Auto-detect from default location
agent-container -b feature

# Custom path
agent-container -b feature --gcp-credentials ~/my-sa.json
```

Credentials are ephemeral and deleted when container exits.
```

**Step 4: Run pre-commit checks**

```bash
pre-commit run --files container/CLAUDE.md
```

Expected: All checks pass (or only markdownlint warnings about line length)

**Step 5: Commit**

```bash
git add container/CLAUDE.md
git commit -m "docs(container): document GOOGLE_APPLICATION_CREDENTIALS precedence

Add credential precedence ordering and example using
GOOGLE_APPLICATION_CREDENTIALS environment variable."
```

---

## Task 7: Update vm/CLAUDE.md documentation

**Files:**
- Modify: `vm/CLAUDE.md:181-186`

**Step 1: Locate Security Considerations section**

Open `vm/CLAUDE.md` and find the "Security Considerations" section at lines
181-186:

```markdown
## Security Considerations

- SSH keys auto-generated by Terraform (not in repo, stored locally)
- GCP credentials auto-detected and injected via `vm-up.sh` (not stored in
  repo)
- Constrained sudo access for AI agents
- Root access via SSH key only (no password)
```

**Step 2: Update GCP credentials bullet point**

Replace the second bullet point with:

```markdown
- GCP credentials auto-detected and injected via `vm-up.sh`:
  - Checks `GOOGLE_APPLICATION_CREDENTIALS` env var first
  - Falls back to `~/.config/gcloud/application_default_credentials.json`
  - Never stored in repo
```

Result should look like:

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

**Step 3: Run pre-commit checks**

```bash
pre-commit run --files vm/CLAUDE.md
```

Expected: All checks pass

**Step 4: Commit**

```bash
git add vm/CLAUDE.md
git commit -m "docs(vm): document GOOGLE_APPLICATION_CREDENTIALS support

Update security section to document credential precedence and
GOOGLE_APPLICATION_CREDENTIALS environment variable support."
```

---

## Task 8: Update test-integration.sh usage documentation

**Files:**
- Modify: `test-integration.sh:38-56`

**Step 1: Locate usage() function**

Open `test-integration.sh` and find the `usage()` function starting at line 37.

**Step 2: Add credential precedence to usage text**

After line 48 (after the `--gcp-credentials` option description), add:

```bash
Credentials are detected in this order:
  1. --gcp-credentials <path> flag (highest priority)
  2. GOOGLE_APPLICATION_CREDENTIALS environment variable
  3. Default: ~/.config/gcloud/application_default_credentials.json

```

The section should look like:

```bash
Options:
  --container                Run container approach test
  --vm                       Run VM approach test
  --all                      Run both tests sequentially
  --gcp-credentials <path>   Path to GCP credentials JSON file
                            (default: ~/.config/gcloud/application_default_credentials.json)
  --rebuild                  Force rebuild (bypass Docker cache)
  -h, --help                 Show this help

Credentials are detected in this order:
  1. --gcp-credentials <path> flag (highest priority)
  2. GOOGLE_APPLICATION_CREDENTIALS environment variable
  3. Default: ~/.config/gcloud/application_default_credentials.json

Examples:
```

**Step 3: Verify syntax**

```bash
shellcheck test-integration.sh
```

Expected: No errors

**Step 4: Test usage output**

```bash
./test-integration.sh --help
```

Expected: Shows updated usage text with credential precedence

**Step 5: Commit**

```bash
git add test-integration.sh
git commit -m "docs(integration): document credential precedence in usage

Add credential detection order to --help output showing
GOOGLE_APPLICATION_CREDENTIALS support."
```

---

## Task 9: Update integration tests design document

**Files:**
- Modify: `docs/plans/2026-01-05-integration-tests-design.md:212-240`

**Step 1: Locate Credential Handling section**

Open `docs/plans/2026-01-05-integration-tests-design.md` and find the
"Credential Handling" section around line 212.

**Step 2: Add precedence note at top of section**

After the section header "### Credential Handling" and the philosophy line,
add:

```markdown
**Credential precedence (all scripts):**

1. CLI flag `--gcp-credentials <path>` (highest priority)
2. Environment variable `GOOGLE_APPLICATION_CREDENTIALS`
3. Default location `~/.config/gcloud/application_default_credentials.json`

```

The section should start like:

```markdown
### Credential Handling

**Philosophy:** Reuse exact same mechanisms as production scripts.

**Credential precedence (all scripts):**

1. CLI flag `--gcp-credentials <path>` (highest priority)
2. Environment variable `GOOGLE_APPLICATION_CREDENTIALS`
3. Default location `~/.config/gcloud/application_default_credentials.json`

**Container approach:**
```

**Step 3: Run pre-commit checks**

```bash
pre-commit run --files docs/plans/2026-01-05-integration-tests-design.md
```

Expected: All checks pass

**Step 4: Commit**

```bash
git add docs/plans/2026-01-05-integration-tests-design.md
git commit -m "docs: add credential precedence to integration tests design

Document GOOGLE_APPLICATION_CREDENTIALS support in integration
tests design document."
```

---

## Task 10: Run pre-commit on all modified files

**Files:**
- Verify: All modified shell scripts and markdown files

**Step 1: Run pre-commit on all changed files**

```bash
pre-commit run --files \
  container/agent-container \
  vm/vm-up.sh \
  test-integration.sh \
  container/CLAUDE.md \
  vm/CLAUDE.md \
  docs/plans/2026-01-05-integration-tests-design.md
```

Expected: All checks pass

**Step 2: Fix any issues**

If pre-commit reports issues, fix them and re-run until all pass.

**Step 3: Commit fixes if needed**

```bash
# Only if pre-commit made changes
git add -u
git commit -m "style: apply pre-commit fixes"
```

---

## Task 11: Manual validation - Default location

**Files:**
- Test: `container/agent-container`, `vm/vm-up.sh`, `test-integration.sh`

**Step 1: Ensure default credentials exist**

```bash
ls -la ~/.config/gcloud/application_default_credentials.json
```

Expected: File exists (if not, run `gcloud auth application-default login`)

**Step 2: Test with clean environment**

```bash
# Ensure no env vars set
unset GOOGLE_APPLICATION_CREDENTIALS
unset GCP_CREDENTIALS_PATH

# Test container script detects default
./container/agent-container --help | grep -i "gcp"
```

Expected: Help text shows credential injection options

**Step 3: Test VM script**

```bash
# Check vm-up.sh would use default
cd vm
unset GOOGLE_APPLICATION_CREDENTIALS
grep -A5 "GCP_CREDS_PATH" vm-up.sh
cd ..
```

Expected: Code shows GOOGLE_APPLICATION_CREDENTIALS check

**Step 4: Document validation**

Record validation results (no commit needed - this is testing phase).

---

## Task 12: Manual validation - GOOGLE_APPLICATION_CREDENTIALS

**Files:**
- Test: `container/agent-container`, `vm/vm-up.sh`, `test-integration.sh`

**Step 1: Set custom credentials path**

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/test-custom-creds.json"
```

**Step 2: Create dummy credentials file (for testing path detection)**

```bash
echo '{"type": "service_account", "project_id": "test"}' > ~/test-custom-creds.json
```

**Step 3: Verify environment variable is honored**

Check that scripts would use the env var:

```bash
# Test container script
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
GCP_CREDS_PATH=""
if [[ -z "$GCP_CREDS_PATH" ]]; then
    if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
    else
        GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
    fi
fi
echo "Would use: $GCP_CREDS_PATH"
```

Expected: Shows `~/test-custom-creds.json`

**Step 4: Clean up test file**

```bash
rm ~/test-custom-creds.json
unset GOOGLE_APPLICATION_CREDENTIALS
```

**Step 5: Document validation**

Record validation results (no commit needed).

---

## Task 13: Manual validation - CLI flag precedence

**Files:**
- Test: `container/agent-container`, `test-integration.sh`

**Step 1: Set environment variable**

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/from-env.json"
```

**Step 2: Test container script with CLI override**

```bash
# Verify help shows --gcp-credentials flag
./container/agent-container --help | grep -A2 "gcp-credentials"
```

Expected: Shows `--gcp-credentials <path>` flag

**Step 3: Verify flag would override env var**

The `--gcp-credentials` flag sets `GCP_CREDS_PATH` during argument parsing,
so the env var check `if [[ -z "$GCP_CREDS_PATH" ]]` would be false and skip
the env var logic.

**Step 4: Test integration script**

```bash
./test-integration.sh --help | grep -A2 "gcp-credentials"
```

Expected: Shows credential precedence documentation

**Step 5: Clean up**

```bash
unset GOOGLE_APPLICATION_CREDENTIALS
```

**Step 6: Document validation**

Record validation results (no commit needed).

---

## Task 14: Verify no GCP_CREDENTIALS_PATH references

**Files:**
- Verify: All repository files

**Step 1: Final search for old env var**

```bash
grep -r "GCP_CREDENTIALS_PATH" . \
  --exclude-dir=.git \
  --exclude-dir=docs/plans \
  2>/dev/null
```

Expected: No output (all removed from code)

**Step 2: Verify only in design docs**

```bash
grep -r "GCP_CREDENTIALS_PATH" docs/plans/ 2>/dev/null | wc -l
```

Expected: Only references in design and implementation plan docs

**Step 3: Document verification**

Verification complete (no commit needed).

---

## Task 15: Final commit and summary

**Files:**
- Verify: Git commit history

**Step 1: Review all commits**

```bash
git log --oneline --decorate -15
```

Expected: Shows all commits from this implementation:
- feat(container): add GOOGLE_APPLICATION_CREDENTIALS precedence
- feat(vm): add GOOGLE_APPLICATION_CREDENTIALS precedence
- feat(integration): add GOOGLE_APPLICATION_CREDENTIALS precedence
- feat(integration): export GOOGLE_APPLICATION_CREDENTIALS to VM test
- docs(container): document GOOGLE_APPLICATION_CREDENTIALS precedence
- docs(vm): document GOOGLE_APPLICATION_CREDENTIALS support
- docs(integration): document credential precedence in usage
- docs: add credential precedence to integration tests design

**Step 2: Verify working tree is clean**

```bash
git status
```

Expected: Clean working tree (all changes committed)

**Step 3: Create summary of changes**

List of modified files:
- `container/agent-container`
- `vm/vm-up.sh`
- `test-integration.sh`
- `container/CLAUDE.md`
- `vm/CLAUDE.md`
- `docs/plans/2026-01-05-integration-tests-design.md`

**Step 4: Tag implementation completion**

```bash
git tag -a google-app-creds-v1 -m "Implement GOOGLE_APPLICATION_CREDENTIALS support"
```

Expected: Tag created

---

## Success Criteria Checklist

Verify all criteria from design document:

- [ ] Container script checks CLI flag → env var → default
- [ ] VM script checks env var → default
- [ ] Integration tests check CLI flag → env var → default
- [ ] Integration tests export GOOGLE_APPLICATION_CREDENTIALS to VM
- [ ] No GCP_CREDENTIALS_PATH references in code
- [ ] container/CLAUDE.md documents precedence with examples
- [ ] vm/CLAUDE.md documents GOOGLE_APPLICATION_CREDENTIALS
- [ ] test-integration.sh usage shows precedence
- [ ] Integration tests design doc updated
- [ ] All commits follow conventional commit format
- [ ] All pre-commit checks pass
- [ ] Manual validation completed for all three scenarios

---

## Next Steps (Post-Implementation)

After completing this plan:

1. **Integration Testing**: Run full integration test suite:
   ```bash
   ./test-integration.sh --all
   ```

2. **Nested VM Testing**: Test in nested VM scenario (requires VM setup)

3. **Update README.md**: Add migration guide for GCP_CREDENTIALS_PATH removal
   (if README documents credential usage)

4. **Announce breaking change**: Document GCP_CREDENTIALS_PATH removal in
   changelog or release notes

---

## Rollback Plan

If issues are discovered:

```bash
# Find the commit before first change
git log --oneline | grep "feat(container): add GOOGLE"

# Reset to commit before implementation
git reset --hard <commit-before-changes>

# Force push if already pushed (use with caution)
# git push --force-with-lease
```
