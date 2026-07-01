#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$ROOT_DIR/qa/input-text-harness.html"

if [ ! -f "$HARNESS" ]; then
    echo "❌ Input QA harness not found: $HARNESS"
    exit 1
fi

open "$HARNESS"

echo "Opened Side Screen Input QA:"
echo "  $HARNESS"
echo ""
echo "Connect Side Screen, type into the page from Android, then download the JSON report."
echo "Keep that report next to the qa-evidence folder for the same run."
