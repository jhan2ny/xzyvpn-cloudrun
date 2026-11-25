import base64
import json
import sys
from urllib.parse import urlencode, urlparse

def make_uri(mode, url, path, credential):
    parsed = urlparse(url)
    host = parsed.hostname
    if parsed.scheme != 'https' or not host or not host.endswith('.run.app'):
        raise ValueError('Expected Cloud Run HTTPS endpoint')
    if mode == 'vmess-ws':
        obj = {'v': '2', 'ps': 'XzyVpn VMess WS', 'add': host, 'port': '443', 'id': credential,
               'aid': '0', 'scy': 'auto', 'net': 'ws', 'type': 'none', 'host': host,
               'path': path, 'tls': 'tls', 'sni': host, 'alpn': 'http/1.1'}
        return 'vmess://' + base64.b64encode(json.dumps(obj, separators=(',', ':')).encode()).decode()
    proto = 'trojan' if mode == 'trojan-ws' else 'vless'
    q = {'security': 'tls', 'sni': host}
    if proto == 'vless': q['encryption'] = 'none'
    if mode.endswith('-ws'):
        q.update(type='ws', host=host, path=path, alpn='http/1.1')
    elif mode == 'vless-grpc':
        q.update(type='grpc', serviceName='xzy-grpc', mode='gun', alpn='h2')
    elif mode == 'vless-xhttp':
        q.update(type='xhttp', host=host, path=path, mode='packet-up', alpn='h2')
    else:
        raise ValueError('Unknown mode')
    return f'{proto}://{credential}@{host}:443?{urlencode(q)}#XzyVpn-{mode}'

if __name__ == '__main__':
    print(make_uri(*sys.argv[1:], sys.stdin.readline().strip()))
