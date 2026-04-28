#!/usr/bin/env bash
# test-prevent-destroy.sh — Validates the prevent_destroy lifecycle guard on
# the portal-shared project_source_property resource (v1.9.2).
#
# Two assertions:
#   1. The account-setup module's project_source_property resource block
#      contains a lifecycle { prevent_destroy = true } directive.
#   2. Terraform itself rejects destroy plans against any resource with this
#      directive — exercised via a synthetic null_resource fixture so the
#      test stays self-contained (no HubSpot API, no restapi provider).
#
# The second assertion guards against the directive being silently dropped
# during a future refactor: it's a smoke test of Terraform's behaviour, not
# of HCL parsing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-prevent-destroy.sh ==="

ACCOUNT_SETUP_TF="$REPO_DIR/terraform/modules/account-setup/main.tf"
assert_file_exists "$ACCOUNT_SETUP_TF" "account-setup/main.tf exists"

# --- Assertion 1: lifecycle block on project_source_property ---
echo ""
echo "--- Assertion 1: lifecycle { prevent_destroy = true } on project_source_property ---"
# Extract the project_source_property resource block by tracking brace
# depth from the opening line. grep alone can't bracket-match; a naive
# `^}$` stop-pattern misbehaves if any nested HCL puts a closing brace
# at column zero. Counting depth handles both.
block=$(awk '
  /^resource "restapi_object" "project_source_property"/ {
    in_block=1; depth=0
  }
  in_block {
    print
    depth += gsub(/\{/, "{")
    depth -= gsub(/\}/, "}")
    if (in_block && depth == 0 && NR > 1 && /\}/) exit
  }
' "$ACCOUNT_SETUP_TF")

# Distinguish "block missing entirely" from "block present but lacks the
# directive" — the failure messages mean different things to a human
# debugging the regression.
if [[ -z "$block" ]]; then
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: could not locate restapi_object.project_source_property block — was it renamed?"
elif echo "$block" | grep -q 'prevent_destroy *= *true'; then
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: project_source_property has prevent_destroy = true"
else
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: project_source_property is missing prevent_destroy = true"
  echo "  block contents:"
  echo "$block" | sed 's/^/    /'
fi

# --- Assertion 2: Terraform rejects destroy when prevent_destroy is set ---
echo ""
echo "--- Assertion 2: terraform plan -destroy fails on prevent_destroy resource ---"

if ! command -v terraform >/dev/null 2>&1; then
  echo "  SKIP: terraform not on PATH; skipping destroy-plan smoke test"
  test_summary
  exit 0
fi

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/terraform"
cat > "$ROOT/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "guarded" {
  lifecycle {
    prevent_destroy = true
  }
}
TF

# Capture init/apply output so failures surface a real diagnostic instead
# of being swallowed by `>/dev/null 2>&1`. Without this, an init failure
# (e.g. provider download outage) makes the destroy assertion fail for
# the wrong reason and the developer chases a phantom regression.
init_log=$(mktemp)
apply_log=$(mktemp)
if ! terraform -chdir="$ROOT/terraform" init -input=false -no-color >"$init_log" 2>&1; then
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: terraform init failed; cannot run prevent_destroy smoke test"
  sed 's/^/    /' "$init_log"
  test_summary
  exit 1
fi
if ! terraform -chdir="$ROOT/terraform" apply -auto-approve -no-color >"$apply_log" 2>&1; then
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: terraform apply failed; cannot run prevent_destroy smoke test"
  sed 's/^/    /' "$apply_log"
  test_summary
  exit 1
fi

# plan -destroy is expected to fail. Capture exit code separately so we
# distinguish "command failed for the wrong reason (matched the regex by
# coincidence)" from "prevent_destroy actually fired".
set +e
plan_out=$(terraform -chdir="$ROOT/terraform" plan -destroy -no-color 2>&1)
plan_rc=$?
set -e

# Broad regex: covers Terraform's current and historical phrasings of the
# lifecycle.prevent_destroy error. Anchoring on either keyword tolerates
# minor wording shifts across Terraform releases.
if (( plan_rc != 0 )) && echo "$plan_out" | grep -qiE 'prevent_destroy|cannot be destroyed|lifecycle.*destroy'; then
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: terraform plan -destroy fails with prevent_destroy error (exit $plan_rc)"
else
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: terraform plan -destroy did not fail with prevent_destroy error (exit $plan_rc)"
  echo "  output (first 20 lines):"
  echo "$plan_out" | head -20 | sed 's/^/    /'
fi

# Sanity: the same fixture WITHOUT prevent_destroy should succeed at plan -destroy.
# This guards against the assertion above being a false positive (e.g. matching
# the wrong error string).
echo ""
echo "--- Sanity: same fixture without prevent_destroy succeeds ---"
cat > "$ROOT/terraform/main.tf" <<'TF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "guarded" {}
TF

if terraform -chdir="$ROOT/terraform" plan -destroy -no-color >/dev/null 2>&1; then
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: plan -destroy succeeds when prevent_destroy is removed"
else
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: plan -destroy failed unexpectedly without prevent_destroy"
fi

test_summary
