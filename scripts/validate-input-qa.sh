#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$ROOT_DIR/qa/input-text-harness.html"
TMP_JS="$(mktemp /tmp/sidescreen-input-qa.XXXXXX.js)"
trap 'rm -f "$TMP_JS"' EXIT

if [ ! -f "$HARNESS" ]; then
    echo "❌ Input QA harness missing: $HARNESS"
    exit 1
fi

python3 - "$HARNESS" "$TMP_JS" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

html_path = Path(sys.argv[1])
js_path = Path(sys.argv[2])
text = html_path.read_text(encoding="utf-8")

class Parser(HTMLParser):
    pass

Parser().feed(text)

try:
    start = text.index("<script>") + len("<script>")
    end = text.index("</script>", start)
except ValueError as exc:
    raise SystemExit(f"script block missing: {exc}")

js_path.write_text(text[start:end], encoding="utf-8")

required = [
    "ação, coração, amanhã, útil, você, João",
    "@ # $ % & * /",
    "teste 🧪 ✅",
    "Paste longo de 4 KB",
    "Paste grande demais",
    "Command+C",
    "Command+V",
    "Command+A",
    "downloadReport",
]

missing = [item for item in required if item not in text]
if missing:
    raise SystemExit("required QA marker missing: " + ", ".join(missing))

print("HTML parsed and required QA markers found")
PY

if command -v node >/dev/null 2>&1; then
    node --check "$TMP_JS"
    echo "JavaScript syntax OK"
else
    echo "⚠️  node unavailable; skipped JavaScript syntax check"
fi

echo "Input QA harness OK: $HARNESS"
