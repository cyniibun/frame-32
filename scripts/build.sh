#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
# Hide a legacy duplicate module map left by some Command Line Tools upgrades.
# This overlay affects only this compiler invocation; system files stay untouched.
python3 - <<'PYOVERLAY'
import json, pathlib
root = pathlib.Path.cwd()
empty = root / '.build/empty.modulemap'
empty.write_text('// Legacy module map intentionally hidden for this build.\n')
overlay = {'version': 0, 'roots': [{'type': 'file', 'name': '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap', 'external-contents': str(empty)}]}
(root / '.build/toolchain-overlay.json').write_text(json.dumps(overlay))
PYOVERLAY
swiftc -vfsoverlay "$PWD/.build/toolchain-overlay.json" -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$PWD/.build/module-cache" Sources/FRAME32/*.swift -o .build/FRAME32
APP="$PWD/build/FRAME32.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/FRAME32 "$APP/Contents/MacOS/FRAME32.next"
mv -f "$APP/Contents/MacOS/FRAME32.next" "$APP/Contents/MacOS/FRAME32"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FRAME32</string>
<key>CFBundleIdentifier</key><string>com.cyniical.frame32</string>
<key>CFBundleName</key><string>FRAME32</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.6</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSCameraUsageDescription</key><string>FRAME32 uses your camera for local preview and processed video recording.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - <<'PYFINGERPRINT'
import hashlib, pathlib, plistlib
root=pathlib.Path.cwd()
names=['AdvancedEffects.swift','SignalProcessor.swift','SpatialKernels.swift','GlyphAtlas.swift','EffectRegistry.swift','EffectVerification.swift']
digest=hashlib.sha256()
for name in sorted(names):
    digest.update(name.encode()+b'\0'+(root/'Sources/FRAME32'/name).read_bytes())
p=root/'build/FRAME32.app/Contents/Info.plist'
info=plistlib.loads(p.read_bytes()); info['FRAME32GPUFingerprint']=digest.hexdigest()
p.write_bytes(plistlib.dumps(info))
PYFINGERPRINT
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
