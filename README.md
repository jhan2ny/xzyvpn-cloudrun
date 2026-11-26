# XzyVpn CloudRun v0.1.2

Patch: remove IPv4-mapped IPv6 CIDR rejected by Xray 26.9.9; keep other routing restrictions. Live build and connection validation pending.
One image, one protocol per deployed service. Trojan WS, VLESS WS, VLESS gRPC, VMess WS and experimental VLESS XHTTP. Uses upstream Xray image pinned to 26.9.9 (not claimed latest), Google-managed HTTPS, and a generated credential per deployment.

## Build
1. Create a GitHub repository `xzyvpn-cloudrun`. Upload the contents of this directory at repository root, including the hidden `.github/workflows/docker.yml`. Do not upload the ZIP itself as the only file.
2. Run Actions > Build XzyVpn CloudRun > Run workflow. It builds AMD64, validates all five configs with Xray, and publishes `ghcr.io/<owner>/xzyvpn-cloudrun:latest` and commit SHA tags.
3. Under GitHub Packages, make the image public (no secrets are included). Cloud Run supports public GHCR images directly. If your organization requires a private package, use Artifact Registry remote instead.

## Deploy in Google Cloud Shell
Select a billing-enabled project, clone your repository (or upload/extract this ZIP in Cloud Shell), then enter the directory. Create a dedicated runtime identity once, with no project-level roles:

```bash
gcloud iam service-accounts create xzy-runtime --display-name='XzyVpn runtime'
gcloud config get-value project
```
The email is `xzy-runtime@PROJECT_ID.iam.gserviceaccount.com`. The deploying account needs permission to act as it (Service Account User) and to deploy Cloud Run, enable APIs and allow public invocation. Organization policies can prohibit public access.

```bash
bash xzy.sh
```
Enter the GitHub owner, repository, protocol, region, service name, path and service account email. Import the printed URI into your client. Run again with a different service name for each simultaneous protocol. Existing services with the same name will be updated and old credentials will stop working once traffic moves to the new revision.

## Security and limits
- Only for authorized use. Keep credentials private. No shared default password. The image is public but the credential is not baked in. Runtime credentials are passed as Cloud Run environment variables; authorized service configuration viewers can read them. Use Secret Manager for production.
- The runtime service account must have no project roles. Private and link-local destinations and SMTP port 25 are blocked at Xray routing level as defense in depth; this is not a substitute for network egress isolation and does not guarantee protection against DNS rebinding.
- TLS terminates at Cloud Run; the container handles plaintext transport from Google's managed frontend. Use the actual run.app endpoint for address, SNI and Host. Never disable TLS verification.
- WebSockets have a maximum 60-minute request timeout; reconnect. gRPC and XHTTP request HTTP/2 end-to-end. XHTTP packet-up is experimental, and limiting instances to one does not guarantee affinity across restarts. Direct SSH/UDP VPN listeners are not supported by this ingress.
- Defaults: 1 vCPU, 512 MiB, min instances zero, max one. Not a spending cap. Active traffic, egress and other resources may cost money. No fake expiry timer. Delete the service after testing using the command printed by the script. Set a billing budget alert (alerts are not a hard cap).
- Optional Telegram delivery to a private chat only; bot messages are not end-to-end encrypted. No real connectivity test has been run here. The workflow checks Xray config syntax only; deployment and client import must be verified on your account.

## References
https://github.com/XTLS/Xray-core
https://docs.cloud.google.com/run/docs/deploying
https://docs.cloud.google.com/run/docs/triggering/websockets
https://docs.cloud.google.com/run/docs/configuring/http2

## Telegram and client export (v0.1.2)
Create a bot with @BotFather, open its private chat and send /start. Obtain your numeric private chat ID (for example from your own bot getUpdates response, keeping its token private). At deployment, choose Telegram delivery and enter the token and ID. The token is not passed to Cloud Run or saved. Telegram gets a text account summary with URI, client.json (standalone Xray local SOCKS/HTTP client configuration) and account.json (connection metadata). Local copies plus uri.txt are saved under a private directory in your home folder even if Telegram fails. These files include VPN secrets; do not upload them to GitHub. Telegram bot chats are not end-to-end encrypted. No Google login credentials or service account keys are sent. No automatic expiry is configured. Use a personal or explicitly authorized GCP project only. The Dockerfile, server.py and workflow are unchanged from v0.1.1; live deployment and client connectivity remain untested.
