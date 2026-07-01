#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$ROOT_DIR/qa/input-text-harness.html"
STAMP="$(date '+%Y%m%d-%H%M%S')-$$"
EVIDENCE_DIR="${SIDESCREEN_QA_EVIDENCE_DIR:-}"
BACKEND="unknown"
TRANSPORT="unknown"
LAYOUT="unknown"
KEYBOARD="not-recorded"
MOUSE="not-recorded"
OBSERVATIONS=""
OPEN_HARNESS=1

usage() {
    echo "Usage: ./scripts/open-input-qa.sh [--evidence-dir dir] [--backend CGEvent|VirtualHID|unknown] [--transport USB|Tailnet|LAN|unknown] [--layout name] [--keyboard name] [--mouse name] [--observations text] [--no-open]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/open-input-qa.sh --backend CGEvent --transport USB --layout ABNT2"
    echo "  ./scripts/open-input-qa.sh --backend VirtualHID --transport Tailnet --evidence-dir qa-evidence/20260701-113541-41224"
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
        --evidence-dir)
            require_value "$1" "${2:-}"
            EVIDENCE_DIR="${2:-}"
            shift 2
            ;;
        --backend)
            require_value "$1" "${2:-}"
            BACKEND="${2:-}"
            shift 2
            ;;
        --transport)
            require_value "$1" "${2:-}"
            TRANSPORT="${2:-}"
            shift 2
            ;;
        --layout)
            require_value "$1" "${2:-}"
            LAYOUT="${2:-}"
            shift 2
            ;;
        --keyboard)
            require_value "$1" "${2:-}"
            KEYBOARD="${2:-}"
            shift 2
            ;;
        --mouse)
            require_value "$1" "${2:-}"
            MOUSE="${2:-}"
            shift 2
            ;;
        --observations)
            require_value "$1" "${2:-}"
            OBSERVATIONS="${2:-}"
            shift 2
            ;;
        --no-open)
            OPEN_HARNESS=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ ! -f "$HARNESS" ]; then
    echo "Input QA harness not found: $HARNESS" >&2
    exit 1
fi

case "$BACKEND" in
    CGEvent|cgevent)
        BACKEND="CGEvent"
        ;;
    VirtualHID|virtualhid|"Virtual HID"|"virtual hid")
        BACKEND="Virtual HID"
        ;;
    unknown|auto|"")
        BACKEND="unknown"
        ;;
    *)
        echo "--backend must be CGEvent, VirtualHID, or unknown." >&2
        exit 1
        ;;
esac

case "$TRANSPORT" in
    USB|usb)
        TRANSPORT="USB"
        ;;
    Tailnet|tailnet|TAILNET)
        TRANSPORT="Tailnet"
        ;;
    LAN|lan)
        TRANSPORT="LAN"
        ;;
    unknown|auto|"")
        TRANSPORT="unknown"
        ;;
    *)
        echo "--transport must be USB, Tailnet, LAN, or unknown." >&2
        exit 1
        ;;
esac

if [ -z "$EVIDENCE_DIR" ]; then
    EVIDENCE_DIR="$ROOT_DIR/qa-evidence/input-qa-$STAMP"
elif [[ "$EVIDENCE_DIR" != /* ]]; then
    EVIDENCE_DIR="$ROOT_DIR/$EVIDENCE_DIR"
fi

mkdir -p "$EVIDENCE_DIR"

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
CHECKLIST_JSON="$EVIDENCE_DIR/input-qa-checklist.json"
CHECKLIST_MD="$EVIDENCE_DIR/input-qa-checklist.md"

cat > "$CHECKLIST_JSON" <<EOF
{
  "tool": "Side Screen Input QA Checklist",
  "generatedAt": "$(json_escape "$GENERATED_AT")",
  "harness": "$(json_escape "$HARNESS")",
  "evidenceDir": "$(json_escape "$EVIDENCE_DIR")",
  "metadata": {
    "backend": "$(json_escape "$BACKEND")",
    "transport": "$(json_escape "$TRANSPORT")",
    "keyboardLayout": "$(json_escape "$LAYOUT")",
    "keyboard": "$(json_escape "$KEYBOARD")",
    "mouse": "$(json_escape "$MOUSE")",
    "observations": "$(json_escape "$OBSERVATIONS")",
    "privacy": "Do not record typed text, passwords, tokens, customer data, or clipboard contents."
  },
  "comparisonAxes": ["backend", "transport", "keyboardLayout", "keyboard", "mouse"],
  "streamChecks": [
    { "id": "duration-recorded", "label": "Duration recorded in evidence manifest", "status": "pending" },
    { "id": "video-p-observed", "label": "Video observed on port P", "status": "pending" },
    { "id": "input-p-plus-1-observed", "label": "Input observed on port P+1", "status": "pending" },
    { "id": "backend-visible", "label": "Active backend visible in Mac or Android diagnostics", "status": "pending" }
  ],
  "keyboardChecks": [
    { "id": "letters-numbers", "label": "A-Z and numbers", "status": "pending" },
    { "id": "modifiers", "label": "Shift, Control, Option/Alt, Command/Meta", "status": "pending" },
    { "id": "control-keys", "label": "Enter, Escape, Tab, Backspace, Delete, arrows", "status": "pending" },
    { "id": "accents-dead-keys", "label": "Accents/dead keys or TextCommit path", "status": "pending" },
    { "id": "shortcuts", "label": "Command+C, Command+V, Command+A, Command+Tab", "status": "pending" },
    { "id": "no-stuck-keys", "label": "No stuck keys after focus/network loss", "status": "pending" }
  ],
  "mouseChecks": [
    { "id": "relative-move", "label": "Relative pointer movement", "status": "pending" },
    { "id": "buttons", "label": "Left, right, and middle buttons", "status": "pending" },
    { "id": "drag", "label": "Drag starts, moves, and releases", "status": "pending" },
    { "id": "scroll-vertical", "label": "Vertical scroll", "status": "pending" },
    { "id": "scroll-horizontal", "label": "Horizontal scroll when hardware supports it", "status": "pending" },
    { "id": "capture-loss-release", "label": "Pointer capture loss sends AllInputsUp", "status": "pending" }
  ],
  "textReportExpected": "Attach sidescreen-input-qa-*.json downloaded from the harness. It stores lengths, mismatch index, shortcut IDs, and manual check states, not typed text."
}
EOF

cat > "$CHECKLIST_MD" <<EOF
# Side Screen Input QA Checklist

| Campo | Valor |
|---|---|
| Backend | $BACKEND |
| Transporte | $TRANSPORT |
| Layout | $LAYOUT |
| Teclado | $KEYBOARD |
| Mouse | $MOUSE |
| Observações | $OBSERVATIONS |

## Checklist

- [ ] Duração registrada no manifesto de evidência.
- [ ] Vídeo observado na porta P.
- [ ] Input observado na porta P+1.
- [ ] Backend ativo aparece no diagnóstico Mac ou Android.
- [ ] Teclado: letras, números, modificadores, teclas de controle e acentos/dead keys.
- [ ] Mouse: movimento relativo, botões, drag, scroll vertical/horizontal.
- [ ] Perda de foco/rede/pointer capture solta tudo, sem tecla ou botão preso.
- [ ] Relatório \`sidescreen-input-qa-*.json\` baixado do harness está nesta pasta.

Não cole aqui texto digitado, senhas, tokens, dados de cliente ou conteúdo de clipboard.
EOF

"$SCRIPT_DIR/validate-input-qa.sh" --report "$CHECKLIST_JSON" >/dev/null

if [ "$OPEN_HARNESS" -eq 1 ]; then
    if command -v open >/dev/null 2>&1; then
        open "$HARNESS"
        echo "Opened Side Screen Input QA:"
    else
        echo "open command unavailable; open the harness manually: $HARNESS" >&2
        echo "Side Screen Input QA harness:"
    fi
else
    echo "Side Screen Input QA harness:"
fi

echo "  $HARNESS"
echo ""
echo "Checklist written to:"
echo "  $CHECKLIST_JSON"
echo "  $CHECKLIST_MD"
echo ""
echo "Connect Side Screen, type into the page from Android, then download the JSON report into:"
echo "  $EVIDENCE_DIR"
echo ""
echo "The report records lengths, mismatch index, shortcut IDs, backend/layout metadata, and checkbox states. It must not record typed text."
