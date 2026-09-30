import SwiftUI
#if os(iOS)
    import UIKit
#endif

extension View {
    /// The player's screen is dark. Lume asks for that with `.preferredColorScheme(.dark)`, which on iPhone and iPad first
    /// reached the whole app while the player was being set up: in light mode everything flashed dark before a channel
    /// opened (Georgs, build 8; filmed by ci/screenshots.sh). Here only the player's own screen is dark — its views
    /// through the environment, its view controller (so its menus and sheets too) through a trait override. The Apple
    /// TV (always dark) and the Mac (a window of its own) keep Lume's way.
    @ViewBuilder
    func gfPlayerScreenDark() -> some View {
        #if os(iOS)
            environment(\.colorScheme, .dark)
                .background(GFDarkScreenProbe().allowsHitTesting(false))
        #else
            preferredColorScheme(.dark)
        #endif
    }

    /// The player engines' own views: dark through the environment on iPhone and iPad (they can be shown inside other
    /// screens, whose view controller stays as it is).
    @ViewBuilder
    func gfPlayerContentDark() -> some View {
        #if os(iOS)
            environment(\.colorScheme, .dark)
        #else
            preferredColorScheme(.dark)
        #endif
    }
}

#if os(iOS)
    /// Makes the view controller showing the player (its full-screen cover or window) dark: that screen and whatever it
    /// presents, never the screen underneath.
    private struct GFDarkScreenProbe: UIViewRepresentable {
        func makeUIView(context _: Context) -> Probe {
            Probe()
        }

        func updateUIView(_: Probe, context _: Context) {}

        final class Probe: UIView {
            override func didMoveToWindow() {
                super.didMoveToWindow()
                var responder: UIResponder? = next
                while let current = responder {
                    if let controller = current as? UIViewController {
                        controller.overrideUserInterfaceStyle = .dark
                        return
                    }
                    responder = current.next
                }
            }
        }
    }
#endif
