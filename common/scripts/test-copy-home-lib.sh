#!/bin/sh
# Unit tests for copy-home-lib.sh
# POSIX sh compatible.
# shellcheck disable=SC3043  # local is widely supported and explicitly allowed

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test state
TESTS_PASSED=0
TESTS_FAILED=0
TEMP_DIR=""
FAKE_HOME=""
DEST_DIR=""

# Cleanup function
# shellcheck disable=SC2317  # Function is called via trap
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Setup function - creates fake home directory structure
setup_fake_home() {
    TEMP_DIR="$(mktemp -d)"
    FAKE_HOME="$TEMP_DIR/fake_home"
    DEST_DIR="$TEMP_DIR/dest"

    mkdir -p "$FAKE_HOME/.claude"
    mkdir -p "$FAKE_HOME/.config/opencode"
    mkdir -p "$FAKE_HOME/.config/other"
    mkdir -p "$FAKE_HOME/.gemini"

    echo "settings content" > "$FAKE_HOME/.claude/settings.json"
    echo "statusline content" > "$FAKE_HOME/.claude/statusline-command.sh"
    echo "claude json content" > "$FAKE_HOME/.claude.json"
    echo "opencode content" > "$FAKE_HOME/.config/opencode/opencode.jsonc"
    echo "other content" > "$FAKE_HOME/.config/other/other.conf"
    echo "gemini content" > "$FAKE_HOME/.gemini/settings.json"
    echo "gitconfig content" > "$FAKE_HOME/.gitconfig"
    echo "unrelated content" > "$FAKE_HOME/.unrelated-file"

    mkdir -p "$DEST_DIR"
}

# Reset destination directory between tests
reset_dest() {
    rm -rf "$DEST_DIR"
    mkdir -p "$DEST_DIR"
}

# Test result reporting
pass_test() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC}: %s\n" "$test_name"
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC}: %s - %s\n" "$test_name" "$reason"
}

# Source the library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/copy-home-lib.sh"

# Test 1: Basic directory copy
test_basic_directory_copy() {
    local test_name="basic directory copy"
    local spec_file="$TEMP_DIR/spec1.txt"

    reset_dest
    echo ".claude" > "$spec_file"

    copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"

    if [ -f "$DEST_DIR/.claude/settings.json" ] && [ -f "$DEST_DIR/.claude/statusline-command.sh" ]; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "expected files not found in destination"
    fi
}

# Test 2: Basic file copy
test_basic_file_copy() {
    local test_name="basic file copy"
    local spec_file="$TEMP_DIR/spec2.txt"

    reset_dest
    echo ".claude.json" > "$spec_file"

    copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"

    if [ -f "$DEST_DIR/.claude.json" ]; then
        pass_test "$test_name"
    else
        fail_test "$test_name" ".claude.json not found in destination"
    fi
}

# Test 3: Nested directory copy
test_nested_directory_copy() {
    local test_name="nested directory copy"
    local spec_file="$TEMP_DIR/spec3.txt"

    reset_dest
    echo ".config/opencode" > "$spec_file"

    copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"

    if [ -f "$DEST_DIR/.config/opencode/opencode.jsonc" ] && [ ! -d "$DEST_DIR/.config/other" ]; then
        pass_test "$test_name"
    else
        if [ ! -f "$DEST_DIR/.config/opencode/opencode.jsonc" ]; then
            fail_test "$test_name" "opencode.jsonc not found"
        else
            fail_test "$test_name" "other directory should not exist"
        fi
    fi
}

# Test 4: Glob expansion
test_glob_expansion() {
    local test_name="glob expansion"
    local spec_file="$TEMP_DIR/spec4.txt"

    reset_dest
    echo ".config/o*" > "$spec_file"

    copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"

    if [ -f "$DEST_DIR/.config/opencode/opencode.jsonc" ] && [ -f "$DEST_DIR/.config/other/other.conf" ]; then
        pass_test "$test_name"
    else
        if [ ! -f "$DEST_DIR/.config/opencode/opencode.jsonc" ]; then
            fail_test "$test_name" "opencode/opencode.jsonc not found"
        else
            fail_test "$test_name" "other/other.conf not found"
        fi
    fi
}

# Test 5: Exclusion
test_exclusion() {
    local test_name="exclusion"
    local spec_file="$TEMP_DIR/spec5.txt"

    reset_dest
    cat > "$spec_file" <<EOF
.config
!.config/other
EOF

    copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"

    if [ -f "$DEST_DIR/.config/opencode/opencode.jsonc" ] && [ ! -d "$DEST_DIR/.config/other" ]; then
        pass_test "$test_name"
    else
        if [ ! -f "$DEST_DIR/.config/opencode/opencode.jsonc" ]; then
            fail_test "$test_name" "opencode.jsonc not found"
        else
            fail_test "$test_name" "other directory should be excluded"
        fi
    fi
}

# Test 6: Missing path
test_missing_path() {
    local test_name="missing path"
    local spec_file="$TEMP_DIR/spec6.txt"

    reset_dest
    echo ".nonexistent" > "$spec_file"

    # Should not fail
    if copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"; then
        # Check that dest is empty (only has . directory)
        local file_count
        file_count=$(find "$DEST_DIR" -type f | wc -l)
        if [ "$file_count" -eq 0 ]; then
            pass_test "$test_name"
        else
            fail_test "$test_name" "destination should be empty but has $file_count files"
        fi
    else
        fail_test "$test_name" "script should exit 0 for missing paths"
    fi
}

# Test 7: Comments and blank lines
test_comments_and_blank_lines() {
    local test_name="comments and blank lines"
    local spec_file="$TEMP_DIR/spec7.txt"

    reset_dest
    cat > "$spec_file" <<EOF
# This is a comment

.claude.json
EOF

    copy_home_files "$spec_file" "$FAKE_HOME" "$DEST_DIR"

    if [ -f "$DEST_DIR/.claude.json" ]; then
        # Make sure only .claude.json was copied (no other files from comments)
        local file_count
        file_count=$(find "$DEST_DIR" -type f | wc -l)
        if [ "$file_count" -eq 1 ]; then
            pass_test "$test_name"
        else
            fail_test "$test_name" "expected 1 file, found $file_count"
        fi
    else
        fail_test "$test_name" ".claude.json not found"
    fi
}

# Run all tests
echo "Setting up test environment..."
setup_fake_home

echo "Running tests..."
echo ""

test_basic_directory_copy
test_basic_file_copy
test_nested_directory_copy
test_glob_expansion
test_exclusion
test_missing_path
test_comments_and_blank_lines

echo ""
echo "=========================================="
echo "Test Results:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "=========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
