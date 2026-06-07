#!/usr/bin/env bash
set -euo pipefail

# check-release-exists.sh
# Check if a GitHub release already exists for the given version
# Usage: check-release-exists.sh <version>

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

VERSION="$1"

# Use the GitHub REST API directly (more reliable than `gh release view`)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${VERSION}")

echo "Release check for ${VERSION}: HTTP ${HTTP_STATUS}"

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "exists=true" >> "$GITHUB_OUTPUT"
  echo "Release ${VERSION} already exists, skipping..."
else
  echo "exists=false" >> "$GITHUB_OUTPUT"
  echo "Release ${VERSION} does not exist (HTTP ${HTTP_STATUS}), proceeding..."
fi
