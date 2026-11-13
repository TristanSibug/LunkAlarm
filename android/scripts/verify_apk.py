#!/usr/bin/env python3
"""Verify the final APK uses exactly the pinned permanent signer."""
import re
import sys
from pathlib import Path

def verify(text, expected):
    digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$', text, re.M)
    if [x.lower() for x in digests] != [expected]:
        raise ValueError('APK signer does not match the permanent signing certificate; refusing distribution.')

if __name__ == '__main__':
    verify(Path(sys.argv[1]).read_text(), (Path(__file__).resolve().parents[1] / 'signing-certificate.sha256').read_text().strip())
    print('APK permanent signing identity verified.')
