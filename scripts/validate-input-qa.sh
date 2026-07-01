#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$ROOT_DIR/qa/input-text-harness.html"
TMP_DIR="$(mktemp -d /tmp/sidescreen-input-qa.XXXXXX)"
TMP_JS="$TMP_DIR/harness.js"
trap 'rm -rf "$TMP_DIR"' EXIT
REPORTS=()

usage() {
    echo "Usage: ./scripts/validate-input-qa.sh [--report path.json ...]"
}

require_value() {
    local option="$1"
    local value="${2:-}"
    if [ -z "$value" ]; then
        echo "$option requires a value" >&2
        usage >&2
        exit 1
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --report)
            require_value "$1" "${2:-}"
            REPORTS+=("${2:-}")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            REPORTS+=("$1")
            shift
            ;;
    esac
done

if [ ! -f "$HARNESS" ]; then
    echo "Input QA harness missing: $HARNESS"
    exit 1
fi

python3 - "$HARNESS" "$TMP_JS" "${REPORTS[@]}" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import json
import sys

html_path = Path(sys.argv[1])
js_path = Path(sys.argv[2])
report_paths = [Path(value) for value in sys.argv[3:] if value]
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
    "backend-select",
    "transport-select",
    "layout-input",
    "keyboard-model",
    "mouse-model",
    "observations",
    "manual-checks",
    "testCase.expected.length",
    "actualLength",
    "firstMismatch",
]

missing = [item for item in required if item not in text]
if missing:
    raise SystemExit("required QA marker missing: " + ", ".join(missing))

print("HTML parsed and required QA markers found")

for report_path in report_paths:
    if not report_path.exists():
        raise SystemExit(f"report missing: {report_path}")

    data = json.loads(report_path.read_text(encoding="utf-8"))
    tool = data.get("tool")
    if tool not in {"Side Screen Input QA", "Side Screen Input QA Checklist"}:
        raise SystemExit(f"unexpected report tool in {report_path}: {tool!r}")

    forbidden_keys = {
        "actual",
        "actualText",
        "typedText",
        "inputText",
        "expected",
        "expectedText",
        "clipboard",
        "password",
        "token",
    }

    def walk(value, path="report"):
        if isinstance(value, dict):
            for key, child in value.items():
                if key in forbidden_keys:
                    raise SystemExit(f"sensitive/raw-text key {path}.{key} found in {report_path}")
                walk(child, f"{path}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, f"{path}[{index}]")

    walk(data)

    if tool == "Side Screen Input QA":
        context = data.get("context") or {}
        if not context.get("backend") or not context.get("keyboardLayout"):
            raise SystemExit(f"report missing backend/layout context: {report_path}")
        for item in data.get("textCases", []):
            for required_key in ("id", "expectedLength", "actualLength", "passed", "firstMismatch"):
                if required_key not in item:
                    raise SystemExit(f"text case missing {required_key} in {report_path}")
    else:
        metadata = data.get("metadata") or {}
        if not metadata.get("backend") or not metadata.get("keyboardLayout"):
            raise SystemExit(f"checklist missing backend/layout metadata: {report_path}")
        for section in ("streamChecks", "keyboardChecks", "mouseChecks"):
            if not data.get(section):
                raise SystemExit(f"checklist missing {section}: {report_path}")

    print(f"JSON report OK: {report_path}")
PY

if command -v node >/dev/null 2>&1; then
    node --check "$TMP_JS"
    echo "JavaScript syntax OK"
else
    echo "⚠️  node unavailable; skipped JavaScript syntax check"
fi

echo "Input QA harness OK: $HARNESS"
