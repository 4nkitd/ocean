import Foundation

/**
 How a part is addressed inside its message.

 v2 parts have no ids of their own: text and reasoning are keyed by their
 position in the message (`msg_x:3`), tools by the call that produced them
 (`msg_x:tool:call_y`). Deltas off the event stream arrive with an ordinal or a
 call id and nothing else, so a screen has to rebuild the key to find the part
 it is meant to update — which is what `PartKey` is for.

 Message ids never contain a colon, so the first one always ends the id.
 */
public enum PartKey: Hashable, Sendable {
  /// `msg_x:3` — a text or reasoning part, keyed by its position.
  case ordinal(messageID: String, ordinal: Int)
  /// `msg_x:tool:call_y`.
  case tool(messageID: String, callID: String)
  /// `msg_x:file:0` — an attachment on a user prompt.
  case file(messageID: String, index: Int)
  /// `msg_x:text` — the prompt (or summary) the message carries directly, which
  /// has no position in `content` at all.
  case text(messageID: String)

  public var messageID: String {
    switch self {
    case .ordinal(let id, _), .tool(let id, _), .file(let id, _), .text(let id): return id
    }
  }

  /// The key as it appears on `Part.id`.
  public var rawValue: String {
    switch self {
    case .ordinal(let id, let ordinal): return "\(id):\(ordinal)"
    case .tool(let id, let callID): return "\(id):tool:\(callID)"
    case .file(let id, let index): return "\(id):file:\(index)"
    case .text(let id): return "\(id):text"
    }
  }

  public init?(rawValue: String) {
    guard let separator = rawValue.firstIndex(of: ":") else { return nil }
    let messageID = String(rawValue[rawValue.startIndex..<separator])
    let rest = String(rawValue[rawValue.index(after: separator)...])
    guard !messageID.isEmpty, !rest.isEmpty else { return nil }

    if let callID = rest.dropPrefixIfPresent("tool:") {
      guard !callID.isEmpty else { return nil }
      self = .tool(messageID: messageID, callID: callID)
      return
    }
    if let index = rest.dropPrefixIfPresent("file:") {
      guard let index = Int(index) else { return nil }
      self = .file(messageID: messageID, index: index)
      return
    }
    if rest == "text" {
      self = .text(messageID: messageID)
      return
    }
    guard let ordinal = Int(rest) else { return nil }
    self = .ordinal(messageID: messageID, ordinal: ordinal)
  }
}

extension String {
  fileprivate func dropPrefixIfPresent(_ prefix: String) -> String? {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
  }
}
