import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class GameStore {
  private(set) var state: GameState
  private let repository: GameRepository
  private let cache = NSCache<NSString, UIImage>()
  var errorMessage: String?
  var toast: String?
  var gold: Int { state.gold }
  var drafts: [SpiritCard] {
    state.cards.filter { !$0.collected && $0.kind == .haunted }.sorted {
      $0.createdAt > $1.createdAt
    }
  }

  init(directory: URL? = nil) throws {
    let root =
      try directory
      ?? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("ExorciseAnything", isDirectory: true)
    repository = try GameRepository(directory: root)
    state = try repository.load()
    cache.countLimit = 30
  }
  func card(_ id: UUID) -> SpiritCard? { state.cards.first { $0.id == id } }
  func count(_ tool: Tool) -> Int { state.inventory[tool, default: 0] }
  func image(_ card: SpiritCard) -> UIImage? {
    if let image = cache.object(forKey: card.photoName as NSString) { return image }
    guard let data = try? repository.photo(card), let image = UIImage(data: data) else {
      return nil
    }
    cache.setObject(image, forKey: card.photoName as NSString)
    return image
  }
  private func mutate(_ action: (inout GameState) throws -> Void) throws {
    var next = state
    try action(&next)
    do { try repository.save(next) } catch { throw GameError.disk }
    state = next
  }
  func report(_ error: Error) {
    errorMessage = (error as? GameError)?.errorDescription ?? L("error_generic")
  }
  @discardableResult func perform(_ action: () throws -> Void) -> Bool {
    do {
      try action()
      return true
    } catch {
      report(error)
      return false
    }
  }
  func capture(_ image: UIImage) throws -> UUID {
    var rng = SystemRandomNumberGenerator()
    let card = SpiritCard.capture(using: &rng)
    let edge: CGFloat = 1000
    let scale = min(1, edge / max(image.size.width, image.size.height))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let resized = UIGraphicsImageRenderer(
      size: CGSize(width: image.size.width * scale, height: image.size.height * scale),
      format: format
    ).image { _ in
      image.draw(
        in: CGRect(
          origin: .zero,
          size: CGSize(width: image.size.width * scale, height: image.size.height * scale)))
    }
    guard let data = resized.jpegData(compressionQuality: 0.75) else { throw GameError.photo }
    try repository.savePhoto(data, card: card)
    try mutate { $0.cards.append(card) }
    return card.id
  }
  func collect(_ id: UUID) throws {
    try mutate { state in
      guard let i = state.cards.firstIndex(where: { $0.id == id }) else {
        throw GameError.cardMissing
      }
      state.cards[i].collected = true
    }
  }
  func rename(_ id: UUID, to name: String) throws {
    try mutate { state in
      guard let i = state.cards.firstIndex(where: { $0.id == id }), state.cards[i].kind == .blessed
      else { throw GameError.cardMissing }
      let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
      state.cards[i].name = trimmed.isEmpty ? nil : trimmed
    }
  }
  func delete(_ id: UUID) throws {
    let old = card(id)
    try mutate { state in
      state.cards.removeAll { $0.id == id }
    }
    if let old {
      try? FileManager.default.removeItem(at: repository.photoURL(old))
      cache.removeObject(forKey: old.photoName as NSString)
    }
  }
  @discardableResult
  func sellCharm(_ id: UUID) throws -> Int {
    let sold = card(id)
    var payment = 0
    try mutate { payment = try GameEngine.sellCharm(id, in: &$0) }
    // The save is committed before removing the photo or publishing the sale.
    if let sold {
      try? FileManager.default.removeItem(at: repository.photoURL(sold))
      cache.removeObject(forKey: sold.photoName as NSString)
    }
    return payment
  }
  func purchase(_ quantities: [Tool: Int]) throws {
    try mutate { try GameEngine.purchase(quantities, in: &$0) }
  }
  func exorcise(_ id: UUID) throws -> Int {
    var reward = 0
    try mutate {
      reward = try GameEngine.exorcise(
        id, holiness: Int.random(in: 1...100), blessing: Int.random(in: 1...36), in: &$0)
    }
    return reward
  }
  func serve(order: UUID, requested: Tool, supplied: Tool) throws -> Bool {
    var success = false
    try mutate {
      success = try GameEngine.serve(
        order: order, requested: requested, supplied: supplied, in: &$0)
    }
    return success
  }
}
