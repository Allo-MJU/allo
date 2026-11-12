#!/usr/bin/env python3
"""Create private, short-lived TLS configuration for the local mirror relay."""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import ssl
import subprocess


def _host_san(host):
    try:
        address = ipaddress.ip_address(host)
        if address.version != 4:
            raise ValueError('IPv4 or DNS hostname required')
        return 'IP:' + str(address)
    except ValueError:
        if len(host) > 253 or not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', host):
            raise ValueError('invalid hostname')
        if any(not part or len(part) > 63 or part.startswith('-') or part.endswith('-') for part in host.split('.')):
            raise ValueError('invalid hostname')
        return 'DNS:' + host


def create_configuration(directory, host, bind, port):
    san = _host_san(host)
    if ipaddress.ip_address(bind).version != 4 or not 1 <= int(port) <= 65535:
        raise ValueError('invalid bind address or port')
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    paths = {name: directory / name for name in ['server.json', 'connection.json', 'cert.pem', 'key.pem']}
    if any(p.exists() for p in paths.values()):
        raise FileExistsError('existing session configuration must not be overwritten')
    executable = shutil.which('openssl')
    if executable is None:
        raise ValueError('openssl is required')
    previous_umask = os.umask(0o077)
    try:
        subprocess.run([executable, 'req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes', '-days', '7',
                        '-keyout', str(paths['key.pem']), '-out', str(paths['cert.pem']),
                        '-subj', '/CN=' + host, '-addext', 'subjectAltName=' + san],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        token = secrets.token_urlsafe(32)
        digest = hashlib.sha256(ssl.PEM_cert_to_DER_cert(paths['cert.pem'].read_text())).hexdigest()
        server = {'bind': bind, 'port': int(port), 'token': token, 'cert': str(paths['cert.pem']), 'key': str(paths['key.pem'])}
        client = {'url': f'https://{host}:{port}', 'token': token, 'certificateSha256': digest}
        for name, data in [('server.json', server), ('connection.json', client)]:
            with paths[name].open('x') as handle:
                json.dump(data, handle, indent=2)
                handle.write('\n')
        for path in paths.values():
            path.chmod(0o600)
    finally:
        os.umask(previous_umask)
    return paths['server.json'], paths['connection.json']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('tasks/mirror-local'))
    parser.add_argument('--host', default='localhost', help='DNS name or IPv4 address reachable by both clients; included in certificate')
    parser.add_argument('--bind', default='127.0.0.1', help='Explicitly use 0.0.0.0 for a trusted LAN experiment')
    parser.add_argument('--port', type=int, default=8443)
    args = parser.parse_args()
    try:
        server, client = create_configuration(args.directory, args.host, args.bind, args.port)
    except (OSError, ValueError, subprocess.SubprocessError):
        parser.exit(1, 'Could not create relay configuration (check arguments, openssl, or existing files).\n')
    print(f'Server configuration: {server}')
    print(f'Private connection information for both debug apps: {client}')
    print('Do not commit, publish, or log connection information. Certificate expires in 7 days.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
