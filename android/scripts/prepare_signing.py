#!/usr/bin/env python3
"""Materialize the permanent CI signing secret privately; never generate a key."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

class SigningError(Exception):
    pass

def prepare(bundle_text, output, expected, keytool='keytool'):
    try:
        bundle = json.loads(bundle_text)
        data = base64.b64decode(bundle['keystore'], validate=True)
        values = {k: bundle[k] for k in ('storePassword', 'keyPassword', 'keyAlias')}
        if not 0 < len(data) <= 131072 or any(not isinstance(v, str) or not v or '\x00' in v for v in values.values()):
            raise ValueError()
    except Exception:
        raise SigningError('ANDROID_SIGNING_BUNDLE is missing or invalid. No replacement signing key will be generated.') from None
    if not re.fullmatch(r'[0-9a-f]{64}', expected):
        raise SigningError('The public signing certificate pin is invalid.')
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.chmod(0o700)
    keystore = output / 'permanent.p12'
    descriptor = os.open(keystore, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as f:
        f.write(data)
    env = os.environ.copy()
    env.pop('ANDROID_SIGNING_BUNDLE', None)
    env['LUNK_VERIFY_STORE_PASSWORD'] = values['storePassword']
    result = subprocess.run([keytool, '-exportcert', '-keystore', str(keystore), '-storepass:env', 'LUNK_VERIFY_STORE_PASSWORD',
                             '-alias', values['keyAlias']], env=env, capture_output=True)
    if result.returncode != 0:
        raise SigningError('The permanent keystore could not be opened with the supplied signing settings.')
    if hashlib.sha256(result.stdout).hexdigest() != expected:
        raise SigningError('Signing certificate mismatch. Refusing to build an incompatible update.')
    def escape(value):
        return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(' ', '\\ ')
    properties = output / 'signing.properties'
    descriptor = os.open(properties, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as f:
        for k,v in {'storeFile':str(keystore), **values}.items():
            f.write(k + '=' + escape(v) + '\n')
    return properties

def main():
    root = Path(__file__).resolve().parents[1]
    parent = Path(os.environ.get('RUNNER_TEMP', tempfile.gettempdir()))
    output = Path(tempfile.mkdtemp(prefix='lunkalarm-signing-', dir=parent))
    try:
        props = prepare(os.environ.get('ANDROID_SIGNING_BUNDLE', ''), output,
                        (root / 'signing-certificate.sha256').read_text().strip())
        env_file = os.environ.get('GITHUB_ENV')
        if env_file:
            with open(env_file, 'a') as f:
                f.write('LUNK_ANDROID_SIGNING_PROPERTIES=' + str(props) + '\n')
        print('Permanent signing certificate verified. Private signing files prepared outside build artifacts.')
        if not env_file:
            print('Signing properties file: ' + str(props))
    except (SigningError, OSError, ValueError) as e:
        shutil.rmtree(output)
        print(str(e) if isinstance(e, SigningError) else "Could not prepare private signing files. No replacement key was generated.", file=sys.stderr)
        return 1
    return 0

def cleanup():
    value = os.environ.get('LUNK_ANDROID_SIGNING_PROPERTIES')
    if not value:
        return 0
    properties = Path(value).resolve()
    parent = Path(os.environ['RUNNER_TEMP']).resolve()
    if properties.name != 'signing.properties' or properties.parent.parent != parent or not properties.parent.name.startswith('lunkalarm-signing-'):
        raise SigningError('Refusing to clean an unexpected signing directory.')
    shutil.rmtree(properties.parent, ignore_errors=True)
    print('Private runner signing files removed.')
    return 0

if __name__ == '__main__':
    sys.exit(cleanup() if sys.argv[1:] == ['--cleanup'] else main())
