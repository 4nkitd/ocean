import Foundation
import OceanKit

public enum DeliveryStatus: String, Codable, Hashable, Sendable {
  case sent
  case sending
  case failed
}

public struct SessionMessage: Identifiable, Hashable, Sendable {
  public var info: MessageInfo
  public var parts: [Part]
  public var delivery: DeliveryStatus
  public var failure: String?
  public var draft: String?
  public var draftAttachments: [PromptAttachment]

  public var id: String { info.id }

  public init(
    info: MessageInfo,
    parts: [Part] = [],
    delivery: DeliveryStatus = .sent,
    failure: String? = nil,
    draft: String? = nil,
    draftAttachments: [PromptAttachment] = []
  ) {
    self.info = info
    self.parts = parts
    self.delivery = delivery
    self.failure = failure
    self.draft = draft
    self.draftAttachments = draftAttachments
  }
}

public enum TodoStatus: String, Codable, Hashable, Sendable {
  case pending
  case in_progress
  case completed
  case cancelled
}

public struct TodoItem: Identifiable, Hashable, Sendable {
  public var id: String
  public var content: String
  public var status: TodoStatus

  public init(id: String, content: String, status: TodoStatus) {
    self.id = id
    self.content = content
    self.status = status
  }
}
