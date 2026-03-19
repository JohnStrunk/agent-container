#!/bin/sh
# Library for copying home directory files based on a specification file.
# POSIX sh compatible.
# shellcheck disable=SC3043  # local is widely supported and explicitly allowed

# build_rsync_filters - reads the spec file and a source home directory,
# outputs rsync filter arguments (one per line) to stdout.
#
# Args:
#   $1 - spec file path
#   $2 - source home directory
build_rsync_filters() {
    local spec_file="$1"
    local src_home="$2"
    local include_filters=""
    local exclude_filters=""
    local seen=""

    # Helper function to add a filter if not already seen
    add_filter() {
        local filter="$1"
        local list_var="$2"  # "include" or "exclude"

        case " $seen " in
            *" $filter "*)
                # Already seen, skip
                ;;
            *)
                if [ "$list_var" = "exclude" ]; then
                    exclude_filters="$exclude_filters$filter
"
                else
                    include_filters="$include_filters$filter
"
                fi
                seen="$seen $filter "
                ;;
        esac
    }

    # Helper function to add parent directory filters
    add_parents() {
        local path="$1"
        local parent

        # Strip leading ./ if present
        path="${path#./}"

        # Walk up the directory tree
        while [ "$path" != "." ] && [ -n "$path" ]; do
            parent="${path%/*}"
            if [ "$parent" = "$path" ]; then
                break
            fi
            if [ -n "$parent" ]; then
                add_filter "+ $parent/" "include"
            fi
            path="$parent"
        done
    }

    # Read spec file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and blank lines
        case "$line" in
            \#*|"")
                continue
                ;;
        esac

        # Check for exclusion (starts with !)
        case "$line" in
            !*)
                # Exclusion line - strip the ! prefix
                pattern="${line#!}"
                # Check if the path exists and is a directory
                if [ -d "$src_home/$pattern" ]; then
                    add_filter "- $pattern/" "exclude"
                    add_filter "- $pattern/**" "exclude"
                else
                    add_filter "- $pattern" "exclude"
                fi
                ;;
            *)
                # Inclusion line - expand globs
                pattern="$line"

                # Check if pattern contains glob characters
                case "$pattern" in
                    *\**|*\?*|*\[*)
                        # Pattern contains globs - expand them
                        if [ -d "$src_home" ]; then
                            # Save matches to a temp file to avoid subshell variable issues
                            local tmpfile
                            tmpfile="$(mktemp)"
                            (
                                cd "$src_home" || exit
                                # Enable globbing
                                set +f
                                # Expand the glob pattern
                                # shellcheck disable=SC2086
                                for match in $pattern; do
                                    if [ -e "$match" ]; then
                                        echo "$match"
                                    fi
                                done
                            ) > "$tmpfile"

                            # Process matches
                            while IFS= read -r match; do
                                if [ -d "$src_home/$match" ]; then
                                    add_parents "$match"
                                    add_filter "+ $match/" "include"
                                    add_filter "+ $match/**" "include"
                                elif [ -e "$src_home/$match" ]; then
                                    add_parents "$match"
                                    add_filter "+ $match" "include"
                                fi
                            done < "$tmpfile"

                            rm -f "$tmpfile"
                        fi
                        ;;
                    *)
                        # No globs - direct path
                        if [ -d "$src_home/$pattern" ]; then
                            add_parents "$pattern"
                            add_filter "+ $pattern/" "include"
                            add_filter "+ $pattern/**" "include"
                        elif [ -e "$src_home/$pattern" ]; then
                            add_parents "$pattern"
                            add_filter "+ $pattern" "include"
                        fi
                        # If path doesn't exist, silently skip
                        ;;
                esac
                ;;
        esac
    done < "$spec_file"

    # Output excludes first, then includes, then final exclusion
    printf '%s' "$exclude_filters"
    printf '%s' "$include_filters"
    echo "- *"
}

# copy_home_files - copies files from source home to destination based on spec
#
# Args:
#   $1 - spec file path
#   $2 - source home directory
#   $3 - destination directory
copy_home_files() {
    local spec_file="$1"
    local src_home="$2"
    local dest_dir="$3"
    local filter_file
    local ret=0

    # Create temporary filter file
    filter_file="$(mktemp)"

    # Ensure cleanup on exit
    trap 'rm -f "$filter_file"' EXIT INT TERM

    # Build filters
    build_rsync_filters "$spec_file" "$src_home" > "$filter_file"

    # Run rsync with filters
    rsync -a --relative --filter="merge $filter_file" \
        "$src_home/./" "$dest_dir/" || ret=$?

    # Cleanup
    rm -f "$filter_file"
    trap - EXIT INT TERM

    return $ret
}
