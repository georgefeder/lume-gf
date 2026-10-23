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
    }

    @Test func `the pretend fold splits the screen in the middle`() {
        let split = GFTabletopLayout.split(size: duo, folds: [GFTabletopLayout.demoFold(size: duo)])
        #expect(split?.video.height == 463.5 && split?.panel.height == 463.5)
    }
}
