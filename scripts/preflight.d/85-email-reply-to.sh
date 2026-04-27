#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 85-email-reply-to.sh — emits PREFLIGHT_EMAIL_REPLY_TO.
#
# Reads: tools_required_ok, project_pointer_ok, pointer_skip_reason,
#        project_profile_ok, EMAIL_REPLY_TO, DOMAIN.
#
# Observability for the EMAIL_DNS fallback in 80-email-dns.sh. EMAIL_DNS
# probes EMAIL_REPLY_TO's host part when set, otherwise falls back to
# DOMAIN. Without this line, operators can't tell from preflight output
# which domain was actually probed — a forgotten EMAIL_REPLY_TO masquerades
# as a DKIM pass on the wrong domain. This check surfaces the decision so
# the skill (or operator) can decide whether the fallback is acceptable
# for their setup.
#
# Emits one of:
#   PREFLIGHT_EMAIL_REPLY_TO=set <address>     — explicit value in the project profile
#   PREFLIGHT_EMAIL_REPLY_TO=fallback <DOMAIN> — empty in profile; falling back to DOMAIN
#   PREFLIGHT_EMAIL_REPLY_TO=skipped <reason>  — project profile missing/incomplete
#                                                or DOMAIN unset
#
# Non-blocking — both `set` and `fallback` exit 0. Framework-level pass/fail
# is unaffected by this line.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_EMAIL_REPLY_TO=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_EMAIL_REPLY_TO=skipped (${pointer_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_profile_ok" -ne 1 ]]; then
  echo "PREFLIGHT_EMAIL_REPLY_TO=skipped (project profile missing or incomplete)"
  return 0 2>/dev/null || exit 0
fi

if [[ -n "${EMAIL_REPLY_TO:-}" ]]; then
  echo "PREFLIGHT_EMAIL_REPLY_TO=set ${EMAIL_REPLY_TO}"
elif [[ -n "${DOMAIN:-}" ]]; then
  echo "PREFLIGHT_EMAIL_REPLY_TO=fallback ${DOMAIN}"
else
  echo "PREFLIGHT_EMAIL_REPLY_TO=skipped (DOMAIN not set)"
fi
