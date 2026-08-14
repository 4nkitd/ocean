import SwiftUI

extension View {
  /// The Vue client's `title=""`. There is no drawn tooltip in this app: macOS
  /// already has one, it is placed correctly against the screen edges, and it
  /// respects the system's delay. `nil` attaches nothing at all.
  @ViewBuilder
  public func tooltip(_ text: String?) -> some View {
    if let text, !text.isEmpty {
      help(text)
    } else {
      self
    }
  }
}
