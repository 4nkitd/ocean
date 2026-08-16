import Combine
import Foundation
import OceanKit

@MainActor
public final class DeepLinkHandler: ObservableObject {
  public static let shared = DeepLinkHandler()

  @Published public var pending: OceanKit.DeepLink?

  public init() {}

  public func handle(_ url: URL) {
    guard let link = OceanKit.DeepLink.parse(url) else { return }
    pending = link
  }

  public func consume() -> OceanKit.DeepLink? {
    let link = pending
    pending = nil
    return link
  }
}
