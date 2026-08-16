import AppKit
import Foundation
import OceanKit
import UserNotifications

@MainActor
public final class SessionNotifier: NSObject, UNUserNotificationCenterDelegate {
  public static let shared = SessionNotifier()

  private var subscription: EventSubscription?
  private var notifiedKeys: Set<String> = []
  private var notifiedKeysOrder: [String] = []
  private var started = false

  public override init() {
    super.init()
  }

  public func start() {
    guard !started else { return }
    started = true

    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

    subscription = ConnectionStore.shared.onServerEvent { [weak self] event in
      Task { @MainActor in
        self?.handleEvent(event)
      }
    }
  }

  private func dedupe(_ key: String) -> Bool {
    if notifiedKeys.contains(key) {
      return true
    }
    notifiedKeys.insert(key)
    notifiedKeysOrder.append(key)
    if notifiedKeys.count > 100 {
      let removeCount = notifiedKeysOrder.count - 50
      if removeCount > 0 {
        let keysToRemove = notifiedKeysOrder.prefix(removeCount)
        for k in keysToRemove {
          notifiedKeys.remove(k)
        }
        notifiedKeysOrder.removeFirst(removeCount)
      }
    }
    return false
  }

  private func handleEvent(_ event: ServerEvent) {
    switch event.type {
    case "permission.requested", "permission.asked":
      let reqID = event.id ?? event["id"].string ?? event["requestID"].string ?? UUID().uuidString
      let toolOrAction = event["permission"]["tool"].string
        ?? event["permission"]["action"].string
        ?? event["action"].string
        ?? event["permission"]["description"].string
        ?? "Action requires approval"
      let key = "\(event.type):\(reqID):\(toolOrAction)"
      if dedupe(key) { return }

      postNotification(title: "Permission requested", body: toolOrAction)

    case "question.asked":
      let text = event["question"].string
        ?? event["prompt"].string
        ?? event["title"].string
        ?? "A question requires your response."
      let reqID = event.id ?? event["id"].string ?? event.sessionID ?? ""
      let key = "\(event.type):\(reqID):\(text)"
      if dedupe(key) { return }

      postNotification(title: "Question asked", body: text)

    case "form.opened", "form.created":
      let title = event["form"]["title"].string
        ?? event["title"].string
        ?? "A form requires input."
      let reqID = event.id ?? event["id"].string ?? event.sessionID ?? ""
      let key = "\(event.type):\(reqID):\(title)"
      if dedupe(key) { return }

      postNotification(title: "Form opened", body: title)

    case "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted":
      let sessionID = event.sessionID ?? event["sessionID"].string ?? ""
      let key = "\(event.type):\(sessionID)"
      if dedupe(key) { return }

      if NSApplication.shared.isActive { return }

      let title: String
      if event.type.hasSuffix("succeeded") {
        title = "Session Succeeded"
      } else if event.type.hasSuffix("failed") {
        title = "Session Failed"
      } else {
        title = "Session Interrupted"
      }

      let sessionTitle = event["title"].string
        ?? event["sessionTitle"].string
        ?? event["session"]["title"].string
        ?? (event.sessionID != nil ? "Session \(event.sessionID!)" : "Session completed")

      postNotification(title: title, body: sessionTitle)

    default:
      break
    }
  }

  private func postNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }
}
