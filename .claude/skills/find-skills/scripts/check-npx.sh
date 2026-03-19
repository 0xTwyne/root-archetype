#!/bin/bash
set -euo pipefail

# Check if npx is available for skill discovery.
# Exit 0 = available, Exit 1 = not available.

if command -v npx &>/dev/null; then
  NPX_VERSION="$(npx --version 2>/dev/null || echo "unknown")"
  echo "OK: npx is available (version: $NPX_VERSION)"
  exit 0
else
  echo "NOT AVAILABLE: npx is not installed."
  echo ""
  echo "To enable skill discovery, install Node.js:"
  echo "  - https://nodejs.org (includes npm and npx)"
  echo "  - Or: brew install node / apt install nodejs npm"
  echo ""
  echo "After installing, you can search for skills with:"
  echo "  npx skills find <query>"
  exit 1
fi
