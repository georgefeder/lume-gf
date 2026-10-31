import CoreGraphics
@testable import LookCore
import Testing

struct GFTabletopLayoutTests {
    // the iPhone Duo's inner display in portrait, in points at 3x (2007 x 2853 px)
    let duo = CGSize(width: 669, height: 951)

    @Test func `a fold across the screen puts the picture above it and the controls below`() {
        let fold = CGRect(x: 0, y: 470, width: 669, height: 11)
        let split = GFTabletopLayout.split(size: duo, folds: [fold])
        #expect(split?.video == CGRect(x: 0, y: 0, width: 669, height: 470))
        #expect(split?.panel == CGRect(x: 0, y: 481, width: 669, height: 470))
    }

    @Test func `no fold, or one folded like a book, keeps the player whole`() {
        #expect(GFTabletopLayout.split(size: duo, folds: []) == nil)
        let book = CGRect(x: 330, y: 0, width: 11, height: 669)
        #expect(GFTabletopLayout.split(size: CGSize(width: 951, height: 669), folds: [book]) == nil)
    }

    @Test func `a fold too near an edge keeps the player whole`() {
        #expect(GFTabletopLayout.split(size: duo, folds: [CGRect(x: 0, y: 60, width: 669, height: 10)]) == nil)
        #expect(GFTabletopLayout.split(size: duo, folds: [CGRect(x: 0, y: 880, width: 669, height: 10)]) == nil)
        // the controls need about 320 pt below the fold
        #expect(GFTabletopLayout.split(size: duo, folds: [CGRect(x: 0, y: 640, width: 669, height: 11)]) == nil)
        #expect(GFTabletopLayout.split(size: duo, folds: [CGRect(x: 0, y: 600, width: 669, height: 11)]) != nil)
    }

    @Test func `the picture stands on the fold`() {
        let above = CGRect(x: 0, y: 0, width: 669, height: 470)
        #expect(GFTabletopLayout.picture(in: above, aspect: 2) == CGRect(x: 0, y: 135.5, width: 669, height: 334.5))
        #expect(GFTabletopLayout.picture(in: above, aspect: nil) == above)
        // narrower than the room (as a 4:3 channel on the Duo): all of its height, centred
        #expect(GFTabletopLayout.picture(in: above, aspect: 1) == CGRect(x: 99.5, y: 0, width: 470, height: 470))
    }

    @Test func `the reflection follows the hinge`() {
        let upright = GFTabletopLayout.reflectionStretch(hingeDegrees: 90)
        #expect(abs(upright - 1.053) < 0.01)
        #expect(GFTabletopLayout.reflectionStretch(hingeDegrees: 75) > upright)
        #expect(GFTabletopLayout.reflectionStretch(hingeDegrees: 110) < upright)
        let opened = GFTabletopLayout.reflectionStretch(hingeDegrees: 110)
        #expect(GFTabletopLayout.reflectionStretch(hingeDegrees: 130) < opened)
        #expect(GFTabletopLayout.reflectionStretch(hingeDegrees: 170) == 0.15)
        #expect(GFTabletopLayout.reflectionStretch(hingeDegrees: nil) == 1)
    }

    @Test func `the controls take the whole width beside the front screen's side column, and only there`() {
        let front = CGSize(width: 457, height: 678)
        #expect(GFTabletopLayout.controlsUseWholeWidth(size: front, leading: 0, trailing: 84))
        #expect(GFTabletopLayout.controlsUseWholeWidth(size: front, leading: 84, trailing: 0)) // turned round
        #expect(!GFTabletopLayout.controlsUseWholeWidth(size: CGSize(width: 402, height: 874), leading: 0, trailing: 0))
        // an iPhone on its side: the Dynamic Island's inset stays clear
        let sideways = CGSize(width: 874, height: 402)
        #expect(!GFTabletopLayout.controlsUseWholeWidth(size: sideways, leading: 62, trailing: 62))
    }

    @Test func `the pretend fold splits the screen in the middle`() {
        let split = GFTabletopLayout.split(size: duo, folds: [GFTabletopLayout.demoFold(size: duo)])
        #expect(split?.video.height == 463.5 && split?.panel.height == 463.5)
    }
}
