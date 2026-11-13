#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p artifacts/android-previews
collect() {
  adb logcat -d -v threadtime > artifacts/android-logcat.txt || true
  adb pull /sdcard/Android/data/online.reeeserve.lunkalarm/files/previews/. artifacts/android-previews/ || true
  adb exec-out screencap -p > artifacts/android-current.png || true
}
trap collect EXIT
adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
baseline_apk="${RUNNER_TEMP:?}/lunkalarm-upgrade-fixture.apk"
python3 android/scripts/verify_upgrade_pair.py "$baseline_apk" android/app/build/outputs/apk/debug/app-debug.apk | tee artifacts/android-upgrade-pair.log
adb install "$baseline_apk"
adb install -r android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell pm grant online.reeeserve.lunkalarm android.permission.POST_NOTIFICATIONS
adb shell appops set online.reeeserve.lunkalarm SCHEDULE_EXACT_ALARM allow
adb shell am instrument -w -r -e class 'online.reeeserve.lunkalarm.UpgradePersistenceTest#seedBeforeUpgrade' online.reeeserve.lunkalarm.test/androidx.test.runner.AndroidJUnitRunner | tee artifacts/android-upgrade-seed.log
python3 - <<'PYCHECK'
from pathlib import Path
assert 'OK (1 test)' in Path('artifacts/android-upgrade-seed.log').read_text()
PYCHECK
# This is deliberately an update, with no uninstall, data clear or reseeding.
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am instrument -w -r -e class 'online.reeeserve.lunkalarm.UpgradePersistenceTest#verifyAfterUpgrade' online.reeeserve.lunkalarm.test/androidx.test.runner.AndroidJUnitRunner | tee artifacts/android-upgrade-verify.log
python3 - <<'PYCHECK'
from pathlib import Path
assert 'OK (1 test)' in Path('artifacts/android-upgrade-verify.log').read_text()
PYCHECK
adb shell appops set online.reeeserve.lunkalarm SCHEDULE_EXACT_ALARM deny
adb shell am instrument -w -r -e class online.reeeserve.lunkalarm.PermissionGateTest online.reeeserve.lunkalarm.test/androidx.test.runner.AndroidJUnitRunner | tee artifacts/android-permission-test.log
python3 - <<'PY'
from pathlib import Path
text=Path('artifacts/android-permission-test.log').read_text()
assert 'OK (1 test)' in text, text
PY
adb shell appops set online.reeeserve.lunkalarm SCHEDULE_EXACT_ALARM allow
adb shell appops set online.reeeserve.lunkalarm USE_FULL_SCREEN_INTENT allow
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
./android/gradlew -p android :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=online.reeeserve.lunkalarm.AlarmInteractionTest -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true --console plain | tee artifacts/android-ui-test.log
