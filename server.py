"""Build the selected Xray inbound from runtime settings; no baked-in credentials."""
import json
import os
import re
import sys
import tempfile
import uuid

MODES = {
    'trojan-ws': ('trojan', 'ws'),
    'vless-ws': ('vless', 'ws'),
    'vless-grpc': ('vless', 'grpc'),
    'vmess-ws': ('vmess', 'ws'),
    'vless-xhttp': ('vless', 'xhttp'),
}

def config(env):
    mode = env.get('VPN_MODE', 'vless-ws')
    proto, transport = MODES[mode]
    port = int(env.get('PORT', '8080'))
    if not 1 <= port <= 65535:
        raise ValueError('Invalid port')
    credential = env['VPN_CREDENTIAL']
    if proto == 'trojan':
        if not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', credential):
            raise ValueError('Use a randomly generated Trojan password of 32+ characters')
        settings = {'clients': [{'password': credential}]}
    else:
        credential = str(uuid.UUID(credential))
        if uuid.UUID(credential).int == 0:
            raise ValueError('Invalid nil UUID')
        settings = {'clients': [{'id': credential}]}
        if proto == 'vless':
            settings['decryption'] = 'none'
    path = env.get('VPN_PATH', '/xzy')
    grpc = env.get('VPN_GRPC_SERVICE', 'xzy-grpc')
    if not re.fullmatch(r'/[A-Za-z0-9_-]+', path) or not re.fullmatch(r'[A-Za-z0-9_-]+', grpc):
        raise ValueError('Invalid path or gRPC service name')
    stream = {'network': transport, 'security': 'none'}
    if transport == 'ws':
        stream['wsSettings'] = {'path': path}
    elif transport == 'grpc':
        stream['grpcSettings'] = {'serviceName': grpc}
    else:
        stream['xhttpSettings'] = {'path': path, 'mode': 'packet-up'}
    return {
        'log': {'loglevel': 'warning'},
        'inbounds': [{'listen': '0.0.0.0', 'port': port, 'protocol': proto,
                      'settings': settings, 'streamSettings': stream}],
        'outbounds': [{'protocol': 'freedom', 'tag': 'internet', 'settings': {'domainStrategy': 'UseIP'}},
                      {'protocol': 'blackhole', 'tag': 'blocked'}],
        'routing': {'domainStrategy': 'IPOnDemand', 'rules': [
            {'type': 'field', 'domain': ['domain:localhost', 'domain:internal', 'full:metadata.google.internal'], 'outboundTag': 'blocked'},
            {'type': 'field', 'ip': ['0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4', '::/128', '::1/128', '::ffff:0:0/96', 'fc00::/7', 'fe80::/10', 'ff00::/8'], 'outboundTag': 'blocked'},
            {'type': 'field', 'port': '25', 'outboundTag': 'blocked'}]}
    }

def main():
    try:
        data = config(os.environ)
    except (ValueError, KeyError):
        sys.exit('Invalid or missing VPN runtime settings')
    fd, filename = tempfile.mkstemp(prefix='xzy-', suffix='.json')
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f)
    args = ['/usr/local/bin/xray', 'run']
    if sys.argv[1:] == ['--check']:
        args.append('-test')
    os.execv(args[0], args + ['-config', filename])

if __name__ == '__main__':
    main()
