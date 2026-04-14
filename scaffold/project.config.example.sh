# scaffold/project.config.example.sh
#
# Project configuration. Copy to project.config.sh and fill in values.
# project.config.sh is gitignored — never commit real values.

# HubSpot account
HUBSPOT_PORTAL_ID=""           # Portal ID (e.g. 147959629)
HUBSPOT_REGION=""              # eu1 or na1
KEYCHAIN_PREFIX=""             # Keychain service prefix (e.g. dml)

# Project
DOMAIN=""                      # Page domain (e.g. heard.digitalmercenaries.ai)
DM_UPLOAD_PATH=""              # Design Manager path (e.g. /heard)
GA4_MEASUREMENT_ID=""          # Google Analytics 4 ID (e.g. G-XXXXXXXXXX)

# Populated by post-apply.sh after terraform apply
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
