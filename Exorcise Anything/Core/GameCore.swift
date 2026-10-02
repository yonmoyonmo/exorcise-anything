import Foundation

enum Tool: String, CaseIterable, Codable, Identifiable, Sendable {
  case garlic
  case holyWater = "holy_water"
  case salt
  case redBeans = "red_beans"
  case talisman, fist
  var id: String { rawValue }
  var key: String { "tool_" + rawValue }
  var asset: String { key }
  static let price = 2
}

enum CardKind: String, Codable, Sendable { case haunted, blessed }

struct SpiritCard: Identifiable, Codable, Equatable, Sendable {
  var id = UUID()
  var createdAt = Date()
  var tier: Int
  var spiritKey: String
  var requirements: [Tool: Int]
  var kind: CardKind = .haunted
  var collected = false
  var holiness: Int?
  var blessingKey: String?
  var name: String?
  var tapGoal: Int { [1: 96, 2: 64, 3: 40, 4: 20][tier] ?? 5 }
  var toolCount: Int { requirements.values.reduce(0, +) }
  var reward: Int { toolCount * Tool.price + (6 - tier) }
  /// Only completed, collected charms can be sold. Ten-point bands pay 3...12 G.
  var salePrice: Int? {
    guard kind == .blessed, collected, let holiness, (1...100).contains(holiness) else {
      return nil
    }
    return 3 + (holiness - 1) / 10
  }
  var photoName: String { id.uuidString + ".jpg" }

  static func capture<R: RandomNumberGenerator>(using rng: inout R) -> Self {
    let roll = Int.random(in: 0..<100, using: &rng)
    let tier = roll < 40 ? 4 : roll < 70 ? 3 : roll < 90 ? 2 : 1
    let count = Int.random(in: ((4 - tier) * 2 + 1)...((4 - tier) * 2 + 2), using: &rng)
    var tools: [Tool: Int] = [:]
    for _ in 0..<count { tools[Tool.allCases.randomElement(using: &rng)!, default: 0] += 1 }
    return Self(
      tier: tier,
      spiritKey: String(format: "spirit_t%d_%03d", tier, Int.random(in: 1...12, using: &rng)),
      requirements: tools)
  }

  func validate() throws {
    guard (1...4).contains(tier), !requirements.isEmpty,
      requirements.values.allSatisfy({ (1...8).contains($0) }),
      (((4 - tier) * 2 + 1)...((4 - tier) * 2 + 2)).contains(toolCount),
      (1...12).map({ String(format: "spirit_t%d_%03d", tier, $0) }).contains(spiritKey),
      (name?.count ?? 0) <= 40
    else { throw GameError.invalidData }
    if kind == .blessed {
      guard let holiness, (1...100).contains(holiness), let blessingKey,
        (1...36).map({ String(format: "blessing_%03d", $0) }).contains(blessingKey)
      else { throw GameError.invalidData }
    } else if holiness != nil || blessingKey != nil {
      throw GameError.invalidData
    }
  }
}

struct GameState: Codable, Equatable, Sendable {
  var version = 1
  var playerID = UUID()
  var gold = 40
  var inventory: [Tool: Int] = [:]
  var cards: [SpiritCard] = []
  var jobClaims: Set<UUID> = []
  func validate() throws {
    guard version == 1, gold >= 0, inventory.values.allSatisfy({ $0 >= 0 }),
      Set(cards.map(\.id)).count == cards.count
    else { throw GameError.invalidData }
    for card in cards { try card.validate() }
  }
}

enum GameError: String, Error, LocalizedError, Sendable {
  case insufficientGold = "error_gold"
  case insufficientTools = "error_tools"
  case cardMissing = "error_card_missing"
  case alreadyBlessed = "error_already_blessed"
  case invalidData = "error_invalid_data"
  case notSellable = "error_not_sellable"
  case emptyPurchase = "error_empty_purchase"
  case disk = "error_storage"
  case photo = "error_photo"
  var errorDescription: String? { NSLocalizedString(rawValue, comment: "") }
}

enum GameEngine {
  static func purchase(_ quantities: [Tool: Int], in state: inout GameState) throws {
    guard quantities.values.allSatisfy({ (0...999).contains($0) }) else {
      throw GameError.invalidData
    }
    let total = quantities.values.reduce(0, +) * Tool.price
    guard total > 0 else { throw GameError.emptyPurchase }
    guard state.gold >= total else { throw GameError.insufficientGold }
    state.gold -= total
    for (tool, count) in quantities { state.inventory[tool, default: 0] += count }
  }
  @discardableResult
  static func sellCharm(_ id: UUID, in state: inout GameState) throws -> Int {
    guard let index = state.cards.firstIndex(where: { $0.id == id }) else {
      throw GameError.cardMissing
    }
    let card = state.cards[index]
    try card.validate()
    guard let price = card.salePrice else { throw GameError.notSellable }
    let (gold, overflow) = state.gold.addingReportingOverflow(price)
    guard !overflow else { throw GameError.invalidData }
    state.cards.remove(at: index)
    state.gold = gold
    return price
  }
  static func exorcise(_ id: UUID, holiness: Int, blessing: Int, in state: inout GameState) throws
    -> Int
  {
    guard let index = state.cards.firstIndex(where: { $0.id == id }) else {
      throw GameError.cardMissing
    }
    let card = state.cards[index]
    guard card.kind == .haunted else { throw GameError.alreadyBlessed }
    guard (1...100).contains(holiness), (1...36).contains(blessing) else {
      throw GameError.invalidData
    }
    guard card.requirements.allSatisfy({ state.inventory[$0.key, default: 0] >= $0.value }) else {
      throw GameError.insufficientTools
    }
    for (tool, count) in card.requirements { state.inventory[tool, default: 0] -= count }
    state.gold += card.reward
    state.cards[index].kind = .blessed
    state.cards[index].collected = true
    state.cards[index].holiness = holiness
    state.cards[index].blessingKey = String(format: "blessing_%03d", blessing)
    return card.reward
  }
  static func serve(order: UUID, requested: Tool, supplied: Tool, in state: inout GameState) throws
    -> Bool
  {
    guard requested == supplied, !state.jobClaims.contains(order) else { return false }
    state.jobClaims.insert(order)
    state.gold += 1
    return true
  }
}
