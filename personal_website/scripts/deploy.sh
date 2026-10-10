#!/usr/bin/env bash
# deploy.sh
#
# Purpose:
#   Copy personal_website/site/ to the Pi's web root, so "edit a file on the
#   laptop, run this" is the whole release process.
#
# Inputs:
#   --dry-run         optional: list what would change, change nothing.
#   base/pi.env       PI_USER and PI_ADDRESS (see base/pi.env.example).
#                     Override the path with PI_ENV_FILE.
#   Your normal SSH key; there should be no password prompt.
#
# Side effects:
#   Writes to /var/www/personal_website on the Pi. --delete removes files there
#   that are not in the repo, so the Pi's copy always matches site/. Files are
#   made world-readable (644/755) so nginx's user can serve them whatever the
#   laptop's file modes are.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$(cd "${SCRIPT_DIR}/../site" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PI_ENV_FILE:-${REPO_ROOT}/base/pi.env}"
REMOTE_ROOT="/var/www/personal_website"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Create it from base/pi.env.example." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"
: "${PI_USER:?PI_USER is not set in ${ENV_FILE}}"
: "${PI_ADDRESS:?PI_ADDRESS is not set in ${ENV_FILE}}"

DRY_RUN=()
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=(--dry-run)
  echo "Dry run: nothing will be changed."
fi

# Trailing slash on the source means "the contents of site/", not site/ itself.
rsync -av --delete --chmod=D755,F644 "${DRY_RUN[@]}" \
  "${SITE_DIR}/" "${PI_USER}@${PI_ADDRESS}:${REMOTE_ROOT}/"

if [[ ${#DRY_RUN[@]} -eq 0 ]]; then
  echo "Done. Check: http://${PI_ADDRESS}/"
fi
