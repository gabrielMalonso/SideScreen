#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
OUT_DIR="$ROOT_DIR/dist"
OUT_FILE="$OUT_DIR/SHA256SUMS.txt"

usage() {
    echo "Usage: ./scripts/generate-checksums.sh [--stdout] [file ...]"
    echo ""
    echo "Without file arguments, checksums local Remote Mac release artifacts."
}

WRITE_STDOUT=0
FILES=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --stdout)
            WRITE_STDOUT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

if [ "${#FILES[@]}" -eq 0 ]; then
    FILES=(
        "$ROOT_DIR/RemoteMac-$VERSION-mac-arm64.dmg"
        "$ROOT_DIR/AndroidClient/app/build/outputs/apk/release/app-release.apk"
        "$ROOT_DIR/AndroidClient/app/build/outputs/bundle/release/app-release.aab"
    )
fi

for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing artifact for checksum: $file" >&2
        exit 1
    fi
done

if [ "$WRITE_STDOUT" -eq 1 ]; then
    for file in "${FILES[@]}"; do
        checksum="$(shasum -a 256 "$file" | awk '{print $1}')"
        printf "%s  %s\n" "$checksum" "$(basename "$file")"
    done
else
    mkdir -p "$OUT_DIR"
    {
        for file in "${FILES[@]}"; do
            checksum="$(shasum -a 256 "$file" | awk '{print $1}')"
            printf "%s  %s\n" "$checksum" "$(basename "$file")"
        done
    } > "$OUT_FILE"
    echo "Checksums written to: $OUT_FILE"
fi
