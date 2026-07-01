#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')

echo "======================================="
echo "  Side Screen - Release v$VERSION"
echo "======================================="
echo ""

# 1. Preflight
echo "[1/4] Preflight..."
set +e
"$ROOT_DIR/scripts/preflight.sh" --full --release
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ]; then
    if [ "$STATUS" -eq 2 ]; then
        echo ""
        echo "Distribution preflight finished with non-blocking warnings."
        echo "Fix them or rerun with SIDESCREEN_ALLOW_RELEASE_WARNINGS=1."
        echo "Signing, notarization, Gatekeeper, and Android release-signing blockers cannot be bypassed."
        if [ "${SIDESCREEN_ALLOW_RELEASE_WARNINGS:-0}" != "1" ]; then
            exit 2
        fi
    else
        echo ""
        echo "Distribution preflight failed. Fix the blockers before tagging a release."
        exit "$STATUS"
    fi
fi

# 2. Lint
echo "[2/4] Linting..."
cd "$ROOT_DIR/MacHost"
if command -v swiftlint &>/dev/null; then
    swiftlint lint --config .swiftlint.yml --strict --quiet
    echo "  Swift lint OK"
fi

cd "$ROOT_DIR/AndroidClient"
if command -v ktlint &>/dev/null; then
    ktlint "app/src/main/java/**/*.kt" --relative
    echo "  Kotlin lint OK"
fi

# 3. Push
echo "[3/4] Pushing to GitHub..."
cd "$ROOT_DIR"
if [ -n "$(git status --porcelain)" ]; then
    git status --short
    echo "Commit or stash the changes before releasing. Release should never guess what to include."
    exit 2
fi
git push

# 4. Tag & release
echo "[4/4] Creating release tag..."
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "  Tag $VERSION already exists, skipping"
else
    git tag "$VERSION"
    git push origin "$VERSION"
    echo "  Tag $VERSION pushed - GitHub Actions will build the release"
fi

echo ""
echo "======================================="
echo "  Done! Check: gh release view $VERSION"
echo "======================================="
