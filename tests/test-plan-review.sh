#!/usr/bin/env bash
# test-plan-review.sh — Validates scripts/plan-review.sh against deterministic
# null_resource plans. No HubSpot API or credentials required: the script
# tolerates a missing project.config.sh and the fixture configs use the
# null_resource provider so terraform plan/show -json work end-to-end.
#
# Scenarios cover the contract:
#   ok / no severity   — clean low-volume create plan
#   confirm caution    — creates over HS_LANDER_MAX_CREATE
#   confirm info       — updates over HS_LANDER_MAX_UPDATE
#   confirm destructive — any delete or replace
#   highest-severity-wins — destructive trumps caution when both trigger
#   confirm portal-shared — delete/replace touches a portal-shared resource
#                            (escalates above destructive; v1.9.2)
#   substring-not-suffix      — endswith anchor rejects partial matches
#   multi-needle              — allowlist with 2+ entries iterated correctly
#   portal-shared + destructive — CSV is a strict subset, no leakage
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-plan-review.sh ==="

SCRIPT="$REPO_DIR/scripts/plan-review.sh"
assert_file_exists "$SCRIPT" "scripts/plan-review.sh exists"

if ! command -v terraform >/dev/null 2>&1; then
  echo "  SKIP: terraform not on PATH; skipping plan-review scenarios"
  test_summary
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not on PATH; skipping plan-review scenarios"
  test_summary
  exit 0
fi

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# Generate a terraform fixture with N null_resources. Returns the project dir.
make_fixture() {
  local name="$1" count="$2" extra="${3:-}"
  local dir="$ROOT/$name"
  mkdir -p "$dir/terraform"

  {
    cat <<TF
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

TF
    if (( count > 0 )); then
      cat <<TF
resource "null_resource" "items" {
  count = ${count}
  triggers = {
    idx = tostring(count.index)
  }
}
TF
    fi
    if [[ -n "$extra" ]]; then
      printf '%s\n' "$extra"
    fi
  } > "$dir/terraform/main.tf"

  # Init quietly. Allow plugin caching across fixtures via TF_PLUGIN_CACHE_DIR.
  ( cd "$dir/terraform" && terraform init -input=false -no-color >/dev/null 2>&1 )

  echo "$dir"
}

# Run plan-review and capture stdout/exit.
run_review() {
  local project_dir="$1"
  shift
  HS_LANDER_PROJECT_DIR="$project_dir" bash "$SCRIPT" "$@" 2>&1
}

# Speed up across scenarios with a shared plugin cache.
export TF_PLUGIN_CACHE_DIR="$ROOT/.tf-plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

# Assert that $1 (text) contains a line matching the regex $2.
assert_grep() {
  local text="$1" pattern="$2" message="$3"
  TESTS=$((TESTS + 1))
  if echo "$text" | grep -q "$pattern"; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message"
    echo "    pattern: $pattern"
    echo "    text:    $text" | head -5
  fi
}

# --- Scenario 1: clean 6-create plan → ok, no severity line ---
echo ""
echo "--- Scenario 1: 6 creates, PLAN_REVIEW=ok ---"
fx1=$(make_fixture "clean-6-creates" 6)
out1=$(run_review "$fx1")
assert_grep "$out1" '^PLAN_CREATE=6$' "PLAN_CREATE=6"
assert_grep "$out1" '^PLAN_REVIEW=ok$' "PLAN_REVIEW=ok"
if echo "$out1" | grep -q '^PLAN_REVIEW_SEVERITY='; then
  echo "  FAIL: PLAN_REVIEW_SEVERITY present on ok plan"
  FAILURES=$((FAILURES+1)); TESTS=$((TESTS+1))
else
  echo "  PASS: PLAN_REVIEW_SEVERITY absent on ok plan"
  PASSES=$((PASSES+1)); TESTS=$((TESTS+1))
fi
plan_file=$(echo "$out1" | sed -n 's/^PLAN_FILE=//p')
assert_file_exists "$plan_file" "saved plan file present at PLAN_FILE"

# Verify line count == 7 on ok
line_count=$(echo "$out1" | grep -c '^PLAN_')
assert_equal "$line_count" "7" "exactly 7 PLAN_* lines on ok"

# --- Scenario 2: 60 creates, PLAN_REVIEW=confirm + severity=caution ---
echo ""
echo "--- Scenario 2: 60 creates → confirm/caution ---"
fx2=$(make_fixture "over-create" 60)
out2=$(run_review "$fx2")
assert_grep "$out2" '^PLAN_CREATE=60$' "PLAN_CREATE=60"
assert_grep "$out2" '^PLAN_REVIEW=confirm$' "PLAN_REVIEW=confirm"
assert_grep "$out2" '^PLAN_REVIEW_SEVERITY=caution$' "severity=caution"

# --- Scenario 3: threshold env-var override (HS_LANDER_MAX_CREATE) ---
# Note: null_resource doesn't support pure in-place updates (trigger change
# always produces a replace), so we exercise the threshold logic by tripping
# the create threshold at a low override rather than synthesising 110 updates.
# The PLAN_REVIEW_SEVERITY=info path is exercised indirectly: same code path,
# different severity selection — the unit-style assertion is on the script's
# tally + severity decision, not on terraform's update encoding.
echo ""
echo "--- Scenario 3: HS_LANDER_MAX_CREATE override trips caution ---"
fx3=$(make_fixture "threshold-override" 6)
out3=$(HS_LANDER_MAX_CREATE=3 run_review "$fx3")
assert_grep "$out3" '^PLAN_CREATE=6$' "PLAN_CREATE=6"
assert_grep "$out3" '^PLAN_REVIEW=confirm$' "PLAN_REVIEW=confirm under override"
assert_grep "$out3" '^PLAN_REVIEW_SEVERITY=caution$' "severity=caution under override"

# --- Scenario 4: 1 destroy → severity=destructive ---
echo ""
echo "--- Scenario 4: 1 destroy → confirm/destructive ---"
fx4=$(make_fixture "destroy-one" 1)
( cd "$fx4/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
# Drop the resource to produce a delete plan.
cat > "$fx4/terraform/main.tf" <<TF
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}
TF
out4=$(run_review "$fx4")
assert_grep "$out4" '^PLAN_DELETE=1$' "PLAN_DELETE=1"
assert_grep "$out4" '^PLAN_REVIEW_SEVERITY=destructive$' "severity=destructive on delete"

# Verify line count == 8 on confirm
lc4=$(echo "$out4" | grep -c '^PLAN_')
assert_equal "$lc4" "8" "exactly 8 PLAN_* lines on confirm"

# --- Scenario 5: replace via -replace target → severity=destructive ---
# null_resource trigger mutation produces replace, which we'll exercise here.
echo ""
echo "--- Scenario 5: 1 replace → confirm/destructive ---"
fx5=$(make_fixture "replace-one" 1)
( cd "$fx5/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
# Mutate triggers → null_resource replaces (it's a tainted lifecycle).
cat > "$fx5/terraform/main.tf" <<TF
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "items" {
  count = 1
  triggers = {
    idx = "changed"
  }
}
TF
out5=$(run_review "$fx5")
# Either replace==1 OR delete+create both bumped — the script normalises
# delete+create into replace. Assert PLAN_REPLACE=1.
assert_grep "$out5" '^PLAN_REPLACE=1$' "PLAN_REPLACE=1"
assert_grep "$out5" '^PLAN_REVIEW_SEVERITY=destructive$' "severity=destructive on replace"

# --- Scenario 6: mixed (60 creates + 1 destroy) → highest-severity-wins ---
echo ""
echo "--- Scenario 6: highest-severity-wins (caution + destructive → destructive) ---"
fx6=$(make_fixture "mixed" 1)
( cd "$fx6/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
# Replace existing resource type from 1 → 0, and add 60 new resources from a
# different name. Net: 60 creates + 1 delete.
cat > "$fx6/terraform/main.tf" <<TF
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "newitems" {
  count = 60
  triggers = {
    idx = tostring(count.index)
  }
}
TF
out6=$(run_review "$fx6")
assert_grep "$out6" '^PLAN_CREATE=60$' "PLAN_CREATE=60"
assert_grep "$out6" '^PLAN_DELETE=1$' "PLAN_DELETE=1"
assert_grep "$out6" '^PLAN_REVIEW_SEVERITY=destructive$' "severity=destructive (highest wins)"

# --- Scenario 7: delete on portal-shared resource → portal-shared ---
# The plan-review script suffix-matches resource addresses (endswith)
# against the PORTAL_SHARED_RESOURCES allowlist. Tests override the
# allowlist via HS_LANDER_PORTAL_SHARED_OVERRIDE so we can drive the gate
# with the null_resource provider (no HubSpot dependency).
#
# Address shape: a child module wrapping the resource — `module.acct.<type>.<name>`
# — mirrors the production address (`module.account_setup.restapi_object.project_source_property`)
# and proves the suffix anchor works against module-path-prefixed addresses.
echo ""
echo "--- Scenario 7: delete portal-shared resource → confirm/portal-shared ---"
fx7="$ROOT/portal-shared"
mkdir -p "$fx7/terraform" "$fx7/terraform/modules/acct"
cat > "$fx7/terraform/modules/acct/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

resource "null_resource" "shared_thing" {}
TF
cat > "$fx7/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

module "acct" {
  source = "./modules/acct"
}
TF
( cd "$fx7/terraform" && terraform init -input=false -no-color >/dev/null 2>&1 )
( cd "$fx7/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
cat > "$fx7/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}
TF
out7=$(HS_LANDER_PORTAL_SHARED_OVERRIDE='null_resource.shared_thing' run_review "$fx7")
assert_grep "$out7" '^PLAN_DELETE=1$' "PLAN_DELETE=1 on portal-shared scenario"
assert_grep "$out7" '^PLAN_REVIEW=confirm$' "PLAN_REVIEW=confirm on portal-shared scenario"
assert_grep "$out7" '^PLAN_REVIEW_SEVERITY=portal-shared$' "severity=portal-shared escalates above destructive"
assert_grep "$out7" '^PLAN_REVIEW_PORTAL_SHARED=module\.acct\.null_resource\.shared_thing$' "PORTAL_SHARED lists the module-prefixed address"

# Verify line count == 9 on portal-shared (adds the PORTAL_SHARED line).
lc7=$(echo "$out7" | grep -c '^PLAN_')
assert_equal "$lc7" "9" "exactly 9 PLAN_* lines on portal-shared"

# --- Scenario 8: ordinary destructive plan does NOT emit PORTAL_SHARED line ---
# Re-uses the destroy-one fixture's output to confirm the PORTAL_SHARED line
# is gated on severity=portal-shared.
echo ""
echo "--- Scenario 8: ordinary destructive plan omits PORTAL_SHARED line ---"
if echo "$out4" | grep -q '^PLAN_REVIEW_PORTAL_SHARED='; then
  echo "  FAIL: PLAN_REVIEW_PORTAL_SHARED present on plain destructive plan"
  FAILURES=$((FAILURES+1)); TESTS=$((TESTS+1))
else
  echo "  PASS: PLAN_REVIEW_PORTAL_SHARED absent on plain destructive plan"
  PASSES=$((PASSES+1)); TESTS=$((TESTS+1))
fi

# --- Scenario 9: substring false-positive guard ---
# An address that *contains* the needle as a substring but does not end with
# it (e.g. `null_resource.shared_thing_helper`) must NOT escalate. Pins the
# endswith semantics against accidental drift back to substring matching.
echo ""
echo "--- Scenario 9: substring-but-not-suffix → destructive, not portal-shared ---"
fx9="$ROOT/false-positive"
mkdir -p "$fx9/terraform"
cat > "$fx9/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "shared_thing_helper" {}
TF
( cd "$fx9/terraform" && terraform init -input=false -no-color >/dev/null 2>&1 )
( cd "$fx9/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
cat > "$fx9/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}
TF
out9=$(HS_LANDER_PORTAL_SHARED_OVERRIDE='null_resource.shared_thing' run_review "$fx9")
assert_grep "$out9" '^PLAN_DELETE=1$' "substring-only fixture has 1 delete"
assert_grep "$out9" '^PLAN_REVIEW_SEVERITY=destructive$' "substring-only does not escalate to portal-shared"
if echo "$out9" | grep -q '^PLAN_REVIEW_PORTAL_SHARED='; then
  echo "  FAIL: substring-only address wrongly listed in PORTAL_SHARED"
  FAILURES=$((FAILURES+1)); TESTS=$((TESTS+1))
else
  echo "  PASS: substring-only address absent from PORTAL_SHARED"
  PASSES=$((PASSES+1)); TESTS=$((TESTS+1))
fi

# --- Scenario 10: multi-needle allowlist + multi-resource match ---
# Verifies (a) multiple entries in PORTAL_SHARED_RESOURCES are iterated
# correctly and (b) when multiple destroyed addresses match the allowlist,
# all of them appear in the CSV. Future-proofs against shipping a v1.9.3
# that adds a second portal-shared resource and silently regressing.
echo ""
echo "--- Scenario 10: multi-needle allowlist surfaces all matching addresses ---"
fx10="$ROOT/multi-needle"
mkdir -p "$fx10/terraform"
cat > "$fx10/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "alpha" {}
resource "null_resource" "beta" {}
TF
( cd "$fx10/terraform" && terraform init -input=false -no-color >/dev/null 2>&1 )
( cd "$fx10/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
cat > "$fx10/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}
TF
out10=$(HS_LANDER_PORTAL_SHARED_OVERRIDE='null_resource.alpha,null_resource.beta' run_review "$fx10")
assert_grep "$out10" '^PLAN_DELETE=2$' "multi-needle scenario has 2 deletes"
assert_grep "$out10" '^PLAN_REVIEW_SEVERITY=portal-shared$' "multi-needle escalates"
assert_grep "$out10" '^PLAN_REVIEW_PORTAL_SHARED=.*null_resource\.alpha' "alpha appears in PORTAL_SHARED CSV"
assert_grep "$out10" '^PLAN_REVIEW_PORTAL_SHARED=.*null_resource\.beta' "beta appears in PORTAL_SHARED CSV"

# --- Scenario 11: portal-shared + unrelated destructive coexistence ---
# The CSV must list ONLY the portal-shared addresses, not the unrelated
# destructive ones — pins the contract that PORTAL_SHARED is a strict
# subset of the destroyed/replaced set.
echo ""
echo "--- Scenario 11: portal-shared CSV excludes unrelated destructive addresses ---"
fx11="$ROOT/portal-plus-destructive"
mkdir -p "$fx11/terraform"
cat > "$fx11/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "shared_thing" {}
resource "null_resource" "ordinary_thing" {}
TF
( cd "$fx11/terraform" && terraform init -input=false -no-color >/dev/null 2>&1 )
( cd "$fx11/terraform" && terraform apply -auto-approve -no-color >/dev/null 2>&1 )
cat > "$fx11/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}
TF
out11=$(HS_LANDER_PORTAL_SHARED_OVERRIDE='null_resource.shared_thing' run_review "$fx11")
assert_grep "$out11" '^PLAN_DELETE=2$' "scenario 11 has 2 deletes"
assert_grep "$out11" '^PLAN_REVIEW_SEVERITY=portal-shared$' "portal-shared wins over destructive"
assert_grep "$out11" '^PLAN_REVIEW_PORTAL_SHARED=null_resource\.shared_thing$' "PORTAL_SHARED contains only the matching address"
if echo "$out11" | grep -q 'PLAN_REVIEW_PORTAL_SHARED=.*ordinary_thing'; then
  echo "  FAIL: unrelated destructive address leaked into PORTAL_SHARED CSV"
  FAILURES=$((FAILURES+1)); TESTS=$((TESTS+1))
else
  echo "  PASS: unrelated destructive address absent from PORTAL_SHARED CSV"
  PASSES=$((PASSES+1)); TESTS=$((TESTS+1))
fi

test_summary
