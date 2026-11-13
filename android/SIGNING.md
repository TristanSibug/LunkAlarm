# Permanent Android signing

Android accepts an update only when the application ID matches, the signing identity is compatible, and the version code is acceptable. Uninstalling removes private app data. All distribution builds from 1.3.1 must reuse the permanent key whose public certificate SHA-256 is recorded in `signing-certificate.sha256`.

## One-time maintainer setup

1. Open the repository's **Settings → Secrets and variables → Actions → New repository secret**.
2. Name the secret **ANDROID_SIGNING_BUNDLE**.
3. Paste the complete contents of the privately supplied `ANDROID_SIGNING_BUNDLE.json` into Value and save it. Do not paste it into a chat, issue, commit, or release.
4. Keep a private, encrypted/offline backup of that bundle under the maintainer's control. It contains the keystore and credentials needed to reproduce the same signing identity.
5. Run **Native Android app** from Actions after saving the secret, or rerun a build that stopped because the secret was missing.

The bundle is a JSON object containing `keystore` (base64 PKCS12), `storePassword`, `keyPassword`, and `keyAlias`. Its actual contents are secret. The public certificate fingerprint is not secret. The bundle is supplied separately; it is not stored in this repository.

Do not regenerate the key between releases. If the secret is accidentally removed, restore the identical bundle from the private backup. Generating a different key would break normal updates again.

## Build safeguards

- `prepare_signing.py` requires the private bundle, writes signing files with owner-only permissions under the runner's temporary directory, and verifies the certificate against the public pin.
- The Gradle distribution job requires that prepared signing configuration; there is no fallback to a generated debug key.
- The workflow never generates a distribution key or relies on caches for one.
- After testing, `verify_apk.py` checks the actual APK signer before it is copied into the distribution artifact.
- Temporary signing files are removed before artifact upload. Only the named verified APK, source archive and non-secret test/build reports are distributed.
- Local debug builds using a separate debug key are for local testing only. They cannot replace the permanently signed app. Distribute only the verified CI artifact.

Six signing-script tests cover valid-key loading and private file permissions, missing/corrupt bundles, incorrect passwords, changed certificates, and wrong/multiple final APK signers.

## Upgrade regression check

CI independently builds a lower-version fixture and the higher-version APK using the permanent key. It verifies matching application IDs and signer fingerprints and increasing version codes. On a fresh emulator it then:

1. Installs the fixture and seeds saved alarm definitions, a countdown, theme/clock preferences and an imported sound.
2. Installs the newer APK with `adb install -r`, without uninstalling, clearing data or reseeding.
3. Checks that alarm IDs/settings, countdown deadlines, preferences and imported sound bytes survived. Countdown wall-time recalculation is allowed a small clock-sampling tolerance; its elapsed deadline must be preserved.
4. Cleans up the test alarms and runs the usual permission and native UI tests.

The fixture is compiled from the current source with a lower version code. This checks installation and storage retention; it does not replace the separate core tests for historical data-schema compatibility. The fixture is not distributed.

## Releases and transition

Keep the application ID `online.reeeserve.lunkalarm`. Increase `versionCode` for each new release, retain the same permanent signing key and publish the verified APK. Back up the private bundle before relying on this baseline.

Older development-signed releases have different certificates and cannot be upgraded to this new signing identity in place. Users moving from those releases need one final reinstall and must recreate their local alarms. Updates beginning with the new 1.3.1 baseline retain their app data.
