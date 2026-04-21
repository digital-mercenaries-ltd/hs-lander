# scaffold/project.config.example.sh
#
# project.config.sh sources account + project config from ~/.config/hs-lander/.
# Copy this file to project.config.sh (gitignored) and set the two names below.
#
# Account configs live at: ~/.config/hs-lander/<account>/config.sh
# Project configs live at: ~/.config/hs-lander/<account>/<project>.sh
#
# See the framework docs for setup:
# https://github.com/digital-mercenaries-ltd/hs-lander/blob/main/docs/framework.md

HS_LANDER_ACCOUNT=""     # directory name under ~/.config/hs-lander/
HS_LANDER_PROJECT=""     # project config filename (without .sh)

# shellcheck source=/dev/null
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
# shellcheck source=/dev/null
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
