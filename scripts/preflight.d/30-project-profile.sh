#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 30-project-profile.sh — emits PREFLIGHT_PROJECT_PROFILE.
#
# Reads: project_pointer_ok, pointer_skip_reason, HS_LANDER_ACCOUNT,
#        HS_LANDER_PROJECT.
# Writes: project_profile_ok, PROJECT_SLUG, DOMAIN, DM_UPLOAD_PATH,
#         GA4_MEASUREMENT_ID, CAPTURE_FORM_ID, EMAIL_REPLY_TO.
#
# Loads the per-project profile and verifies the three required fields are
# non-empty. The optional fields (GA4_MEASUREMENT_ID, CAPTURE_FORM_ID,
# EMAIL_REPLY_TO) are pulled into the parent shell here so downstream checks
# (DNS, EMAIL_DNS, GA4, FORM_IDS) can read them without a second source step.

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_PROJECT_PROFILE=skipped (${pointer_skip_reason})"
  project_profile_ok=0
  return 0 2>/dev/null || exit 0
fi

project_config="${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
if [[ ! -f "$project_config" ]]; then
  echo "PREFLIGHT_PROJECT_PROFILE=missing $project_config does not exist"
  project_profile_ok=0
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

eval "$(source_vars "$project_config" PROJECT_SLUG DOMAIN DM_UPLOAD_PATH GA4_MEASUREMENT_ID CAPTURE_FORM_ID EMAIL_REPLY_TO)"
project_missing=()
for v in PROJECT_SLUG DOMAIN DM_UPLOAD_PATH; do
  [[ -z "${!v:-}" ]] && project_missing+=("$v")
done
if [[ ${#project_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_PROJECT_PROFILE=ok"
  project_profile_ok=1
else
  missing_csv=$(IFS=,; echo "${project_missing[*]}")
  echo "PREFLIGHT_PROJECT_PROFILE=incomplete $missing_csv"
  project_profile_ok=0
  required_failed=1
fi
