#!/usr/bin/env bash
# sed-portable.sh — portable sed helpers (BSD on macOS, GNU on Linux).
#
# Sourced by build.sh, post-apply.sh, set-project-field.sh, accounts-init.sh,
# upgrade-project-scripts.sh, and any future script that needs in-place
# editing or replacement-side metacharacter escaping. Keeps the BSD/GNU
# divergence and the `[\\|&]` escape pattern in one place so they can't
# silently drift between consumers.

# Portable in-place sed. Use exactly like `sed -i` on Linux:
#   sed_inplace -e 's|FOO|bar|g' "$file"
#   sed_inplace -E 's|^(KEY)=.*|\1=replaced|' "$file"
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Escape sed replacement-side metacharacters: \, |, &.
# - `\` is sed's escape character.
# - `|` is the substitution-delimiter the framework uses (chosen so paths
#   containing `/` round-trip without escaping).
# - `&` is sed's "whole match" backref on the replacement side.
#
# Left-hand-side escaping (regex metacharacters in the search pattern) is
# the caller's concern. The framework's substitution patterns are static
# tokens (`__KEY__`) which don't need escaping; only consumer-supplied
# values (right-hand side) reach this helper.
sed_escape_replacement() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}
