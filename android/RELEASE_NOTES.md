# LunkAlarm for Android v1.3.1 — Reliable App Updates

- Establishes one permanent signing identity for future releases.
- Removes cache-based signing and automatic replacement-key generation.
- Rejects missing or incorrect signing keys before building a distributable APK.
- Verifies the final APK certificate before packaging.
- Adds an installation-over-existing-app test covering saved alarms, timers, preferences and imported ringtones.

## One-time transition

Older test releases use different signing keys. Moving to **1.3.1** requires one final reinstall, which removes their local alarm data. Record any alarm details you want to recreate before uninstalling. Future updates from this new signing baseline install over the existing app and retain its data, provided the same application ID and permanent key are used.

Download the attached APK to install.
