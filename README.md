# hs-lander

Reusable HubSpot landing page framework — Terraform modules, shell scripts, scaffold templates, and Claude Code skill.

## What this does

Takes a landing page project (HTML templates with placeholder tokens, config file) and deploys a complete HubSpot funnel: forms, pages, welcome email, and contact segmentation.

## Usage

See [docs/framework.md](docs/framework.md) for the full guide.

```bash
# Scaffold a new project
cp -r scaffold/* /path/to/my-project/
cp -r scripts/ /path/to/my-project/scripts/

# Build and deploy
cd /path/to/my-project
npm run build && npm run setup && npm run post-apply && npm run deploy
```

## Terraform Modules

Reference in your project's `terraform/main.tf`:

```hcl
module "account_setup" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v1.0.0"
}

module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.0.0"
  # ... variables
}
```

## Licence

Proprietary — Digital Mercenaries Ltd.
