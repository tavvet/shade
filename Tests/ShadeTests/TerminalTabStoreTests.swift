import XCTest
@testable import Shade
@testable import ShadeCore

final class TerminalTabStoreTests: XCTestCase {
    func testAppendAndSelectExposeActiveSession() {
        var store = TerminalTabStore<SessionStub>()
        let first = SessionStub()
        let second = SessionStub()

        XCTAssertEqual(store.append(first), 0)
        XCTAssertEqual(store.append(second), 1)
        XCTAssertNil(store.activeSession)

        XCTAssertTrue(store.select(at: 1))
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertTrue(store.activeSession === second)
        XCTAssertFalse(store.select(at: 2))
        XCTAssertEqual(store.activeIndex, 1)
    }

    func testNextAndPreviousSelectionWrapAround() {
        var store = TerminalTabStore<SessionStub>()
        store.append(SessionStub())
        store.append(SessionStub())
        store.append(SessionStub())
        store.select(at: 0)

        XCTAssertEqual(store.previousIndex, 2)
        store.select(at: store.previousIndex!)
        XCTAssertEqual(store.nextIndex, 0)
    }

    func testRemovingTabBeforeActiveKeepsSameLogicalSessionSelected() {
        var store = TerminalTabStore<SessionStub>()
        let first = SessionStub()
        let second = SessionStub()
        let third = SessionStub()
        store.append(first)
        store.append(second)
        store.append(third)
        store.select(at: 2)

        let removed = store.remove(at: 0)

        XCTAssertTrue(removed === first)
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertTrue(store.activeSession === third)
    }

    func testRemovingActiveTabSelectsPreviousTab() {
        var store = TerminalTabStore<SessionStub>()
        let first = SessionStub()
        let second = SessionStub()
        store.append(first)
        store.append(second)
        store.append(SessionStub())
        store.select(at: 1)

        let removed = store.remove(at: 1)

        XCTAssertTrue(removed === second)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertTrue(store.activeSession === first)
    }

    func testRemovingTabAfterActiveLeavesSelectionUnchanged() {
        var store = TerminalTabStore<SessionStub>()
        let active = SessionStub()
        store.append(active)
        store.append(SessionStub())
        let closing = SessionStub()
        store.append(closing)
        store.select(at: 0)

        XCTAssertTrue(store.remove(at: 2) === closing)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertTrue(store.activeSession === active)
    }

    func testRemovingFirstOrOnlyTabKeepsValidSelection() {
        var store = TerminalTabStore<SessionStub>()
        let first = SessionStub()
        let second = SessionStub()
        store.append(first)
        store.append(second)
        store.select(at: 0)

        XCTAssertTrue(store.remove(at: 0) === first)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertTrue(store.activeSession === second)

        XCTAssertTrue(store.remove(at: 0) === second)
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.activeIndex, -1)
        XCTAssertNil(store.activeSession)
    }

    func testIndexUsesObjectIdentity() {
        var store = TerminalTabStore<SessionStub>()
        let session = SessionStub()
        store.append(session)

        XCTAssertEqual(store.index(of: session), 0)
        XCTAssertNil(store.index(of: SessionStub()))
    }

    func testPinningMovesTabsLeftInPinOrderAndKeepsTheActiveSession() {
        var store = TerminalTabStore<SessionStub>()
        let tabs = (0..<4).map { _ in SessionStub() }
        tabs.forEach { store.append($0) }
        store.select(at: 1)

        XCTAssertTrue(store.setPinned(true, at: 2))
        XCTAssertTrue(store.setPinned(true, at: 3))

        XCTAssertEqual(store.pinnedCount, 2)
        XCTAssertTrue(store.sessions.elementsEqual([tabs[2], tabs[3], tabs[0], tabs[1]], by: ===))
        XCTAssertTrue(store.isPinned(at: 0))
        XCTAssertTrue(store.isPinned(at: 1))
        XCTAssertFalse(store.isPinned(at: 2))
        XCTAssertTrue(store.activeSession === tabs[1])
        XCTAssertFalse(store.setPinned(true, at: 0))
        XCTAssertFalse(store.setPinned(true, at: 9))
    }

    func testUnpinningPlacesTheTabFirstAmongUnpinnedTabs() {
        var store = TerminalTabStore<SessionStub>()
        let tabs = (0..<3).map { _ in SessionStub() }
        tabs.forEach { store.append($0) }
        store.setPinned(true, at: 1)
        store.setPinned(true, at: 2)
        store.select(at: 0)

        XCTAssertTrue(store.setPinned(false, at: 0))

        XCTAssertEqual(store.pinnedCount, 1)
        XCTAssertTrue(store.sessions.elementsEqual([tabs[2], tabs[1], tabs[0]], by: ===))
        XCTAssertTrue(store.activeSession === tabs[1])
        XCTAssertFalse(store.setPinned(false, at: 1))
    }

    func testRemovingAPinnedTabKeepsPinnedTabsLeading() {
        var store = TerminalTabStore<SessionStub>()
        let tabs = (0..<3).map { _ in SessionStub() }
        tabs.forEach { store.append($0) }
        store.setPinned(true, at: 0)
        store.setPinned(true, at: 1)

        store.remove(at: 0)
        let added = SessionStub()
        store.append(added)

        XCTAssertEqual(store.pinnedCount, 1)
        XCTAssertTrue(store.sessions.elementsEqual([tabs[1], tabs[2], added], by: ===))
        XCTAssertFalse(store.isPinned(at: 2))
    }
}

private final class SessionStub {}
