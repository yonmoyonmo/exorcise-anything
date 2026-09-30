import Foundation

struct GameRepository {
  let directory: URL
  var stateURL: URL { directory.appendingPathComponent("game.json") }
  var photosURL: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
  init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
  }
  func load() throws -> GameState {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return GameState() }
    let state = try JSONDecoder().decode(GameState.self, from: Data(contentsOf: stateURL))
    try state.validate()
    return state
  }
  func save(_ state: GameState) throws {
    try state.validate()
    try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
  }
  func photoURL(_ card: SpiritCard) -> URL { photosURL.appendingPathComponent(card.photoName) }
  func photo(_ card: SpiritCard) throws -> Data { try Data(contentsOf: photoURL(card)) }
  func savePhoto(_ data: Data, card: SpiritCard) throws {
    guard !data.isEmpty, data.count <= 2_000_000 else { throw GameError.photo }
    try data.write(to: photoURL(card), options: .atomic)
  }
}
