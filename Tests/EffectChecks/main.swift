import Foundation
import Metal

guard let device = MTLCreateSystemDefaultDevice() else {
    fputs("GPU unavailable in this execution context; use View > Run GPU Effect Checks in the native app.\n",stderr); exit(2)
}
do { print(try EffectVerification.run(device: device)) }
catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
