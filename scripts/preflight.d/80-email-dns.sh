#!/usr/bin/env bash
# 80-email-dns.sh — emits PREFLIGHT_EMAIL_DNS.
#
# Reads: tools_required_ok, project_pointer_ok, pointer_skip_reason,
#        EMAIL_REPLY_TO, DOMAIN, HUBSPOT_REGION, HUBSPOT_PORTAL_ID.
#
# SPF / DKIM / DMARC checks for the email_reply_to domain. Catches the
# "broken email auth, mail goes to spam" failure mode before deploy. DKIM
# uses typed `dig CNAME` (never ANY — RFC 8482 refusal under Cloudflare
# defaults). Region-aware SPF: HubSpot's portal-specific include hostname
# differs by region. The lookup table here mirrors references/email-auth-dns.md;
# update both in lockstep when new regions ship.
#
# Emits one of:
#   ok                          — SPF (with HubSpot include + correct mechanism order),
#                                 DKIM (both hs1- and hs2- selectors), and DMARC all present
#   spf-missing                 — no SPF record at apex of email-reply-to domain
#   spf-no-hubspot-include      — SPF exists but missing the portal-specific include
#   spf-all-mid-record          — SPF has the include but `all` mechanism isn't last
#   dkim-missing                — one or both portal-id-suffixed DKIM CNAME selectors absent
#   dmarc-missing               — no DMARC TXT record at _dmarc.<domain>
#   region-unknown              — HUBSPOT_REGION isn't one we know SPF includes for
#   skipped (<reason>)          — EMAIL_REPLY_TO unset or DNS tooling unavailable
#
# Multiple issues compose: e.g. a domain missing both DKIM and DMARC will
# emit `dkim-missing` then a separate `dmarc-missing` follow-up note (DMARC
# is warn-only — preflight's overall pass/fail is unaffected by DMARC alone).
#
# TODO (v1.8.x): NA1 SPF include hostname is a placeholder pending
# verification against a NA1 portal — see references/email-auth-dns.md.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_EMAIL_DNS=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_EMAIL_DNS=skipped (${pointer_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

# Determine the email-auth domain. Preferred source: EMAIL_REPLY_TO from
# project profile (set explicitly by the consumer). Fallback: DOMAIN
# (assumes the project's landing-page domain doubles as its email-sending
# domain, which is true in the common single-domain case).
_email_auth_domain=""
if [[ -n "${EMAIL_REPLY_TO:-}" ]]; then
  _email_auth_domain="${EMAIL_REPLY_TO##*@}"
elif [[ -n "${DOMAIN:-}" ]]; then
  _email_auth_domain="$DOMAIN"
fi

if [[ -z "$_email_auth_domain" ]]; then
  echo "PREFLIGHT_EMAIL_DNS=skipped (no EMAIL_REPLY_TO or DOMAIN to probe)"
elif ! command -v dig >/dev/null 2>&1; then
  echo "PREFLIGHT_EMAIL_DNS=skipped (dig unavailable)"
else
  # Region → HubSpot SPF include hostname. Update in lockstep with
  # references/email-auth-dns.md.
  case "${HUBSPOT_REGION:-}" in
    eu1)  _spf_include_host="${HUBSPOT_PORTAL_ID}.spf04.hubspotemail.net" ;;
    na1)  _spf_include_host="${HUBSPOT_PORTAL_ID}.spf.hubspotemail.net" ;;  # TODO: verify against NA1 portal
    *)    _spf_include_host="" ;;
  esac

  if [[ -z "$_spf_include_host" ]]; then
    echo "PREFLIGHT_EMAIL_DNS=region-unknown ${HUBSPOT_REGION:-<unset>} (no known HubSpot SPF include hostname)"
  else
    _spf_record=$(dig +short TXT "$_email_auth_domain" 2>/dev/null | tr -d '"' | grep -i 'v=spf1' | head -1 || true)
    _email_dns_state="ok"
    _email_dns_detail=""

    if [[ -z "$_spf_record" ]]; then
      _email_dns_state="spf-missing"
      _email_dns_detail="no v=spf1 record at $_email_auth_domain"
    elif [[ "$_spf_record" != *"include:${_spf_include_host}"* ]]; then
      _email_dns_state="spf-no-hubspot-include"
      _email_dns_detail="expected include:${_spf_include_host} (HUBSPOT_REGION=${HUBSPOT_REGION:-?})"
    else
      # Verify `all` mechanism is the LAST token; anything after it (notably
      # another `include:`) is silently ignored by validators.
      _spf_tokens=$(printf '%s' "$_spf_record" | tr -s ' ')
      _last_token="${_spf_tokens##* }"
      case "$_last_token" in
        ~all|-all|+all|?all) ;;
        *)
          _email_dns_state="spf-all-mid-record"
          _email_dns_detail="all mechanism is not the last token (last=$_last_token)"
          ;;
      esac
    fi

    if [[ "$_email_dns_state" == "ok" ]]; then
      _dkim_hs1=$(dig +short CNAME "hs1-${HUBSPOT_PORTAL_ID}._domainkey.${_email_auth_domain}" 2>/dev/null || true)
      _dkim_hs2=$(dig +short CNAME "hs2-${HUBSPOT_PORTAL_ID}._domainkey.${_email_auth_domain}" 2>/dev/null || true)
      if [[ -z "$_dkim_hs1" || -z "$_dkim_hs2" ]]; then
        _email_dns_state="dkim-missing"
        _missing_selectors=""
        [[ -z "$_dkim_hs1" ]] && _missing_selectors="hs1-${HUBSPOT_PORTAL_ID}"
        [[ -z "$_dkim_hs2" ]] && _missing_selectors="${_missing_selectors:+$_missing_selectors,}hs2-${HUBSPOT_PORTAL_ID}"
        _email_dns_detail="missing CNAME selectors: $_missing_selectors"
      fi
    fi

    if [[ "$_email_dns_state" == "ok" ]]; then
      _dmarc=$(dig +short TXT "_dmarc.${_email_auth_domain}" 2>/dev/null | tr -d '"' | grep -i 'v=DMARC1' | head -1 || true)
      if [[ -z "$_dmarc" ]]; then
        _email_dns_state="dmarc-missing"
        _email_dns_detail="no v=DMARC1 record at _dmarc.${_email_auth_domain} (warn — DMARC is recommended, not required)"
      fi
    fi

    case "$_email_dns_state" in
      ok)
        echo "PREFLIGHT_EMAIL_DNS=ok"
        ;;
      dmarc-missing)
        # Warn-only — keep required_failed unchanged.
        echo "PREFLIGHT_EMAIL_DNS=$_email_dns_state $_email_dns_detail"
        ;;
      *)
        echo "PREFLIGHT_EMAIL_DNS=$_email_dns_state $_email_dns_detail"
        required_failed=1
        ;;
    esac
  fi
fi
unset _email_auth_domain _spf_include_host _spf_record _spf_tokens _last_token _dkim_hs1 _dkim_hs2 _dmarc _email_dns_state _email_dns_detail _missing_selectors
