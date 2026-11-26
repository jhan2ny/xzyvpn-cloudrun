"""Export private VPN account details and optionally deliver them to a private Telegram chat."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import secrets
import sys
from urllib.parse import urlparse, urlencode
from urllib.request import Request, urlopen
from uri import make_uri


def client_config(mode, host, path, credential):
    proto, network = mode.split('-', 1)
    if proto == 'trojan':
        settings = {'servers': [{'address': host, 'port': 443, 'password': credential}]}
    else:
        user = {'id': credential}
        if proto == 'vless':
            user['encryption'] = 'none'
        else:
            user.update(alterId=0, security='auto')
        settings = {'vnext': [{'address': host, 'port': 443, 'users': [user]}]}
    stream = {'network': network, 'security': 'tls', 'tlsSettings': {
        'serverName': host, 'allowInsecure': False, 'alpn': ['http/1.1' if network == 'ws' else 'h2']}}
    if network == 'ws':
        stream['wsSettings'] = {'host': host, 'path': path}
    elif network == 'grpc':
        stream['grpcSettings'] = {'serviceName': 'xzy-grpc', 'multiMode': False}
    elif network == 'xhttp':
        stream['xhttpSettings'] = {'host': host, 'path': path, 'mode': 'packet-up'}
    else:
        raise ValueError('Invalid transport')
    return {'log': {'loglevel': 'warning'}, 'inbounds': [
        {'listen': '127.0.0.1', 'port': 10808, 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': True}},
        {'listen': '127.0.0.1', 'port': 10809, 'protocol': 'http', 'settings': {}}],
        'outbounds': [{'tag': 'proxy', 'protocol': proto, 'settings': settings, 'streamSettings': stream}]}


def export(args, credential):
    uri = make_uri(args.mode, args.url, args.path, credential)
    host = urlparse(args.url).hostname
    proto, network = args.mode.split('-', 1)
    details = {'service': args.service, 'region': args.region, 'protocol': proto,
               'transport': network, 'address': host, 'port': 443, 'tls': True,
               'sni': host, 'host': host if network != 'grpc' else None,
               'path': args.path if network != 'grpc' else None,
               'grpc_service_name': 'xzy-grpc' if network == 'grpc' else None,
               'xhttp_mode': 'packet-up' if network == 'xhttp' else None,
               'alpn': 'http/1.1' if network == 'ws' else 'h2',
               'password' if proto == 'trojan' else 'uuid': credential,
               'encryption': 'none' if proto == 'vless' else ('auto' if proto == 'vmess' else None),
               'url': args.url, 'image': args.image, 'cpu': 1, 'memory': '512Mi',
               'min_instances': 0, 'max_instances': 1, 'request_timeout_seconds': 3600,
               'exported_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'expires_at': None, 'connectivity_verified': False, 'uri': uri}
    details = {k: v for k, v in details.items() if v is not None}
    directory = Path(args.output)
    for name, content in {'client.json': json.dumps(client_config(args.mode, host, args.path, credential), indent=2),
                          'account.json': json.dumps(details, indent=2), 'uri.txt': uri}.items():
        with (directory / name).open('x', encoding='utf-8') as f:
            f.write(content + '\n')
    return details


def api(token, method, fields, document=None):
    if not re.fullmatch(r'[0-9]+:[A-Za-z0-9_-]+', token):
        raise ValueError('Invalid bot token')
    url = 'https://api.telegram.org/bot' + token + '/' + method
    if document is None:
        data = urlencode(fields).encode()
        content_type = 'application/x-www-form-urlencoded'
    else:
        boundary = secrets.token_hex(24)
        chunks = []
        for key, value in fields.items():
            chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
        chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="document"; filename="{document.name}"\r\nContent-Type: application/json\r\n\r\n'.encode())
        chunks.extend([document.read_bytes(), f'\r\n--{boundary}--\r\n'.encode()])
        data = b''.join(chunks)
        content_type = 'multipart/form-data; boundary=' + boundary
    with urlopen(Request(url, data=data, headers={'Content-Type': content_type}), timeout=25) as response:
        result = json.load(response)
    if not result.get('ok'):
        raise RuntimeError('Telegram rejected request')
    return result['result']


def send(token, chat, details, directory):
    if not re.fullmatch(r'[1-9][0-9]*', chat):
        raise ValueError('Only a private numeric chat ID is supported')
    if api(token, 'getChat', {'chat_id': chat}).get('type') != 'private':
        raise ValueError('Recipient must be a private chat')
    keys = ['service', 'region', 'protocol', 'transport', 'address', 'port', 'tls', 'sni', 'host', 'path', 'grpc_service_name', 'xhttp_mode', 'alpn', 'uuid', 'password', 'encryption', 'url', 'cpu', 'memory', 'min_instances', 'max_instances', 'request_timeout_seconds', 'exported_utc']
    message = 'XzyVpn CloudRun — deployed\n\n' + '\n'.join(f'{k}: {details[k]}' for k in keys if k in details)
    message += '\n\nVPN URI:\n' + details['uri'] + '\n\nNo automatic expiry. VPN connectivity not yet tested. Keep private.'
    api(token, 'sendMessage', {'chat_id': chat, 'text': message, 'link_preview_options': json.dumps({'is_disabled': True})})
    for name in ('client.json', 'account.json'):
        api(token, 'sendDocument', {'chat_id': chat, 'caption': name + ' — contains private VPN credentials'}, directory / name)


def main():
    parser = argparse.ArgumentParser()
    for name in ('mode', 'url', 'path', 'service', 'region', 'image', 'output'):
        parser.add_argument(name)
    parser.add_argument('--chat', default='')
    args = parser.parse_args()
    os.umask(0o077)
    credential = sys.stdin.readline().strip()
    token = sys.stdin.readline().strip()
    details = export(args, credential)
    if token and args.chat:
        try:
            send(token, args.chat, details, Path(args.output))
        except Exception:
            # Never print an exception containing a bot-token URL or credentials.
            print('Telegram delivery incomplete or failed. Local results are saved. Check token, private chat ID, /start and network.', file=sys.stderr)
            return 2
        print('Telegram: account message and both JSON files delivered.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
