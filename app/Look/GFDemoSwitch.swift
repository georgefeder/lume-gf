import SwiftUI

/// Lume GF: the app's root view. The screenshot build (`-D GF_DEMO`, ci/screenshots.sh) shows the demo when started
/// with `-GFDemo`; every other build is exactly Lume's `ContentView`.
struct GFDemoSwitch<Real: View>: View {
    @ViewBuilder var real: () -> Real

    var body: some View {
        #if GF_DEMO
            if GFDemo.mode != nil {
                GFDemoRoot()
            } else {
                real()
            }
        #else
            real()
        #endif
    }
}
