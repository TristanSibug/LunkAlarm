#!/usr/bin/env python3
"""Dependency-free, deterministic Xcode project generation. Run after adding source files."""
import hashlib
from pathlib import Path

IOS = Path(__file__).resolve().parents[1]
PROJECT = IOS / "LunkAlarm.xcodeproj"
PROJECT.mkdir(exist_ok=True)

def ident(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()

objects = []
def add(label, body):
    objects.append(f'\t\t{ident(label)} = {{ {body} }};')
    return ident(label)

sources = sorted((IOS / "LunkAlarm").rglob("*.swift"))
resources = sorted((IOS / "LunkAlarm/Resources/Sounds").glob("*.wav"))
resources += [IOS / "LunkAlarm/Resources/Assets.xcassets", IOS / "LunkAlarm/Resources/PrivacyInfo.xcprivacy"]
refs, source_builds, resource_builds = [], [], []
for path in sources + resources:
    relative = path.relative_to(IOS).as_posix()
    filetype = {".swift": "sourcecode.swift", ".wav": "audio.wav", ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml"}[path.suffix]
    ref = add("ref:" + relative, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    build = add("build:" + relative, f'isa = PBXBuildFile; fileRef = {ref};')
    refs.append(ref)
    (source_builds if path.suffix == ".swift" else resource_builds).append(build)

product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LunkAlarm.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_sources = sorted((IOS / "UITests").glob("*.swift"))
test_builds = []
for path in test_sources:
    relative = path.relative_to(IOS).as_posix()
    ref = add("ref:" + relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    test_builds.append(add("build:" + relative, f'isa = PBXBuildFile; fileRef = {ref};'))
test_product = add("testproduct", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LunkAlarmUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add("products", f'isa = PBXGroup; children = ({product},{test_product},); name = Products; sourceTree = "<group>";')
add("main", f'isa = PBXGroup; children = ({",".join(refs + [ident("products")])},); sourceTree = "<group>";')
add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(source_builds)},); runOnlyForDeploymentPostprocessing = 0;')
add("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
add("frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add("testsources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(test_builds)},); runOnlyForDeploymentPostprocessing = 0;')
add("testframeworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add("testproxy", f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target")}; remoteInfo = LunkAlarm;')
add("testdependency", f'isa = PBXTargetDependency; target = {ident("target")}; targetProxy = {ident("testproxy")};')

for mode in ("Debug", "Release"):
    debug = mode == "Debug"
    project_settings = {
        "CLANG_ENABLE_MODULES": "YES", "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
        "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"' if debug else '"-O"',
        "DEBUG_INFORMATION_FORMAT": '"dwarf"' if debug else '"dwarf-with-dsym"',
        "ENABLE_TESTABILITY": "YES" if debug else "NO", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"' if debug else '"$(inherited)"',
    }
    app_settings = {
        "PRODUCT_NAME": "LunkAlarm", "PRODUCT_BUNDLE_IDENTIFIER": "online.reeeserve.LunkAlarm",
        "INFOPLIST_FILE": "LunkAlarm/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "TARGETED_DEVICE_FAMILY": '"1,2"', "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "7", "MARKETING_VERSION": "1.6.0",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": '""',
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
    }
    test_settings = {
        "PRODUCT_NAME": "LunkAlarmUITests", "PRODUCT_BUNDLE_IDENTIFIER": "online.reeeserve.LunkAlarm.UITests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "LunkAlarm",
        "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": '"1,2"',
    }
    for scope, settings in (("project", project_settings), ("app", app_settings), ("test", test_settings)):
        content = " ".join(f"{key} = {value};" for key, value in settings.items())
        add(scope + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {content} }}; name = {mode};')
for scope in ("project", "app", "test"):
    add(scope + "configs", f'isa = XCConfigurationList; buildConfigurations = ({ident(scope + "Debug")},{ident(scope + "Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add("target", f'isa = PBXNativeTarget; buildConfigurationList = {ident("appconfigs")}; buildPhases = ({ident("sources")},{ident("frameworks")},{ident("resources")},); buildRules = (); dependencies = (); name = LunkAlarm; productName = LunkAlarm; productReference = {product}; productType = "com.apple.product-type.application";')
add("testtarget", f'isa = PBXNativeTarget; buildConfigurationList = {ident("testconfigs")}; buildPhases = ({ident("testsources")},{ident("testframeworks")},); buildRules = (); dependencies = ({ident("testdependency")},); name = LunkAlarmUITests; productName = LunkAlarmUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{ {ident("target")} = {{ CreatedOnToolsVersion = 26.0; }}; {ident("testtarget")} = {{ CreatedOnToolsVersion = 26.0; TestTargetID = {ident("target")}; }}; }}; }}; buildConfigurationList = {ident("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {ident("main")}; productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ident("target")},{ident("testtarget")},);')
(PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + "\n".join(objects) + '\n\t};\n\trootObject = ' + ident("project") + ';\n}\n')
schemes = PROJECT / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target")}" BuildableName="LunkAlarm.app" BlueprintName="LunkAlarm" ReferencedContainer="container:LunkAlarm.xcodeproj"/>'
test_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("testtarget")}" BuildableName="LunkAlarmUITests.xctest" BlueprintName="LunkAlarmUITests" ReferencedContainer="container:LunkAlarm.xcodeproj"/>'
(schemes / "LunkAlarm.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{test_reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_reference}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"Generated Xcode project: {len(sources)} Swift files, {len(resources)} resources")
