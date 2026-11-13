#!/usr/bin/env python3
"""Check identity and increasing version codes before exercising adb install -r."""
import os
from pathlib import Path
import re
import subprocess
import sys
from verify_apk import verify

def check_pair(old, new, tools):
    pin = (Path(__file__).resolve().parents[1] / 'signing-certificate.sha256').read_text().strip()
    versions=[]
    for apk in [old, new]:
        signature = subprocess.check_output([str(tools / 'apksigner'), 'verify', '--print-certs', apk], text=True)
        verify(signature, pin)
        info = subprocess.check_output([str(tools / 'aapt'), 'dump', 'badging', apk], text=True)
        match = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", info, re.M)
        if not match or match[1] != 'online.reeeserve.lunkalarm':
            raise ValueError('Upgrade APK package ID is incorrect.')
        versions.append(int(match[2]))
    if versions[1] <= versions[0]:
        raise ValueError('The update must have a higher version code than the installed fixture.')
    print(f'Upgrade pair verified: permanent signer, same app ID, versionCode {versions[0]} -> {versions[1]}.')
if __name__ == '__main__':
    check_pair(sys.argv[1], sys.argv[2], Path(os.environ['ANDROID_HOME']) / 'build-tools/35.0.0')
