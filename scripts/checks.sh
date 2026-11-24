#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
FLAGS=(-vfsoverlay "$PWD/.build/toolchain-overlay.json" -swift-version 5 -module-cache-path "$PWD/.build/module-cache")
swiftc "${FLAGS[@]}" Sources/FRAME32/EffectRegistry.swift Sources/FRAME32/FrameClock.swift Sources/FRAME32/UserPresets.swift Sources/FRAME32/SpatialKernels.swift Sources/FRAME32/PreviewLayout.swift Tests/ParameterChecks/main.swift -o .build/ParameterChecks
.build/ParameterChecks "$PWD/.build"
swiftc "${FLAGS[@]}" Sources/FRAME32/EffectRegistry.swift Sources/FRAME32/SignalProcessor.swift Sources/FRAME32/AdvancedEffects.swift Sources/FRAME32/SpatialKernels.swift Sources/FRAME32/GlyphAtlas.swift Sources/FRAME32/EffectVerification.swift Tests/EffectChecks/main.swift -o .build/EffectChecks
# Metal may be unavailable to a restricted shell. Exit 2 means NOT RUN, not PASS.
set +e
.build/EffectChecks
GPU_RESULT=$?
set -e
codesign --verify --deep --strict build/FRAME32.app
if (( GPU_RESULT == 2 )); then
  # A native report is reusable only for the exact current GPU source fingerprint.
  python3 - <<'PYGATE'
from pathlib import Path
import plistlib,sys
info=plistlib.loads(Path('build/FRAME32.app/Contents/Info.plist').read_bytes())
fingerprint=info.get('FRAME32GPUFingerprint')
report=Path.home()/'Library/Application Support/FRAME32/verification-report.txt'
lines=report.read_text().splitlines() if report.exists() else []
if fingerprint and f'GPU SOURCE {fingerprint}' in lines and any(line.startswith('PASS / ') for line in lines) and not any('FAILED' in line for line in lines):
    print('PASS: matching native GPU regression report verified.')
else:
    print('NOT ACCEPTED: GPU regression tests did not run; no matching native pass exists.',file=sys.stderr)
    sys.exit(2)
PYGATE
elif (( GPU_RESULT != 0 )); then
  exit "$GPU_RESULT"
fi
