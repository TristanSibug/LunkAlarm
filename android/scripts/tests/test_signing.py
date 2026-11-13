import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_signing import SigningError, prepare
from verify_apk import verify

class SigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.keys = tempfile.TemporaryDirectory()
        cls.key = Path(cls.keys.name) / 'test.p12'
        cls.password = 'only-a-disposable-test-password'
        subprocess.run(['keytool', '-genkeypair', '-storetype', 'PKCS12', '-keystore', str(cls.key), '-storepass', cls.password,
                        '-keypass', cls.password, '-alias', 'test', '-dname', 'CN=Disposable Test', '-keyalg', 'RSA',
                        '-keysize', '2048', '-validity', '1'], check=True, capture_output=True)
        cert = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(cls.key), '-storepass', cls.password,
                                        '-alias', 'test'], stderr=subprocess.DEVNULL)
        cls.pin = hashlib.sha256(cert).hexdigest()
    @classmethod
    def tearDownClass(cls):
        cls.keys.cleanup()
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / 'loaded'
        self.bundle = {'keystore':base64.b64encode(self.key.read_bytes()).decode(), 'storePassword':self.password,
                       'keyPassword':self.password, 'keyAlias':'test'}
    def tearDown(self):
        self.tmp.cleanup()
    def test_correct_key_is_verified_and_files_are_private(self):
        props = prepare(json.dumps(self.bundle), self.out, self.pin)
        self.assertTrue(props.exists())
        self.assertEqual(0o600, props.stat().st_mode & 0o777)
        self.assertEqual(0o600, (self.out / 'permanent.p12').stat().st_mode & 0o777)
        self.assertEqual(0o700, self.out.stat().st_mode & 0o777)
        self.assertEqual(self.key.read_bytes(), (self.out / 'permanent.p12').read_bytes())
    def test_missing_key_never_generates_a_replacement(self):
        with self.assertRaises(SigningError): prepare('', self.out, self.pin)
        self.assertFalse((self.out / 'permanent.p12').exists())
    def test_changed_certificate_is_rejected(self):
        with self.assertRaisesRegex(SigningError, 'certificate mismatch'): prepare(json.dumps(self.bundle), self.out, '0'*64)
        self.assertFalse((self.out / 'signing.properties').exists())
    def test_bad_password_has_no_secret_in_error(self):
        self.bundle['storePassword'] = 'do-not-print-this-test-value'
        with self.assertRaises(SigningError) as failure: prepare(json.dumps(self.bundle), self.out, self.pin)
        self.assertNotIn(self.bundle['storePassword'], str(failure.exception))
    def test_bad_base64_is_rejected(self):
        self.bundle['keystore'] = 'not valid base64!'
        with self.assertRaises(SigningError): prepare(json.dumps(self.bundle), self.out, self.pin)
    def test_final_apk_must_have_exactly_the_permanent_signer(self):
        verify('Signer #1 certificate SHA-256 digest: '+self.pin, self.pin)
        for value in ['', 'Signer #1 certificate SHA-256 digest: '+'0'*64,
                      'Signer #1 certificate SHA-256 digest: '+self.pin+'\nSigner #2 certificate SHA-256 digest: '+self.pin]:
            with self.assertRaises(ValueError): verify(value, self.pin)
if __name__ == '__main__': unittest.main()
