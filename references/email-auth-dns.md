# Email-authentication DNS for HubSpot mail (SPF / DKIM / DMARC)

`scripts/preflight.sh` (v1.8.0+) probes the project's `email_reply_to` domain (or `DOMAIN` as a fallback) for the three records HubSpot needs to send mail without it being silently downgraded by recipient mail servers. This file is the source of truth for the regional includes, selector patterns, and known-broken record shapes that preflight detects.

## Required records

### SPF (TXT at the apex)

A single TXT record at the apex of the email-sending domain that includes HubSpot's portal-specific include hostname. Example for an EU1 portal `12345678`:

```
yourdomain.example.com.    TXT    "v=spf1 include:12345678.spf04.hubspotemail.net -all"
```

The `-all` (or `~all`) **must be the last token**. SPF mechanism order is left-to-right; anything after `all` is silently ignored by validators. The "broken SPF that breaks email auth" pattern Heard hit looked like:

```
"v=spf1 ~all include:12345678.spf04.hubspotemail.net"
                                                       ⌃ all is mid-record;
                                                         the include is unreachable
```

Visually plausible, but the include never gets evaluated.

### DKIM (CNAME at portal-specific selectors)

Two CNAME records at portal-id-suffixed selectors. For portal `12345678`:

```
hs1-12345678._domainkey.yourdomain.example.com.    CNAME    hs1-12345678.<...>.hsdns.io.
hs2-12345678._domainkey.yourdomain.example.com.    CNAME    hs2-12345678.<...>.hsdns.io.
```

The right-hand side (CNAME target) varies per portal — HubSpot generates the target during the "Connect a sending domain" flow in Settings → Marketing → Email → Email sending domain. The selector pattern (`hs1-<portal-id>` and `hs2-<portal-id>`) is portal-agnostic across the portals sampled to date.

**Don't use `dig +short ANY` to probe DKIM.** Cloudflare and other modern authoritatives respond to ANY queries with an empty/refusal per RFC 8482. Use typed `dig +short CNAME <selector>._domainkey.<domain>` instead — that's what preflight does.

### DMARC (TXT at `_dmarc.<domain>`)

```
_dmarc.yourdomain.example.com.    TXT    "v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.example.com"
```

`p=none` is the safe baseline; consumers progressing to `p=quarantine` and `p=reject` is encouraged but not required by preflight. DMARC is **warn-only** in the preflight contract — its absence emits a warning but doesn't fail the check.

## Regional SPF includes

| `HUBSPOT_REGION` | SPF include hostname | Verification status |
|---|---|---|
| `eu1` | `<portal-id>.spf04.hubspotemail.net` | Verified 2026-04-26 against an EU1 portal during the v1.7.0 deploy round |
| `na1` | `<portal-id>.spf.hubspotemail.net` | **Placeholder** — not yet verified against a NA1 portal. Probe via HubSpot's Settings → Marketing → Email → Email sending domain → Connect a domain flow on a NA1 portal and capture the include the UI displays in its DNS instructions. Update this row + `scripts/preflight.sh`'s case statement when verified. |
| `apac` (when introduced) | TBD | Probe at first APAC consumer. |

`preflight.sh` reads `HUBSPOT_REGION` from project config and emits `PREFLIGHT_EMAIL_DNS=region-unknown` for any region not in this table. The skill (or a hand-edit) coaches the consumer to set `HUBSPOT_REGION` if the value is missing.

## Preflight emit values

| Value | Meaning |
|---|---|
| `ok` | SPF (HubSpot include + correct `all` mechanism position), both DKIM CNAME selectors, and DMARC all present |
| `spf-missing <detail>` | No `v=spf1` TXT at the email-auth domain apex |
| `spf-no-hubspot-include <detail>` | SPF exists but doesn't include the portal-specific HubSpot include |
| `spf-all-mid-record <detail>` | SPF has the include but `all` token isn't last |
| `dkim-missing <detail>` | One or both portal-id-suffixed DKIM CNAME selectors absent |
| `dmarc-missing <detail>` | No `v=DMARC1` TXT at `_dmarc.<domain>` (warn-only — overall check still passes) |
| `region-unknown <region>` | `HUBSPOT_REGION` isn't in the table above |
| `skipped (<reason>)` | `EMAIL_REPLY_TO` and `DOMAIN` both unset, or `dig` unavailable |

## Common fixes

### "spf-no-hubspot-include"

Replace your existing SPF TXT record with one that includes HubSpot's portal-specific hostname for your region. **Don't append a second `v=spf1` record** — RFC 7208 §3.2 disallows multiple SPF records on the same domain (`PermError`). Merge the existing mechanisms into one record:

```
"v=spf1 include:_spf.your-existing-provider.com include:12345678.spf04.hubspotemail.net -all"
```

### "spf-all-mid-record"

Move the `all` mechanism to the end of the record. Anything after it is silently ignored by validators.

```diff
- "v=spf1 ~all include:12345678.spf04.hubspotemail.net"
+ "v=spf1 include:12345678.spf04.hubspotemail.net ~all"
```

### "dkim-missing"

Get the CNAME targets from HubSpot's UI: Settings → Marketing → Email → Email sending domain → Manage DNS records. Add both `hs1-<portal-id>._domainkey` and `hs2-<portal-id>._domainkey` CNAME records to your DNS zone.

### "dmarc-missing" (warn-only)

Add a baseline DMARC record with `p=none` to start collecting reports without affecting delivery:

```
_dmarc.yourdomain.example.com.    TXT    "v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.example.com"
```

After 2-4 weeks of clean reports (no third-party services failing alignment), progress to `p=quarantine`, then `p=reject`. The skill plan covers this progression in detail (separate concern; out of framework scope at v1.8.0).

## Why this matters

Email auth is silently broken; deliverability degrades for weeks until users notice nothing is arriving. Recipient mail servers (Gmail, Apple Mail, Outlook) treat unauthenticated messages as low-reputation, often:

- Adding a "via amazonses.com" tag in the From: line
- Routing to spam
- Dropping the connection during SMTP

The framework can't fix consumer-side DNS (that's the consumer's authoritative DNS provider's job), but it can refuse to declare a deploy "ready" when email auth is broken. `PREFLIGHT_EMAIL_DNS` failing is a hard fail (except `dmarc-missing`, which is warn-only) — surfaces the problem before the welcome email goes silently into the spam pit.
