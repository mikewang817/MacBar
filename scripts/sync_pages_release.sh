#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync_pages_release.sh [--dry-run]

Sync the latest GitHub Release zip to the local website branch and deploy it to
Cloudflare Pages without pushing the website branch to GitHub.
EOF
}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command git
require_command curl
require_command python3
require_command npx
require_command rg

REPO_ROOT="$(git rev-parse --show-toplevel)"
WEBSITE_BRANCH="${WEBSITE_BRANCH:-codex/website-local}"
PAGES_PROJECT="${PAGES_PROJECT:-macbar}"
RELEASE_REPO="${RELEASE_REPO:-mikewang817/MacBar}"
WRANGLER_CONFIG="${HOME}/Library/Preferences/.wrangler/config/default.toml"

cd "$REPO_ROOT"

if ! git show-ref --verify --quiet "refs/heads/${WEBSITE_BRANCH}"; then
  echo "Local website branch '${WEBSITE_BRANCH}' does not exist." >&2
  exit 1
fi

if git worktree list --porcelain | rg -q "^branch refs/heads/${WEBSITE_BRANCH}\$"; then
  echo "Website branch '${WEBSITE_BRANCH}' is already checked out in another worktree." >&2
  echo "Switch away from it and rerun this script." >&2
  exit 1
fi

RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases/latest")"

RELEASE_INFO="$(
  printf '%s' "$RELEASE_JSON" | python3 -c '
import json
import sys

release = json.load(sys.stdin)
tag = release["tag_name"]
version = tag[1:] if tag.startswith("v") else tag
preferred = f"MacBar-v{version}.zip"
asset_name = None
asset_url = None
release_name = release.get("name") or f"MacBar v{version}"
release_page_url = release.get("html_url") or f"https://github.com/mikewang817/MacBar/releases/tag/{tag}"

for asset in release.get("assets", []):
    if asset["name"] == preferred:
        asset_name = asset["name"]
        asset_url = asset["browser_download_url"]
        break

if asset_url is None:
    for asset in release.get("assets", []):
        if asset["name"].endswith(".zip"):
            asset_name = asset["name"]
            asset_url = asset["browser_download_url"]
            break

if asset_url is None or asset_name is None:
    raise SystemExit("Could not find a zip asset in the latest GitHub Release.")

print(tag)
print(version)
print(release_name)
print(release_page_url)
print(asset_name)
print(asset_url)
'
)"

TAG_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '1p')"
RELEASE_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '3p')"
RELEASE_PAGE_URL="$(printf '%s\n' "$RELEASE_INFO" | sed -n '4p')"
ASSET_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '5p')"
ASSET_URL="$(printf '%s\n' "$RELEASE_INFO" | sed -n '6p')"

if [[ -z "$TAG_NAME" || -z "$RELEASE_NAME" || -z "$RELEASE_PAGE_URL" || -z "$ASSET_NAME" || -z "$ASSET_URL" ]]; then
  echo "Failed to parse latest GitHub Release metadata." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macbar-pages-sync.XXXXXX")"
WORKTREE_DIR="${TMP_DIR}/website-worktree"

cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

git worktree add --quiet "$WORKTREE_DIR" "$WEBSITE_BRANCH"
cd "$WORKTREE_DIR"

if [[ ! -d website ]]; then
  echo "The website directory is missing on branch '${WEBSITE_BRANCH}'." >&2
  exit 1
fi

mkdir -p website/downloads
curl -fL "$ASSET_URL" -o "website/downloads/${ASSET_NAME}"
find website/downloads -maxdepth 1 -type f -name 'MacBar-v*.zip' ! -name "${ASSET_NAME}" -delete
printf '/download/latest /downloads/%s 302\n' "${ASSET_NAME}" > website/_redirects
MACBAR_TAG_NAME="$TAG_NAME" \
MACBAR_RELEASE_NAME="$RELEASE_NAME" \
MACBAR_RELEASE_PAGE_URL="$RELEASE_PAGE_URL" \
MACBAR_ASSET_NAME="$ASSET_NAME" \
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "version": os.environ["MACBAR_TAG_NAME"].lstrip("vV"),
    "name": os.environ["MACBAR_RELEASE_NAME"],
    "download_url": f'https://macbar.app/downloads/{os.environ["MACBAR_ASSET_NAME"]}',
    "release_notes_url": os.environ["MACBAR_RELEASE_PAGE_URL"],
}

Path("website/update.json").write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete. Latest release is ${TAG_NAME}."
  echo "Would sync website branch '${WEBSITE_BRANCH}' and deploy to Pages project '${PAGES_PROJECT}'."
  exit 0
fi

git add website/_redirects website/update.json website/downloads
if ! git diff --cached --quiet; then
  git commit -m "website: sync Cloudflare download to ${TAG_NAME}" >/dev/null
  echo "Committed website branch update for ${TAG_NAME} on ${WEBSITE_BRANCH}."
else
  echo "Website branch already points to ${TAG_NAME}; no local commit needed."
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" && -f "$WRANGLER_CONFIG" ]]; then
  TOKEN="$(
    npx --yes wrangler auth token 2>/dev/null | awk 'NF { line = $0 } END { print line }' || true
  )"
  if [[ -z "$TOKEN" ]]; then
    TOKEN="$(python3 - <<'PY'
import re
from pathlib import Path

config = Path.home() / "Library/Preferences/.wrangler/config/default.toml"
text = config.read_text()
match = re.search(r'oauth_token = "([^"]+)"', text)
if match:
    print(match.group(1))
PY
)"
  fi
  if [[ -n "$TOKEN" ]]; then
    export CLOUDFLARE_API_TOKEN="$TOKEN"
  fi
fi

npx --yes wrangler pages deploy website \
  --project-name "$PAGES_PROJECT" \
  --branch master \
  --commit-dirty=true \
  --commit-message "website: sync latest release ${TAG_NAME}" || {
    echo "Cloudflare Pages deploy failed." >&2
    echo "Run 'wrangler login' again or provide a valid CLOUDFLARE_API_TOKEN, then rerun this script." >&2
    exit 1
  }

echo "Cloudflare Pages download is now synced to ${TAG_NAME}."
