#!/usr/bin/env python3
"""Generate a deterministic Xcode project using only relative source paths."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
objects = []

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(value)

def add(name, body):
    key = ident(name)
    objects.append(f"\t\t{key} = {{ {body} }};")
    return key

def arr(values):
    return "(" + ", ".join(values) + ")"

def settings(values):
    return "{ " + " ".join(f"{key} = {quote(value)};" for key, value in values.items()) + " }"

source_files = sorted((root / "App/iOS").glob("*.swift")) + sorted((root / "App/Shared").glob("*.swift"))
refs, builds = [], []
for file in source_files:
    relative = "../" + file.relative_to(root).as_posix()
    ref = add(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(relative)}; sourceTree = "<group>";')
    refs.append(ref)
    builds.append(add(relative + ":build", f"isa = PBXBuildFile; fileRef = {ref};"))
asset = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
asset_build = add("asset-build", f"isa = PBXBuildFile; fileRef = {asset};")
info = add("info", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
test = add("test-file", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MiniRadioUITests/MiniRadioUITests.swift; sourceTree = "<group>";')
test_build = add("test-build", f"isa = PBXBuildFile; fileRef = {test};")
product = add("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = MiniRadio.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = MiniRadioUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f'isa = PBXGroup; children = {arr([product, test_product])}; name = Products; sourceTree = "<group>";')
group = add("main-group", f'isa = PBXGroup; children = {arr(refs + [asset, info, test, products])}; sourceTree = "<group>";')
package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = ..;')
package_product = add("package-product", f"isa = XCSwiftPackageProductDependency; package = {package}; productName = RadioCore;")
framework_build = add("package-link", f"isa = PBXBuildFile; productRef = {package_product};")
sources = add("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;")
frameworks = add("frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([framework_build])}; runOnlyForDeploymentPostprocessing = 0;")
resources = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([asset_build])}; runOnlyForDeploymentPostprocessing = 0;")
test_sources = add("test-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr([test_build])}; runOnlyForDeploymentPostprocessing = 0;")
test_frameworks = add("test-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
test_resources = add("test-resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")

def config_list(name, base):
    configs = []
    for mode in ["Debug", "Release"]:
        values = dict(base)
        if name == "project":
            values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O",
                          DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym",
                          SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" if mode == "Debug" else "")
        configs.append(add(name + mode, f"isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {mode};"))
    return add(name + "-config-list", f"isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

project_configs = config_list("project", {"CLANG_ENABLE_MODULES": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0"})
app_configs = config_list("app", {"PRODUCT_BUNDLE_IDENTIFIER": "com.stevendong.miniradio.ios", "PRODUCT_NAME": "MiniRadio",
    "INFOPLIST_FILE": "Info.plist", "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1", "TARGETED_DEVICE_FAMILY": "1,2",
    "CODE_SIGN_STYLE": "Automatic", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
test_configs = config_list("tests", {"PRODUCT_BUNDLE_IDENTIFIER": "com.stevendong.miniradio.ios.uitests", "PRODUCT_NAME": "MiniRadioUITests",
    "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "MiniRadio-iOS", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2"})
app = add("app-target", f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {arr([sources, frameworks, resources])}; buildRules = (); dependencies = (); name = "MiniRadio-iOS"; packageProductDependencies = {arr([package_product])}; productName = MiniRadio; productReference = {product}; productType = "com.apple.product-type.application";')
proxy = add("test-proxy", f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = "MiniRadio-iOS";')
dependency = add("test-dependency", f"isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};")
test_target = add("test-target", f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {arr([test_sources, test_frameworks, test_resources])}; buildRules = (); dependencies = {arr([dependency])}; name = MiniRadioUITests; productName = MiniRadioUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
project = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1640; TargetAttributes = {{ {app} = {{ CreatedOnToolsVersion = 16.4; }}; {test_target} = {{ CreatedOnToolsVersion = 16.4; TestTargetID = {app}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; packageReferences = {arr([package])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([app, test_target])};')
folder = root / "iOS/MiniRadio.xcodeproj"
folder.mkdir(parents=True, exist_ok=True)
(folder / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 60;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {project};\n}}\n")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="MiniRadio.app" BlueprintName="MiniRadio-iOS" ReferencedContainer="container:MiniRadio.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="MiniRadioUITests.xctest" BlueprintName="MiniRadioUITests" ReferencedContainer="container:MiniRadio.xcodeproj"/></TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="MiniRadio.app" BlueprintName="MiniRadio-iOS" ReferencedContainer="container:MiniRadio.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
schemes = folder / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "MiniRadio-iOS.xcscheme").write_text(scheme)
print("Generated iOS Xcode project and shared scheme.")
