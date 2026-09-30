import XCTest

@testable import ExorciseCore

final class CharmSaleTests: XCTestCase {
  private func charm(_ holiness: Int) -> SpiritCard {
    SpiritCard(
      tier: 4, spiritKey: "spirit_t4_001", requirements: [.salt: 1],
      kind: .blessed, collected: true, holiness: holiness, blessingKey: "blessing_001")
  }
  func testPriceBandsCoverAllHolinessValues() {
    for (lower, upper, price) in [
      (1, 10, 3), (11, 20, 4), (21, 30, 5), (31, 40, 6), (41, 50, 7),
      (51, 60, 8), (61, 70, 9), (71, 80, 10), (81, 90, 11), (91, 100, 12),
    ] {
      for holiness in lower...upper { XCTAssertEqual(charm(holiness).salePrice, price) }
    }
    XCTAssertNil(charm(0).salePrice)
    XCTAssertNil(charm(101).salePrice)
  }
  func testOnlySelectedCharmIsSoldAndCannotBeSoldTwice() throws {
    var state = GameState()
    let sold = charm(94)
    let kept = charm(25)
    state.cards = [sold, kept]
    state.inventory = [.fist: 2]
    XCTAssertEqual(try GameEngine.sellCharm(sold.id, in: &state), 12)
    XCTAssertEqual(state.gold, 52)
    XCTAssertEqual(state.cards, [kept])
    XCTAssertEqual(state.inventory, [.fist: 2])
    let after = state
    XCTAssertThrowsError(try GameEngine.sellCharm(sold.id, in: &state))
    XCTAssertEqual(state, after)
  }
  func testHauntedAndUncollectedCardsCannotBeSold() {
    var haunted = charm(50)
    haunted.kind = .haunted
    haunted.holiness = nil
    haunted.blessingKey = nil
    var draft = charm(50)
    draft.collected = false
    for card in [haunted, draft] {
      var state = GameState()
      state.cards = [card]
      let before = state
      XCTAssertNil(card.salePrice)
      XCTAssertThrowsError(try GameEngine.sellCharm(card.id, in: &state))
      XCTAssertEqual(state, before)
    }
  }
  func testSalePersistsAcrossRepositoryReload() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let repo = try GameRepository(directory: dir)
    var state = GameState()
    let card = charm(50)
    state.cards = [card]
    try repo.save(state)
    try GameEngine.sellCharm(card.id, in: &state)
    try repo.save(state)
    let loaded = try repo.load()
    XCTAssertEqual(loaded.gold, 47)
    XCTAssertTrue(loaded.cards.isEmpty)
  }
  func testPriceDoesNotDependOnNameOrTier() {
    let first = charm(50)
    var other = first
    other.name = "Lucky Fist"
    other.tier = 1
    other.spiritKey = "spirit_t1_012"
    other.requirements = [.fist: 8]
    XCTAssertEqual(first.salePrice, other.salePrice)
  }
}
