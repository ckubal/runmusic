import Foundation
import BackgroundTasks

@MainActor
class NewRunDetectionService: ObservableObject {
    static let shared = NewRunDetectionService()
    
    private let stravaService = StravaService.shared
    private let spotifyService = SpotifyService.shared
    private let dataConversion = DataConversionService.shared
    private let pushNotificationService = PushNotificationService.shared
    
    // Background task identifier
    private let backgroundTaskIdentifier = "com.runmusic.newrun-check"
    
    // Constants
    private let notificationWindow: TimeInterval = 6 * 60 * 60 // 6 hours
    private let maxProcessingTime: TimeInterval = 25 // 25 seconds to stay within 30-second limit
    
    private init() {
        scheduleBackgroundRefresh()
    }
    
    // MARK: - Background Task Management
    
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes minimum
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 New run detection background task scheduled")
        } catch {
            print("❌ Failed to schedule new run detection task: \(error)")
        }
    }
    
    func handleBackgroundAppRefresh(task: BGAppRefreshTask) {
        print("🔄 New run detection background refresh triggered")
        
        // Schedule next background task
        scheduleBackgroundRefresh()
        
        // Set up timeout handling
        task.expirationHandler = {
            print("⏰ New run detection background task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Perform the check with timeout protection
        Task {
            let startTime = Date()
            await checkForNewRuns()
            
            let processingTime = Date().timeIntervalSince(startTime)
            print("⏱️ New run detection completed in \(processingTime)s")
            
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - New Run Detection
    
    func checkForNewRuns() async {
        guard stravaService.isAuthenticated else {
            print("⚠️ Strava not authenticated, skipping new run check")
            return
        }
        
        guard UserPreferences.shared.pushNotificationsEnabled else {
            print("⚠️ Push notifications disabled, skipping new run check")
            return
        }
        
        print("🔄 Checking for new runs...")
        
        do {
            // Get latest activities from Strava (only fetch a few to save time)
            let activities = try await stravaService.fetchActivities(page: 1, perPage: 3)
            
            for activity in activities {
                // Only process runs
                guard activity.type == "Run" else { continue }
                
                // Check if this is a new run we haven't processed
                if isNewRunForNotification(activity) {
                    print("🏃‍♂️ New run detected: \(activity.name)")
                    await processNewRunForNotification(activity)
                    break // Only process one run per background refresh to save time
                }
            }
            
        } catch {
            print("❌ Failed to check for new runs: \(error)")
        }
    }
    
    private func isNewRunForNotification(_ activity: StravaActivity) -> Bool {
        // Parse the start date from ISO8601 string
        let dateFormatter = ISO8601DateFormatter()
        guard let startDate = dateFormatter.date(from: activity.startDate) else {
            print("⚠️ Failed to parse activity start date: \(activity.startDate)")
            return false
        }
        
        // Check if run is within notification window
        let timeSinceRun = Date().timeIntervalSince(startDate)
        guard timeSinceRun <= notificationWindow else {
            return false
        }
        
        // Check if we haven't already processed this run
        let lastProcessedRunId = UserDefaults.standard.string(forKey: "lastNotificationRunId")
        guard "\(activity.id)" != lastProcessedRunId else {
            return false
        }
        
        return true
    }
    
    private func processNewRunForNotification(_ activity: StravaActivity) async {
        let startTime = Date()
        
        do {
            // Check timeout before starting
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                print("⏰ Processing timeout reached before starting, skipping notification")
                return
            }
            
            // 1. Get detailed activity data from Strava
            let detailedActivity = try await stravaService.fetchDetailedActivity(id: activity.id)
            let streams = try await stravaService.fetchActivityStreams(id: activity.id, types: ["latlng", "time"])
            
            // Check timeout after Strava calls
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                print("⏰ Processing timeout reached after Strava calls, skipping notification")
                return
            }
            
            // 2. Convert to RunActivity with detailed data
            let run = await dataConversion.convertStravaActivityToRunActivity(activity, detailedActivity: detailedActivity, streams: streams)
            
            // 3. Get Spotify tracks for the run timeframe
            var runWithSpotify = run
            if spotifyService.isAuthenticated {
                do {
                    let spotifyTracks = try await spotifyService.fetchRecentlyPlayed(
                        startTime: run.date,
                        endTime: run.date.addingTimeInterval(run.elapsedTime)
                    )
                    runWithSpotify.spotifyTracks = spotifyTracks
                    print("📱 Found \(spotifyTracks.count) Spotify tracks for run")
                } catch {
                    print("⚠️ Failed to fetch Spotify tracks: \(error)")
                    // Continue without Spotify data
                }
            }
            
            // Check timeout after processing
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                print("⏰ Processing timeout reached after data processing, skipping notification")
                return
            }
            
            // 4. Verify we have sufficient data for a complete card
            guard isRunDataCompleteForNotification(runWithSpotify) else {
                print("⚠️ Run data incomplete, skipping notification")
                // Save this run ID so we don't keep trying to process it
                UserDefaults.standard.set("\(activity.id)", forKey: "lastNotificationRunId")
                return
            }
            
            // 5. Send the push notification
            await sendRunCompletionNotification(for: runWithSpotify)
            
            // 6. Mark this run as processed
            UserDefaults.standard.set("\(activity.id)", forKey: "lastNotificationRunId")
            
            print("✅ Notification sent for run: \(runWithSpotify.name)")
            
        } catch {
            print("❌ Failed to process new run for notification: \(error)")
            // Still mark as processed to avoid retrying failed runs
            UserDefaults.standard.set("\(activity.id)", forKey: "lastNotificationRunId")
        }
    }
    
    private func isRunDataCompleteForNotification(_ run: RunActivity) -> Bool {
        // Must have basic run data
        guard run.distance > 0, run.elapsedTime > 0 else {
            print("⚠️ Missing basic run data (distance/elapsedTime)")
            return false
        }
        
        // Must have route coordinates
        guard !run.routeCoordinates.isEmpty else {
            print("⚠️ Missing route coordinates")
            return false
        }
        
        // Should have at least some Spotify tracks (but not required for notification)
        if let spotifyTracks = run.spotifyTracks, spotifyTracks.isEmpty {
            print("ℹ️ No Spotify tracks found, but proceeding with notification")
        } else if run.spotifyTracks == nil {
            print("ℹ️ No Spotify data, but proceeding with notification")
        }
        
        return true
    }
    
    private func sendRunCompletionNotification(for run: RunActivity) async {
        await pushNotificationService.sendRunCompletionNotification(for: run)
    }
    
    // MARK: - Manual Testing
    
    func testNewRunDetection() async {
        print("🧪 Testing new run detection...")
        await checkForNewRuns()
    }
    
    // MARK: - State Management
    
    func resetLastProcessedRun() {
        UserDefaults.standard.removeObject(forKey: "lastNotificationRunId")
        print("🔄 Reset last processed run ID")
    }
    
    func getLastProcessedRunId() -> String? {
        return UserDefaults.standard.string(forKey: "lastNotificationRunId")
    }
}