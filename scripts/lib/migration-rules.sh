#!/usr/bin/env bash
# migration-rules.sh — versioned migration rules consumed by
# scripts/migrate-project.sh.
#
# Public entry point: `run_migration_chain <from> <to>` walks the
# `_MIGRATION_CHAIN` table from <from> to <to>, calling each one-version
# rule in turn and emitting MIGRATE_STEP=<n> <description> lines.
#
# Caller sets two env vars:
#   _MIGRATE_PROJECT_DIR — absolute path of the project being migrated
#   _MIGRATE_APPLY       — "1" to write changes, "0" for plan-only
#
# Each rule function uses the helpers below to apply transformations
# atomically (tempfile + mv) so a partial failure leaves the file
# unchanged. Helpers are no-ops when _MIGRATE_APPLY != 1 — they emit
# the MIGRATE_STEP description regardless so the plan-only mode shows
# what would happen.
#
# Internal step counter so functions don't need to thread one another's
# return values. _MIGRATE_STEP_COUNTER starts at 1 in run_migration_chain.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/sed-portable.sh"

_emit_step() {
  echo "MIGRATE_STEP=$_MIGRATE_STEP_COUNTER $*"
  _MIGRATE_STEP_COUNTER=$(( _MIGRATE_STEP_COUNTER + 1 ))
}

# Insert a `variable "X" {...}` block before the first `module "..." {`
# block in terraform/main.tf, idempotently. The block content is read
# from stdin so it can be multi-line without BSD-awk-incompatible
# tricks. No-op when the variable is already declared.
_migrate_add_root_variable_from_stdin() {
  local main_tf="$1" var_name="$2"
  local block
  block=$(cat)
  if grep -qE "^variable \"${var_name}\" \{" "$main_tf"; then
    return 0
  fi
  if [[ "${_MIGRATE_APPLY:-0}" -ne 1 ]]; then
    return 0
  fi
  local tmp_path="$main_tf.tmp.$$"
  local block_file
  block_file=$(mktemp)
  printf '%s\n\n' "$block" > "$block_file"
  awk -v BLOCK_FILE="$block_file" '
    BEGIN {
      while ((getline line < BLOCK_FILE) > 0) {
        block_lines[++n] = line
      }
      close(BLOCK_FILE)
    }
    !inserted && /^module "[a-z_]+" \{/ {
      for (i = 1; i <= n; i++) print block_lines[i]
      inserted = 1
    }
    { print }
  ' "$main_tf" > "$tmp_path"
  rm -f "$block_file"
  mv "$tmp_path" "$main_tf"
}

# Add a `<key> = var.<name>` line into the `module "landing_page" {...}`
# block, before its closing `}`. Idempotent. Tracks brace depth so it
# inserts at the correct closing brace, not at any nested one.
_migrate_wire_module_var() {
  local main_tf="$1" key_name="$2"
  if grep -qE "^[[:space:]]+${key_name}[[:space:]]*=[[:space:]]*var\.${key_name}" "$main_tf"; then
    return 0
  fi
  if [[ "${_MIGRATE_APPLY:-0}" -ne 1 ]]; then
    return 0
  fi
  local tmp_path="$main_tf.tmp.$$"
  awk -v key="$key_name" '
    /^module "landing_page" \{/ { in_block = 1; depth = 1; print; next }
    in_block {
      # Track brace depth so we hit the right closing }, not a nested one.
      n_open = gsub(/\{/, "{")
      depth_now = depth + n_open
      # Re-scan because gsub mutated $0 — restore.
      $0 = orig_line
      n_close = gsub(/\}/, "}")
      depth_now = depth_now - n_close
      $0 = orig_line
      if (depth_now == 0) {
        # This line closes the block. Insert before it.
        printf "  %s = var.%s\n", key, key
        in_block = 0
      } else {
        depth = depth_now
      }
    }
    { orig_line = $0; print }
  ' "$main_tf" > "$tmp_path"
  # The above awk has a subtle issue with re-evaluating $0; use a simpler
  # depth tracker that just counts on the original line via a side
  # channel. Replace with a clean implementation:
  awk -v key="$key_name" '
    BEGIN { depth = 0; in_block = 0 }
    {
      line = $0
      if (in_block) {
        # Count braces in the current line (ignoring the line itself).
        opens = gsub(/\{/, "{", line)
        closes = gsub(/\}/, "}", line)
        depth_after = depth + opens - closes
        if (depth_after <= 0) {
          # This line contains the closing } of the module block.
          # Emit our wire line before printing this line.
          printf "  %s = var.%s\n", key, key
          in_block = 0
          print $0
          next
        }
        depth = depth_after
        print $0
        next
      }
      if ($0 ~ /^module "landing_page" \{/) {
        in_block = 1
        depth = 1
        # Account for additional open/close on the same line (rare).
        rest = $0
        sub(/^module "landing_page" \{/, "", rest)
        opens = gsub(/\{/, "{", rest)
        closes = gsub(/\}/, "}", rest)
        depth = depth + opens - closes
        print $0
        next
      }
      print $0
    }
  ' "$main_tf" > "$tmp_path"
  mv "$tmp_path" "$main_tf"
}

# Rewrite the ?ref= pin in BOTH module blocks. Atomic.
_migrate_bump_ref() {
  local main_tf="$1" target_version="$2"
  if [[ "${_MIGRATE_APPLY:-0}" -ne 1 ]]; then
    return 0
  fi
  local tmp_path="$main_tf.tmp.$$"
  sed -E "s|\\?ref=v[0-9]+\\.[0-9]+\\.[0-9]+[A-Za-z0-9.-]*|?ref=v${target_version}|g" "$main_tf" > "$tmp_path"
  mv "$tmp_path" "$main_tf"
}

# --- v1.6.0 → v1.7.0 ---
# Three new scaffold root variables: email_preview_text,
# auto_publish_welcome_email, capture_post_submit_action_override.
migrate_v1_6_0_to_v1_7_0() {
  local main_tf="$_MIGRATE_PROJECT_DIR/terraform/main.tf"
  _emit_step "declare email_preview_text root variable"
  _migrate_add_root_variable_from_stdin "$main_tf" "email_preview_text" <<'BLOCK'
variable "email_preview_text" {
  type    = string
  default = ""
}
BLOCK
  _emit_step "declare auto_publish_welcome_email root variable"
  _migrate_add_root_variable_from_stdin "$main_tf" "auto_publish_welcome_email" <<'BLOCK'
variable "auto_publish_welcome_email" {
  type    = bool
  default = true
}
BLOCK
  _emit_step "declare capture_post_submit_action_override root variable"
  _migrate_add_root_variable_from_stdin "$main_tf" "capture_post_submit_action_override" <<'BLOCK'
variable "capture_post_submit_action_override" {
  type    = any
  default = {}
}
BLOCK
  _emit_step "wire email_preview_text into module.landing_page"
  _migrate_wire_module_var "$main_tf" "email_preview_text"
  _emit_step "wire auto_publish_welcome_email into module.landing_page"
  _migrate_wire_module_var "$main_tf" "auto_publish_welcome_email"
  _emit_step "wire capture_post_submit_action_override into module.landing_page"
  _migrate_wire_module_var "$main_tf" "capture_post_submit_action_override"
}

# --- v1.7.0 → v1.8.0 ---
# No scaffold-root changes (additive module work only).
migrate_v1_7_0_to_v1_8_0() {
  _emit_step "v1.7.0 → v1.8.0: no scaffold-root changes (additive module work only)"
}

# --- v1.8.0 → v1.8.1 ---
# Adds email_reply_to root variable + wiring. v1.8.0's scaffold hard-coded
# replyTo to a placeholder; v1.8.1 made it consumer-supplied.
migrate_v1_8_0_to_v1_8_1() {
  local main_tf="$_MIGRATE_PROJECT_DIR/terraform/main.tf"
  _emit_step "declare email_reply_to root variable"
  _migrate_add_root_variable_from_stdin "$main_tf" "email_reply_to" <<'BLOCK'
variable "email_reply_to" {
  type = string
}
BLOCK
  _emit_step "wire email_reply_to into module.landing_page (replacing hard-coded placeholder)"
  _migrate_wire_module_var "$main_tf" "email_reply_to"
}

# --- v1.8.1 → v1.9.0 ---
# scaffold/package.json gains npm run plan + npm run apply; npm run setup
# chains plan-review→apply. The scaffold/terraform/main.tf is unchanged
# (no new root variables). Refresh package.json from scaffold via
# upgrade-project-scripts.sh — out of scope for this in-place migration.
migrate_v1_8_1_to_v1_9_0() {
  _emit_step "v1.8.1 → v1.9.0: refresh package.json from scaffold/ for new npm run plan/apply scripts"
  _emit_step "v1.8.1 → v1.9.0: confirm scaffold/.gitignore additions are present (terraform/state-backups/, .hs-lander-plan.bin)"
}

# --- v1.9.0 → v1.9.1 ---
# No scaffold-root changes (framework-side additions only).
migrate_v1_9_0_to_v1_9_1() {
  _emit_step "v1.9.0 → v1.9.1: no per-project changes (framework-side additions only)"
}

# Lookup table: known migration steps in order.
_MIGRATION_CHAIN=(
  "1.6.0:1.7.0:migrate_v1_6_0_to_v1_7_0"
  "1.7.0:1.8.0:migrate_v1_7_0_to_v1_8_0"
  "1.8.0:1.8.1:migrate_v1_8_0_to_v1_8_1"
  "1.8.1:1.9.0:migrate_v1_8_1_to_v1_9_0"
  "1.9.0:1.9.1:migrate_v1_9_0_to_v1_9_1"
)

# Run the chain from <from> to <to>. Caller sets _MIGRATE_PROJECT_DIR
# and _MIGRATE_APPLY in the environment first.
run_migration_chain() {
  local from="$1" to="$2"
  local main_tf="$_MIGRATE_PROJECT_DIR/terraform/main.tf"
  _MIGRATE_STEP_COUNTER=1
  local applied_any=0
  local entry
  for entry in "${_MIGRATION_CHAIN[@]}"; do
    local rule_from="${entry%%:*}"
    local rest="${entry#*:}"
    local rule_to="${rest%%:*}"
    local rule_fn="${rest#*:}"
    if _version_in_range "$rule_from" "$from" "$rule_to" "$to"; then
      "$rule_fn"
      applied_any=1
    fi
  done

  if [[ "$applied_any" -eq 0 ]]; then
    _emit_step "(no migration rules between $from and $to — direct ?ref= bump only)"
  fi

  _emit_step "bump ?ref=v$from → ?ref=v$to in terraform/main.tf"
  if [[ -f "$main_tf" ]]; then
    _migrate_bump_ref "$main_tf" "$to"
  fi
}

# version-in-range: true if rule_from >= from AND rule_to <= to.
_version_in_range() {
  local rule_from="$1" from="$2" rule_to="$3" to="$4"
  local lower
  lower=$(printf '%s\n%s\n' "$rule_from" "$from" | sort -V | head -1)
  if [[ "$lower" != "$from" ]]; then
    return 1
  fi
  local upper
  upper=$(printf '%s\n%s\n' "$rule_to" "$to" | sort -V | tail -1)
  if [[ "$upper" != "$to" ]]; then
    return 1
  fi
  return 0
}
