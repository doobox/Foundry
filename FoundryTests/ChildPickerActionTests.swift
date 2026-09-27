import Testing
@testable import Foundry

struct ChildPickerActionTests {
    @Test func noOptionsDisablesAdding() {
        let action = ChildPickerAction.resolve(options: [], childCount: 0, maximum: nil)
        #expect(action == .unavailable)
        #expect(action.isEnabled == false)
    }

    @Test func oneOptionAddsDirectly() {
        let action = ChildPickerAction.resolve(options: [.paragraph], childCount: 0, maximum: nil)
        #expect(action == .add(.paragraph))
        #expect(action.isEnabled)
    }

    @Test func severalOptionsOpenChooser() {
        let action = ChildPickerAction.resolve(options: [.paragraph, .heading], childCount: 1, maximum: 3)
        #expect(action == .choose)
        #expect(action.isEnabled)
    }

    @Test(arguments: [1, 2], [2, 3])
    func reachedOrExceededLimitDisablesBothPaths(_ optionCount: Int, _ count: Int) {
        let options = Array([PartType.paragraph, .heading].prefix(optionCount))
        let action = ChildPickerAction.resolve(options: options, childCount: count, maximum: 2)
        #expect(action == .limitReached)
        #expect(action.isEnabled == false)
    }

    @Test func removalOrCatalogChangesRecomputeTheAction() {
        #expect(ChildPickerAction.resolve(options: [.paragraph, .heading], childCount: 1, maximum: 1) == .limitReached)
        #expect(ChildPickerAction.resolve(options: [.paragraph, .heading], childCount: 0, maximum: 1) == .choose)
        #expect(ChildPickerAction.resolve(options: [.heading], childCount: 0, maximum: 1) == .add(.heading))
        #expect(ChildPickerAction.resolve(options: [], childCount: 0, maximum: 1) == .unavailable)
    }
}
