#!/usr/bin/env bash
set -euo pipefail
umask 077
if [[ ! -t 0 && -t 1 && -r /dev/tty ]]; then exec </dev/tty; fi
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RESET='' CYAN='' GREEN='' YELLOW='' BOLD=''
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  RESET=$'\e[0m'; CYAN=$'\e[36m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'
fi
line(){ printf '%s\n' '----------------------------------------'; }
section(){ printf '\n%s%s%s\n' "$CYAN" "$1" "$RESET"; line; }
info(){ printf '  %-12s %s\n' "$1" "$2"; }
fail(){ printf '%s%s%s\n' "$YELLOW" "$1" "$RESET" >&2; exit 1; }
command -v python3 >/dev/null || fail 'Python 3 is required.'
TEST_ONLY=false
case "${1:-}" in
  '') ;;
  --telegram-test) TEST_ONLY=true;;
  *) fail 'Usage: bash xzy.sh [--telegram-test]';;
esac
if ! $TEST_ONLY; then
  command -v gcloud >/dev/null || fail 'Run in Google Cloud Shell.'
  PROJECT=$(gcloud config get-value project 2>/dev/null)
  [[ -n "$PROJECT" && "$PROJECT" != '(unset)' ]] || fail 'Select a GCP project first.'
fi
IMAGE='ghcr.io/jhan2nyonigeb-bot/xzyvpn-cloudrun:latest' 
# Clear the clone output only after startup checks succeed.
if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then printf '\033[2J\033[H'; fi
printf '%s%s' "$CYAN" "$BOLD"
line
printf '        XzyVpn CloudRun v0.1.5\n        Universal Xray Deployment\n'
line
printf '%s' "$RESET"
if ! $TEST_ONLY; then
  info 'Project:' "$PROJECT"
  info 'Image:' 'XzyVpn / GHCR (automatic)'
  info 'Resources:' '1 CPU / 512 MiB'
fi
section '01 | Telegram setup'
TELEGRAM_TOKEN='' TELEGRAM_CHAT='' TELEGRAM_BOT=''
echo '  Create a bot: https://t.me/BotFather'
echo '  Open your bot and send /start first.'
read -rsp 'Enter Telegram bot token (hidden; blank skips): ' TELEGRAM_TOKEN
printf '\n'
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  TELEGRAM_CHAT=${XZY_TELEGRAM_CHAT_ID:-}
  if [[ -z "$TELEGRAM_CHAT" ]]; then
    read -rp 'Enter private numeric chat ID: ' TELEGRAM_CHAT
  fi
  info 'Chat ID:' "$TELEGRAM_CHAT"
  TELEGRAM_BOT=${XZY_TELEGRAM_BOT:-}
  if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ || ! "$TELEGRAM_CHAT" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Invalid Telegram settings.' >&2
    TELEGRAM_TOKEN=''; TELEGRAM_CHAT=''; TELEGRAM_BOT=''
  else
    echo 'Verifying bot and sending Telegram test message...'
    if printf '%s\n' "$TELEGRAM_TOKEN" | python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from results import api
try:
    token = sys.stdin.readline().strip()
    expected, chat = sys.argv[2:4]
    bot = api(token, "getMe", {})
    if expected and bot.get("username", "").casefold() != expected.casefold():
        raise ValueError("Bot mismatch")
    if api(token, "getChat", {"chat_id": chat}).get("type") != "private":
        raise ValueError("Private chat required")
    api(token, "sendMessage", {"chat_id": chat, "text": "✅ XzyVpn Telegram Test Successful!"})
    print("Verified bot: @" + bot.get("username", ""))
except Exception:
    print("Telegram verification or delivery failed. Check token, chat ID, /start and network.", file=sys.stderr)
    sys.exit(1)' "$ROOT" "$TELEGRAM_BOT" "$TELEGRAM_CHAT"; then
      printf '%sTelegram test message delivered.%s\n' "$GREEN" "$RESET"
    else
      TELEGRAM_TOKEN=''; TELEGRAM_CHAT=''; TELEGRAM_BOT=''
    fi
  fi
  if [[ -z "$TELEGRAM_TOKEN" ]]; then
    fail 'Telegram verification failed; no deployment started. Retry with a valid token and chat ID.'
  fi
fi
if $TEST_ONLY; then [[ -n "$TELEGRAM_TOKEN" ]] || fail 'Telegram token required for test.'; unset TELEGRAM_TOKEN; exit 0; fi
section '02 | Select protocol'
printf '%s\n' '  1. Trojan WS' '  2. VLESS WS' '  3. VLESS gRPC' '  4. VMess WS' '  5. VLESS XHTTP (experimental)'
read -rp 'Enter protocol [2]: ' choice
case "${choice:-2}" in
  1) MODE=trojan-ws;; 2) MODE=vless-ws;; 3) MODE=vless-grpc;; 4) MODE=vmess-ws;; 5) MODE=vless-xhttp;; *) fail 'Invalid protocol.';;
esac
section '03 | Select region'
printf '%s\n' '  1. Singapore' '  2. Iowa, USA' '  3. Jakarta' '  4. Tokyo'
read -rp 'Enter region [1]: ' choice
case "${choice:-1}" in
  1) REGION=asia-southeast1;; 2) REGION=us-central1;; 3) REGION=asia-southeast2;; 4) REGION=asia-northeast1;; *) fail 'Invalid region.';;
esac
# Automatic defaults. A random suffix avoids replacing an existing VPN service.
SERVICE="xzy-$MODE-$(python3 -c 'import secrets; print(secrets.token_hex(4))')"
VPN_PATH='/xzy'
SA=${XZY_RUNTIME_SERVICE_ACCOUNT:-xzy-runtime@$PROJECT.iam.gserviceaccount.com}
[[ "$SA" == *@"$PROJECT".iam.gserviceaccount.com ]] || fail 'Use an authorized dedicated service account in this project.'
if [[ "$MODE" == trojan-ws ]]; then CREDENTIAL=$(python3 -c 'import secrets; print(secrets.token_hex(32))'); else CREDENTIAL=$(python3 -c 'import uuid; print(uuid.uuid4())'); fi
HTTP2=(--no-use-http2)
if [[ "$MODE" == vless-grpc || "$MODE" == vless-xhttp ]]; then HTTP2=(--use-http2); fi
section '04 | Ready to deploy'
info 'Protocol:' "$MODE"
info 'Region:' "$REGION"
info 'Service:' "$SERVICE"
info 'Path:' "$VPN_PATH"
info 'Image:' "$IMAGE"
info 'Runtime:' "$SA"
if [[ -n "$TELEGRAM_TOKEN" ]]; then info 'Telegram:' "Enabled${TELEGRAM_BOT:+ (@$TELEGRAM_BOT)}"; else info 'Telegram:' 'Disabled'; fi
info 'Instances:' 'min 0 / max 1'
info 'Timeout:' '3600s per request'
printf '%s\n' 'Use only an authorized billing-enabled project.' 'Usage can incur charges. Creates a new public endpoint protected by VPN credentials.' 'The dedicated xzy-runtime account will be created if missing and permitted.'
read -rp 'Proceed? [y/N]: ' yes
[[ "$yes" == y || "$yes" == Y ]] || { echo 'Cancelled.'; exit 0; }
ENVFILE=$(mktemp)
trap 'rm -f "$ENVFILE"' EXIT
printf 'VPN_MODE: "%s"\nVPN_CREDENTIAL: "%s"\nVPN_PATH: "%s"\nVPN_GRPC_SERVICE: "xzy-grpc"\n' "$MODE" "$CREDENTIAL" "$VPN_PATH" > "$ENVFILE"
section '05 | Deploying Cloud Run'
echo '[1/3] Checking dedicated runtime service account...'
if ! gcloud iam service-accounts describe "$SA" --project "$PROJECT" --format='value(email)' >/dev/null 2>&1; then
  if [[ "$SA" != "xzy-runtime@$PROJECT.iam.gserviceaccount.com" ]]; then
    fail 'Cannot access configured runtime service account. Check permissions.'
  fi
  gcloud iam service-accounts create xzy-runtime --project "$PROJECT" --display-name 'XzyVpn runtime' --quiet || fail 'Cannot create runtime account. An authorized administrator must configure it.'
fi
echo '[2/3] Enabling Cloud Run API...'
gcloud services enable run.googleapis.com --project "$PROJECT" --quiet
echo '[3/3] Deploying container...' 
gcloud run deploy "$SERVICE" --project "$PROJECT" --region "$REGION" --image "$IMAGE" \
  --service-account "$SA" --port 8080 --cpu 1 --memory 512Mi --timeout 3600 \
  --min-instances 0 --max-instances 1 --allow-unauthenticated --env-vars-file "$ENVFILE" \
  "${HTTP2[@]}" --quiet
URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')
URI=$(python3 "$ROOT/uri.py" "$MODE" "$URL" "$VPN_PATH" <<< "$CREDENTIAL")
section '06 | Deployment results'
printf '%sService deployed.%s\n' "$GREEN" "$RESET"
info 'Service URL:' "$URL"
printf '\nPrivate connection URI (do not share):\n%s\n' "$URI"
echo 'Deployment success is not a VPN connectivity test. Import the URI and verify internet traffic.'
printf 'Delete when finished: gcloud run services delete %q --project %q --region %q\n' "$SERVICE" "$PROJECT" "$REGION"
RESULT_DIR=$(mktemp -d "$HOME/xzyvpn-results.XXXXXX")
if printf '%s\n%s\n' "$CREDENTIAL" "$TELEGRAM_TOKEN" | python3 "$ROOT/results.py" \
  "$MODE" "$URL" "$VPN_PATH" "$SERVICE" "$REGION" "$IMAGE" "$RESULT_DIR" --chat "$TELEGRAM_CHAT"; then
  :
else
  echo 'Result export or Telegram delivery reported an error; check local files.' >&2
fi
unset TELEGRAM_TOKEN CREDENTIAL
info 'Local files:' "$RESULT_DIR"
line
