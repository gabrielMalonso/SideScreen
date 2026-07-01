#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
STAMP="$(date '+%Y%m%d-%H%M%S')-$$"
OUT_DIR="$ROOT_DIR/qa-evidence/$STAMP"
START_EPOCH="$(date +%s)"
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"
ORIGINAL_ARGS=("$@")
DEFAULT_APK_PATH="$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
APK_PATH="${SIDESCREEN_APK:-$DEFAULT_APK_PATH}"
APK_SOURCE="default debug APK"
APK_SELECTED_EXPLICITLY=0
if [ -n "${SIDESCREEN_APK:-}" ]; then
    APK_SOURCE="SIDESCREEN_APK"
    APK_SELECTED_EXPLICITLY=1
fi
PORT="${SIDESCREEN_PORT:-54321}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65534 ]; then
    echo "SIDESCREEN_PORT must be 1..65534 because remote input uses port + 1." >&2
    exit 1
fi
INPUT_PORT=$((PORT + 1))
DURATION=15
RUN_SMOKE=0
EXPECT_STREAM=0
TAILNET_HOST=""
NO_REVERSE=0
TAP_CONNECT=0
SMOKE_STATUS=0

usage() {
    echo "Usage: ./scripts/collect-qa-evidence.sh [--smoke] [--apk path] [--expect-stream] [--no-reverse] [--tap-connect] [--duration seconds] [--tailnet-host host]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/collect-qa-evidence.sh"
    echo "  ./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream"
    echo "  ./scripts/collect-qa-evidence.sh --smoke --apk AndroidClient/app/build/outputs/apk/release/app-release.apk --duration 1800 --expect-stream"
    echo "  ./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream --tailnet-host mac.example.ts.net"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --smoke)
            RUN_SMOKE=1
            shift
            ;;
        --apk)
            if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
                echo "--apk requires a path" >&2
                exit 1
            fi
            RUN_SMOKE=1
            APK_PATH="$2"
            APK_SOURCE="--apk"
            APK_SELECTED_EXPLICITLY=1
            shift 2
            ;;
        --expect-stream)
            RUN_SMOKE=1
            EXPECT_STREAM=1
            shift
            ;;
        --duration)
            DURATION="${2:-}"
            shift 2
            ;;
        --tailnet-host)
            RUN_SMOKE=1
            TAILNET_HOST="${2:-}"
            shift 2
            ;;
        --no-reverse)
            RUN_SMOKE=1
            NO_REVERSE=1
            shift
            ;;
        --tap-connect)
            RUN_SMOKE=1
            TAP_CONNECT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
    echo "--duration must be a positive number of seconds." >&2
    exit 1
fi

if [ "$APK_SELECTED_EXPLICITLY" -eq 1 ] && [ ! -f "$APK_PATH" ]; then
    echo "Selected APK does not exist: $APK_PATH" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

transport_mode() {
    if [ "$RUN_SMOKE" -ne 1 ]; then
        echo "evidence-only"
    elif [ "$NO_REVERSE" -eq 1 ]; then
        echo "tailnet-or-network"
    else
        echo "usb-adb-reverse"
    fi
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

write_manifest() {
    local run_status="$1"
    local smoke_status="$2"
    local finished_at="${3:-}"
    local finished_epoch="${4:-}"
    local elapsed=""
    if [ -n "$finished_epoch" ]; then
        elapsed=$((finished_epoch - START_EPOCH))
    fi

    {
        echo "Side Screen QA Evidence"
        echo "Version: $VERSION"
        echo "Status: $run_status"
        echo "Started: $STARTED_AT"
        if [ -n "$finished_at" ]; then
            echo "Finished: $finished_at"
            echo "Elapsed seconds: $elapsed"
        fi
        echo "Root: $ROOT_DIR"
        echo "Evidence folder: $OUT_DIR"
        echo "Command: ./scripts/collect-qa-evidence.sh ${ORIGINAL_ARGS[*]}"
        echo "Transport mode: $(transport_mode)"
        echo "APK path: $APK_PATH"
        echo "APK source: $APK_SOURCE"
        echo "APK explicitly selected: $APK_SELECTED_EXPLICITLY"
        echo "Video port (P): $PORT"
        echo "Input port (P+1): $INPUT_PORT"
        echo "Smoke: $RUN_SMOKE"
        echo "Expect stream: $EXPECT_STREAM"
        echo "Requested duration seconds: $DURATION"
        echo "Tailnet host: ${TAILNET_HOST:-none}"
        echo "No reverse: $NO_REVERSE"
        echo "Tap connect: $TAP_CONNECT"
        echo "Android smoke exit status: $smoke_status"
    } > "$OUT_DIR/manifest.txt"

    {
        echo "{"
        echo "  \"tool\": \"Side Screen QA Evidence\","
        echo "  \"version\": \"$(json_escape "$VERSION")\","
        echo "  \"status\": \"$(json_escape "$run_status")\","
        echo "  \"startedAt\": \"$(json_escape "$STARTED_AT")\","
        if [ -n "$finished_at" ]; then
            echo "  \"finishedAt\": \"$(json_escape "$finished_at")\","
            echo "  \"elapsedSeconds\": $elapsed,"
        else
            echo "  \"finishedAt\": null,"
            echo "  \"elapsedSeconds\": null,"
        fi
        echo "  \"root\": \"$(json_escape "$ROOT_DIR")\","
        echo "  \"evidenceFolder\": \"$(json_escape "$OUT_DIR")\","
        echo "  \"command\": \"$(json_escape "./scripts/collect-qa-evidence.sh ${ORIGINAL_ARGS[*]}")\","
        echo "  \"transportMode\": \"$(json_escape "$(transport_mode)")\","
        echo "  \"apk\": { \"path\": \"$(json_escape "$APK_PATH")\", \"source\": \"$(json_escape "$APK_SOURCE")\", \"explicitlySelected\": $APK_SELECTED_EXPLICITLY },"
        echo "  \"ports\": { \"videoP\": $PORT, \"inputPPlus1\": $INPUT_PORT },"
        echo "  \"smoke\": $RUN_SMOKE,"
        echo "  \"expectStream\": $EXPECT_STREAM,"
        echo "  \"requestedDurationSeconds\": $DURATION,"
        echo "  \"tailnetHost\": \"$(json_escape "${TAILNET_HOST:-}")\","
        echo "  \"noReverse\": $NO_REVERSE,"
        echo "  \"tapConnect\": $TAP_CONNECT,"
        echo "  \"androidSmokeExitStatus\": \"$(json_escape "$smoke_status")\""
        echo "}"
    } > "$OUT_DIR/manifest.json"
}

write_readme() {
cat > "$OUT_DIR/README.md" <<EOF
# Rodada de Evidências QA do Side Screen

Esta pasta é o pacote auditável de uma rodada de QA.

| Campo | Valor |
|---|---|
| Início | $STARTED_AT |
| Modo de transporte | $(transport_mode) |
| APK configurado | $APK_PATH |
| Origem do APK | $APK_SOURCE |
| Duração solicitada | ${DURATION}s |
| Porta de vídeo (P) | $PORT |
| Porta de input (P+1) | $INPUT_PORT |
| Tailnet host | ${TAILNET_HOST:-none} |
| Exige stream | $EXPECT_STREAM |
| Tap connect | $TAP_CONNECT |

## Comece Aqui

1. Leia \`manifest.txt\` ou \`manifest.json\` para os metadados da rodada.
2. Leia \`qa-observation-summary.txt\` para linhas observadas de stream, input e backend.
3. Leia \`android-device-smoke.txt\` quando a rodada tiver smoke Android.
4. Anexe nesta pasta o relatório \`sidescreen-input-qa-*.json\` baixado pelo \`./scripts/open-input-qa.sh\` para QA de input com hardware.

## Evidência de Aprovação

| Requisito | Caminho de evidência |
|---|---|
| Duração e modo explícitos | \`manifest.txt\`, \`manifest.json\` |
| APK instalado no smoke | \`manifest.txt\`, \`manifest.json\`, \`selected-apk.txt\`, \`android-device-smoke.txt\` |
| Vídeo usa a porta P | \`manifest.txt\`, \`android-device-smoke.txt\` |
| Input usa P+1 | \`manifest.txt\`, \`adb-reverse-list*.txt\`, \`android-device-smoke.txt\` |
| Stream observado | \`qa-observation-summary.txt\`, \`android-device-smoke.txt\` |
| Backend observado quando disponível | \`qa-observation-summary.txt\`, \`mac-runtime-log-tail.txt\`, diagnósticos Android |
| Rota/status Tailnet | \`tailscale-status.txt\`, \`tailnet-diagnostics.txt\` |
| Checklist/relatório de input QA | \`input-qa-checklist.*\`, \`sidescreen-input-qa-*.json\` |

## Checks que Exigem Hardware

Não aprove uso diário por USB ou Tailnet sem uma rodada de 1800 segundos com stream e input observados. Para QA de input com hardware, compare pelo menos uma rodada CGEvent e uma rodada Virtual HID quando Virtual HID estiver disponível.
EOF
}

capture() {
    local label="$1"
    local file="$2"
    shift 2

    {
        echo "# $label"
        echo "Command: $*"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""
    } > "$OUT_DIR/$file"

    "$@" >> "$OUT_DIR/$file" 2>&1
    local status=$?

    {
        echo ""
        echo "Exit status: $status"
        echo "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    } >> "$OUT_DIR/$file"

    return "$status"
}

capture_shell() {
    local label="$1"
    local file="$2"
    local command="$3"
    capture "$label" "$file" bash -lc "$command"
}

write_selected_apk_evidence() {
    {
        echo "# Selected APK"
        echo "Path: $APK_PATH"
        echo "Source: $APK_SOURCE"
        echo "Explicitly selected: $APK_SELECTED_EXPLICITLY"
        echo ""
        if [ -f "$APK_PATH" ]; then
            ls -lh "$APK_PATH"
            if command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "$APK_PATH"
            else
                echo "shasum unavailable"
            fi
        else
            echo "Status: missing at evidence collection time"
        fi
    } > "$OUT_DIR/selected-apk.txt"
}

capture_android_diag_full() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb unavailable" > "$OUT_DIR/android-diag-full.txt"
        return
    fi
    capture_shell \
        "Android app diagnostic log full" \
        "android-diag-full.txt" \
        ". '$SCRIPT_DIR/adb-env.sh' >/dev/null 2>&1 && sidescreen_select_adb_device >/dev/null 2>&1 && adb -s \"\$ANDROID_SERIAL\" shell run-as com.sidescreen.app cat files/diag.log"
}

print_matches() {
    local pattern="$1"
    local fallback="$2"
    shift 2

    local tmp
    tmp="$(mktemp /tmp/sidescreen-qa-lines.XXXXXX)"
    if grep -E "$pattern" "$@" > "$tmp" 2>/dev/null; then
        tail -30 "$tmp"
    else
        echo "$fallback"
    fi
    rm -f "$tmp"
}

write_observation_summary() {
    local summary="$OUT_DIR/qa-observation-summary.txt"
    {
        echo "# QA Observation Summary"
        echo ""
        echo "Transport mode: $(transport_mode)"
        echo "APK: $APK_PATH"
        echo "APK source: $APK_SOURCE"
        echo "Requested duration seconds: $DURATION"
        echo "Video port (P): $PORT"
        echo "Input port (P+1): $INPUT_PORT"
        echo "Tailnet host: ${TAILNET_HOST:-none}"
        echo ""
        echo "## Stream/input evidence"
        if [ -f "$OUT_DIR/android-device-smoke.txt" ] || [ -f "$OUT_DIR/android-diag-full.txt" ]; then
            print_matches \
                "Stream connection and frame flow observed|Recent frame flow observed|No recent frame flow|First video frame|First output frame|Frame heartbeat: total=[1-9][0-9]*|Frames received: [1-9][0-9]*|Decode stats: input=[1-9][0-9]*|Input channel observed on $INPUT_PORT|Input channel connected to .*:$INPUT_PORT" \
                "No stream/input observation lines found in android-device-smoke.txt" \
                "$OUT_DIR/android-device-smoke.txt" "$OUT_DIR/android-diag-full.txt"
        else
            echo "android-device-smoke.txt not present; smoke was not requested."
        fi
        echo ""
        echo "## Backend evidence"
        if [ -f "$OUT_DIR/android-device-smoke.txt" ] || [ -f "$OUT_DIR/android-diag-full.txt" ] || [ -f "$OUT_DIR/mac-runtime-log-tail.txt" ]; then
            print_matches \
                "backend=(CGEvent|Virtual HID)|Input: (CGEvent|Virtual HID) active|Input backend: (CGEvent|Virtual HID)|Active backend|Virtual HID" \
                "No backend observation lines found." \
                "$OUT_DIR/android-device-smoke.txt" "$OUT_DIR/android-diag-full.txt" "$OUT_DIR/mac-runtime-log-tail.txt"
        else
            echo "No runtime logs available."
        fi
        echo ""
        echo "## ADB reverse P/P+1"
        if [ -f "$OUT_DIR/adb-reverse-list-after.txt" ]; then
            grep -E "tcp:$PORT tcp:$PORT|tcp:$INPUT_PORT tcp:$INPUT_PORT" "$OUT_DIR/adb-reverse-list-after.txt" || echo "P/P+1 reverse pair not observed after run."
        elif [ -f "$OUT_DIR/adb-reverse-list-before.txt" ]; then
            grep -E "tcp:$PORT tcp:$PORT|tcp:$INPUT_PORT tcp:$INPUT_PORT" "$OUT_DIR/adb-reverse-list-before.txt" || echo "P/P+1 reverse pair not observed before run."
        else
            echo "ADB reverse list unavailable."
        fi
        echo ""
        echo "## Human attachments expected"
        echo "- Input QA report: sidescreen-input-qa-*.json"
        echo "- Manual notes only if needed; do not paste typed text or secrets."
    } > "$summary"
}

write_manifest "running" "not-run"
write_readme

capture "Git status" "git-status.txt" git -C "$ROOT_DIR" status --short
capture "Git diff stat" "git-diff-stat.txt" git -C "$ROOT_DIR" diff --stat
capture "Preflight full" "preflight.txt" "$SCRIPT_DIR/preflight.sh" --full

if command -v adb >/dev/null 2>&1; then
    capture "ADB devices" "adb-devices.txt" adb devices -l
    capture "ADB reverse list before smoke" "adb-reverse-list-before.txt" adb reverse --list
else
    echo "adb unavailable" > "$OUT_DIR/adb-devices.txt"
    echo "adb unavailable" > "$OUT_DIR/adb-reverse-list-before.txt"
fi

if command -v tailscale >/dev/null 2>&1; then
    capture "Tailscale status" "tailscale-status.txt" tailscale status
    capture "Side Screen Tailnet diagnostics" "tailnet-diagnostics.txt" "$SCRIPT_DIR/tailnet-diagnostics.sh"
else
    echo "tailscale unavailable" > "$OUT_DIR/tailscale-status.txt"
fi

capture_shell "Artifacts" "artifacts.txt" "cd '$ROOT_DIR' && ls -lh SideScreen.app SideScreen-'$VERSION'-mac-arm64.dmg AndroidClient/app/build/outputs/apk/debug/app-debug.apk AndroidClient/app/build/outputs/apk/release/app-release.apk AndroidClient/app/build/outputs/bundle/release/app-release.aab 2>&1"
write_selected_apk_evidence
capture "Release checksums" "checksums.txt" "$SCRIPT_DIR/generate-checksums.sh" --stdout
capture "Android release signing" "android-release-signing.txt" "$SCRIPT_DIR/verify-android-signing.sh"
capture_shell "Input QA harness" "input-qa-harness.txt" "cd '$ROOT_DIR' && ls -lh qa/input-text-harness.html scripts/open-input-qa.sh && shasum -a 256 qa/input-text-harness.html scripts/open-input-qa.sh"
capture "Input QA validation" "input-qa-validation.txt" "$SCRIPT_DIR/validate-input-qa.sh"

if [ -d "$ROOT_DIR/SideScreen.app" ]; then
    capture "Mac app codesign" "mac-codesign.txt" codesign --verify --deep --strict --verbose=2 "$ROOT_DIR/SideScreen.app"
    capture "Mac app Gatekeeper assessment" "mac-spctl-app.txt" spctl -a -vv "$ROOT_DIR/SideScreen.app"
    capture "Mac distribution readiness" "mac-distribution.txt" "$SCRIPT_DIR/verify-mac-distribution.sh"
fi

DMG="$ROOT_DIR/SideScreen-$VERSION-mac-arm64.dmg"
if [ -f "$DMG" ]; then
    capture "Mac DMG Gatekeeper assessment" "mac-spctl-dmg.txt" spctl -a -vv -t open "$DMG"
fi

if [ "$RUN_SMOKE" -eq 1 ]; then
    smoke_args=(--duration "$DURATION")
    if [ "$APK_SELECTED_EXPLICITLY" -eq 1 ]; then
        smoke_args+=(--apk "$APK_PATH")
    fi
    if [ "$EXPECT_STREAM" -eq 1 ]; then
        smoke_args+=(--expect-stream)
    fi
    if [ -n "$TAILNET_HOST" ]; then
        smoke_args+=(--tailnet-host "$TAILNET_HOST")
    fi
    if [ "$NO_REVERSE" -eq 1 ]; then
        smoke_args+=(--no-reverse)
    fi
    if [ "$TAP_CONNECT" -eq 1 ]; then
        smoke_args+=(--tap-connect)
    fi
    capture "Android device smoke" "android-device-smoke.txt" "$SCRIPT_DIR/android-device-smoke.sh" "${smoke_args[@]}"
    SMOKE_STATUS=$?
    write_selected_apk_evidence
    capture_android_diag_full
fi

if command -v adb >/dev/null 2>&1; then
    capture "ADB reverse list after smoke" "adb-reverse-list-after.txt" adb reverse --list
fi

capture_shell "Mac runtime log tail" "mac-runtime-log-tail.txt" "if [ -f /tmp/sidescreen.log ]; then tail -240 /tmp/sidescreen.log; else echo '/tmp/sidescreen.log missing'; fi"
write_observation_summary

FINISHED_EPOCH="$(date +%s)"
FINISHED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"
write_manifest "finished" "$SMOKE_STATUS" "$FINISHED_AT" "$FINISHED_EPOCH"

echo "Evidence written to: $OUT_DIR"
echo "Start with: $OUT_DIR/README.md"

if [ "$RUN_SMOKE" -eq 1 ] && [ "$SMOKE_STATUS" -ne 0 ]; then
    exit "$SMOKE_STATUS"
fi

exit 0
