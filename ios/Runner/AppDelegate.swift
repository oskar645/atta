import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var tapEventChannel: FlutterEventChannel?
  private let tapStreamHandler = PushTapStreamHandler()
  private var tokenResult: FlutterResult?
  private var currentDeviceToken: String?
  private var initialNotification: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerPushChannels()
    if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      initialNotification = normalizeUserInfo(remoteNotification)
    }
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    currentDeviceToken = token
    tokenResult?(token)
    tokenResult = nil
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    tokenResult?(
      FlutterError(
        code: "apns_registration_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
    tokenResult = nil
  }

  private func registerPushChannels() {
    guard let registrar = registrar(forPlugin: "AttaPushNotifications") else {
      return
    }
    let messenger = registrar.messenger()
    pushChannel = FlutterMethodChannel(
      name: "atta/push_notifications",
      binaryMessenger: messenger
    )
    pushChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handlePushMethod(call: call, result: result)
    }
    tapEventChannel = FlutterEventChannel(
      name: "atta/push_notification_taps",
      binaryMessenger: messenger
    )
    tapEventChannel?.setStreamHandler(tapStreamHandler)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = normalizeUserInfo(response.notification.request.content.userInfo)
    tapStreamHandler.send(payload)
    completionHandler()
  }

  private func handlePushMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestToken":
      requestToken(result: result)
    case "getInitialNotification":
      result(initialNotification)
      initialNotification = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestToken(result: @escaping FlutterResult) {
    if let token = currentDeviceToken {
      result(token)
      return
    }
    tokenResult = result
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      if let error = error {
        DispatchQueue.main.async {
          self.tokenResult?(
            FlutterError(
              code: "push_permission_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          self.tokenResult = nil
        }
        return
      }
      guard granted else {
        DispatchQueue.main.async {
          self.tokenResult?(nil)
          self.tokenResult = nil
        }
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }
}

private final class PushTapStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var bufferedPayload: [String: Any]?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    if let payload = bufferedPayload {
      events(payload)
      bufferedPayload = nil
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func send(_ payload: [String: Any]) {
    if let sink = sink {
      sink(payload)
    } else {
      bufferedPayload = payload
    }
  }
}

private func normalizeUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
  var result: [String: Any] = [:]
  for (key, value) in userInfo {
    result[String(describing: key)] = normalizePushValue(value)
  }
  return result
}

private func normalizePushValue(_ value: Any) -> Any {
  if let dict = value as? [AnyHashable: Any] {
    return normalizeUserInfo(dict)
  }
  if let array = value as? [Any] {
    return array.map { normalizePushValue($0) }
  }
  return value
}
