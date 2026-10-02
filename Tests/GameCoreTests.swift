import XCTest

@testable import ExorciseCore

final class GameCoreTests: XCTestCase {
  struct Seeded: RandomNumberGenerator {
    var value: UInt64 = 42
    mutating func next() -> UInt64 {
      value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return value
    }
  }
  func card(tier: Int = 4, tool: Tool = .salt) -> SpiritCard {
    SpiritCard(
      tier: tier, spiritKey: String(format: "spirit_t%d_001", tier),
      requirements: [tool: (4 - tier) * 2 + 1], collected: true)
  }
  func testGenerationDistributionAndBounds() throws {
    var random = Seeded()
    var counts: [Int: Int] = [:]
    for _ in 0..<20000 {
      let card = SpiritCard.capture(using: &random)
      try card.validate()
      counts[card.tier, default: 0] += 1
      XCTAssertEqual(card.tapGoal, [1: 96, 2: 64, 3: 40, 4: 20][card.tier])
    }
    for (tier, expected) in [1: 0.1, 2: 0.2, 3: 0.3, 4: 0.4] {
      XCTAssertEqual(Double(counts[tier, default: 0]) / 20000, expected, accuracy: 0.02)
    }
  }
  func testAllTiersFundNextExorcismAndCannotRepeat() throws {
    for tier in 1...4 {
      var state = GameState()
      let card = card(tier: tier)
      state.cards = [card]
      try GameEngine.purchase(card.requirements, in: &state)
      let reward = try GameEngine.exorcise(card.id, holiness: 100, blessing: 36, in: &state)
      XCTAssertEqual(reward, card.reward)
      XCTAssertEqual(state.gold, 40 + 6 - tier)
      XCTAssertEqual(state.inventory[.salt], 0)
      XCTAssertEqual(state.cards.first?.kind, .blessed)
      XCTAssertNil(state.cards.first?.name)
      let done = state
      XCTAssertThrowsError(try GameEngine.exorcise(card.id, holiness: 1, blessing: 1, in: &state))
      XCTAssertEqual(state, done)
    }
  }
  func testFailedActionsDoNotMutate() throws {
    var state = GameState()
    let c = card()
    state.cards = [c]
    let original = state
    XCTAssertThrowsError(try GameEngine.purchase([.fist: 21], in: &state))
    XCTAssertEqual(state, original)
    XCTAssertThrowsError(try GameEngine.purchase([.fist: -1], in: &state))
    XCTAssertEqual(state, original)
    XCTAssertThrowsError(try GameEngine.purchase([:], in: &state))
    XCTAssertEqual(state, original)
    XCTAssertThrowsError(try GameEngine.exorcise(c.id, holiness: 50, blessing: 1, in: &state))
    XCTAssertEqual(state, original)
  }
  func testJobIsFreeAndIdempotent() throws {
    var state = GameState()
    let order = UUID()
    XCTAssertFalse(
      try GameEngine.serve(order: order, requested: .fist, supplied: .salt, in: &state))
    XCTAssertEqual(state.gold, 40)
    XCTAssertTrue(try GameEngine.serve(order: order, requested: .fist, supplied: .fist, in: &state))
    XCTAssertEqual(state.gold, 41)
    XCTAssertFalse(
      try GameEngine.serve(order: order, requested: .fist, supplied: .fist, in: &state))
    XCTAssertEqual(state.gold, 41)
    XCTAssertTrue(state.inventory.isEmpty)
  }
  func testInvalidCardRejected() throws {
    var invalid = card()
    invalid.holiness = 1
    XCTAssertThrowsError(try invalid.validate())
  }
  func testRepositoryRoundTripAndCorruptionPreserved() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let repo = try GameRepository(directory: dir)
    var state = GameState()
    let c = card()
    state.cards = [c]
    try repo.savePhoto(Data([1, 2, 3]), card: c)
    try repo.save(state)
    XCTAssertEqual(try repo.load(), state)
    XCTAssertEqual(try repo.photo(c), Data([1, 2, 3]))
    let path = dir.appendingPathComponent("game.json")
    let corrupt = Data("broken".utf8)
    try corrupt.write(to: path)
    XCTAssertThrowsError(try repo.load())
    XCTAssertEqual(try Data(contentsOf: path), corrupt)
  }
}
