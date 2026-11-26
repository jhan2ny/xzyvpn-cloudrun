#!/usr/bin/env bash
set -euo pipefail
umask 077
if [[ ! -t 0 && -t 1 && -r /dev/tty ]]; then exec </dev/tty; fi
command -v gcloud >/dev/null || { echo 'Run in Google Cloud Shell.'; exit 1; }
PROJECT=$(gcloud config get-value project 2>/dev/null)
[[ -n "$PROJECT" && "$PROJECT" != '(unset)' ]] || { echo 'Select a GCP project first.'; exit 1; }
echo '=== XzyVpn CloudRun v0.1.2 ==='
echo "Project: $PROJECT"
read -rp 'GitHub owner: ' OWNER
read -rp 'Repository [xzyvpn-cloudrun]: ' REPO
REPO=${REPO:-xzyvpn-cloudrun}
[[ "$OWNER" =~ ^[a-zA-Z0-9_-]+$ && "$REPO" =~ ^[a-zA-Z0-9_.-]+$ ]] || exit 1
IMAGE="ghcr.io/${OWNER,,}/${REPO,,}:latest"
echo '1) Trojan WS  2) VLESS WS  3) VLESS gRPC  4) VMess WS  5) VLESS XHTTP (experimental)'
read -rp 'Protocol [2]: ' choice
case "${choice:-2}" in
  1) MODE=trojan-ws;; 2) MODE=vless-ws;; 3) MODE=vless-grpc;; 4) MODE=vmess-ws;; 5) MODE=vless-xhttp;; *) exit 1;;
esac
echo '1) Singapore  2) Iowa  3) Jakarta  4) Tokyo'
read -rp 'Region [1]: ' choice
case "${choice:-1}" in
  1) REGION=asia-southeast1;; 2) REGION=us-central1;; 3) REGION=asia-southeast2;; 4) REGION=asia-northeast1;; *) exit 1;;
esac
read -rp "Service name [xzy-$MODE]: " SERVICE
SERVICE=${SERVICE:-xzy-$MODE}
[[ "$SERVICE" =~ ^[a-z]([a-z0-9-]{0,47}[a-z0-9])?$ ]] || { echo 'Invalid service name'; exit 1; }
read -rp 'WebSocket / XHTTP path [/xzy]: ' VPN_PATH
VPN_PATH=${VPN_PATH:-/xzy}
[[ "$VPN_PATH" =~ ^/[a-zA-Z0-9_-]+$ ]] || exit 1
read -rp 'Runtime service account email (dedicated, no project roles): ' SA
[[ "$SA" == *@"$PROJECT".iam.gserviceaccount.com ]] || { echo 'Use a dedicated service account in this project.'; exit 1; }
if [[ "$MODE" == trojan-ws ]]; then CREDENTIAL=$(python3 -c 'import secrets; print(secrets.token_hex(32))'); else CREDENTIAL=$(python3 -c 'import uuid; print(uuid.uuid4())'); fi
HTTP2=(--no-use-http2)
if [[ "$MODE" == vless-grpc || "$MODE" == vless-xhttp ]]; then HTTP2=(--use-http2); fi
echo "Deploy $MODE to $REGION using $IMAGE (1 CPU, 512Mi, min 0, max 1)."
echo 'Public endpoint; Xray authenticates clients. Usage can incur charges. Existing service credentials will be replaced.'
read -rp 'Proceed? [y/N]: ' yes
[[ "$yes" == y || "$yes" == Y ]] || exit 0
TELEGRAM_TOKEN=''
TELEGRAM_CHAT=''
read -rp 'Send private VPN account and JSON to Telegram? [y/N]: ' tg
if [[ "$tg" == y || "$tg" == Y ]]; then
  read -rsp 'Telegram bot token (hidden): ' TELEGRAM_TOKEN
  printf '\n'
  read -rp 'Your private numeric Telegram chat ID: ' TELEGRAM_CHAT
  if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ || ! "$TELEGRAM_CHAT" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Invalid Telegram settings; continuing with local results only.'
    TELEGRAM_TOKEN=''; TELEGRAM_CHAT=''
  fi
fi
ENVFILE=$(mktemp)
trap 'rm -f "$ENVFILE"' EXIT
printf 'VPN_MODE: "%s"\nVPN_CREDENTIAL: "%s"\nVPN_PATH: "%s"\nVPN_GRPC_SERVICE: "xzy-grpc"\n' "$MODE" "$CREDENTIAL" "$VPN_PATH" > "$ENVFILE"
gcloud services enable run.googleapis.com --project "$PROJECT"
gcloud run deploy "$SERVICE" --project "$PROJECT" --region "$REGION" --image "$IMAGE" \
  --service-account "$SA" --port 8080 --cpu 1 --memory 512Mi --timeout 3600 \
  --min-instances 0 --max-instances 1 --allow-unauthenticated --env-vars-file "$ENVFILE" \
  "${HTTP2[@]}"
URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')
URI=$(python3 "$(dirname "$0")/uri.py" "$MODE" "$URL" "$VPN_PATH" <<< "$CREDENTIAL")
printf '\nService URL: %s\nPrivate connection URI (do not share):\n%s\n' "$URL" "$URI"
echo 'Deployment success is not a VPN connectivity test. Import the URI and verify internet traffic.'
printf 'Delete when finished: gcloud run services delete %q --project %q --region %q\n' "$SERVICE" "$PROJECT" "$REGION"

RESULT_DIR=$(mktemp -d "$HOME/xzyvpn-results.XXXXXX")
if printf '%s\n%s\n' "$CREDENTIAL" "$TELEGRAM_TOKEN" | python3 "$(dirname "$0")/results.py" \
  "$MODE" "$URL" "$VPN_PATH" "$SERVICE" "$REGION" "$IMAGE" "$RESULT_DIR" --chat "$TELEGRAM_CHAT"; then
  :
else
  echo 'Result export or Telegram delivery reported an error; check local files.' >&2
fi
unset TELEGRAM_TOKEN CREDENTIAL
printf 'Private results directory: %s\n' "$RESULT_DIR"
