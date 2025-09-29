import Foundation
import UserNotifications
import UIKit

@MainActor
class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isEnabled: Bool = false
    
    private init() {
        Task {
            await updateAuthorizationStatus()
        }
    }
    
    // MARK: - Permission Management
    
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
            await updateAuthorizationStatus()
            
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("✅ Push notification permission granted")
            } else {
                print("❌ Push notification permission denied")
            }
            
            return granted
        } catch {
            print("❌ Push notification permission error: \(error)")
            return false
        }
    }
    
    private func updateAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            self.isEnabled = settings.authorizationStatus == .authorized
        }
    }
    
    // MARK: - Notification Delivery
    
    func sendRunCompletionNotification(for run: RunActivity) async {
        guard authorizationStatus == .authorized else {
            print("⚠️ Push notifications not authorized, skipping notification")
            return
        }
        
        // Check if notifications are enabled in user preferences
        guard UserPreferences.shared.pushNotificationsEnabled else {
            print("⚠️ Push notifications disabled in settings, skipping notification")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "congrats on finishing a great run!"
        content.body = "check out your run's tunes graphic"
        content.sound = .default
        
        // Deep-link payload
        content.userInfo = [
            "runId": run.id,
            "action": "openRunDetail",
            "runName": run.name
        ]
        
        let request = UNNotificationRequest(
            identifier: "run-completion-\(run.id)",
            content: content,
            trigger: nil // Send immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📱 Push notification sent for run: \(run.name)")
        } catch {
            print("❌ Failed to send notification: \(error)")
        }
    }
    
    // MARK: - Notification Management
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func clearNotification(for runId: String) {
        let identifier = "run-completion-\(runId)"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    // MARK: - Deep Link Handling
    
    func handleNotificationResponse(_ response: UNNotificationResponse) -> String? {
        let userInfo = response.notification.request.content.userInfo
        
        if let action = userInfo["action"] as? String,
           action == "openRunDetail",
           let runId = userInfo["runId"] as? String {
            return runId
        }
        
        return nil
    }
}