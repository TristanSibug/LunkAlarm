#!/usr/bin/env python3
import json, os, shutil, sys
import xml.etree.ElementTree as ET
from pathlib import Path
output=Path(sys.argv[1])
report={
    'commit':os.environ['GITHUB_SHA'],
    'run':f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    'status':os.environ['BUILD_STATUS'],
    'build':os.environ.get('APK_STATUS'),
    'emulator':os.environ.get('EMULATOR_STATUS'),
    'release':os.environ.get('RELEASE_STATUS'),
    'tests':[], 'errors':[], 'previews':[]
}
for pattern in ['android/app/build/test-results/testDebugUnitTest/TEST-*.xml','android/app/build/outputs/androidTest-results/connected/**/*.xml']:
    for path in sorted(Path('.').glob(pattern)):
        try:
            root=ET.parse(path).getroot()
            report['tests'].append({k:root.get(k) for k in ['name','tests','failures','errors','skipped']})
            for failure in root.iter('failure'):
                report['errors'].append((failure.text or failure.get('message') or '')[:8000])
        except ET.ParseError: pass
for name in ['artifacts/android-build.log','artifacts/android-ui-test.log','artifacts/android-permission-test.log']:
    p=Path(name)
    if not p.exists(): continue
    lines=p.read_text(errors='replace').splitlines()
    report['errors'] += [line for line in lines if line.startswith('e: ') or ': error:' in line][:40]
    if report['status']!='success': report[p.name]=lines[-100:]
for p in sorted(Path('artifacts/android-previews').glob('*.png')):
    shutil.copyfile(p,output/p.name); report['previews'].append(p.name)
if Path('artifacts/android-current.png').exists(): shutil.copyfile('artifacts/android-current.png',output/'android-current.png')
(output/'build.json').write_text(json.dumps(report,indent=2)+'\n')
(output/'README.md').write_text(f"# Native Android build\n\nStatus: **{report['status']}**  \nCommit: `{report['commit']}`  \n[Build and APK]({report['run']})\n\nThis branch contains generated reports and emulator previews only. Android source is on main under android/.\n")
