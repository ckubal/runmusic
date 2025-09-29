import Foundation
import StoreKit

// MARK: - Subscription Service

class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    @Published var isPremium: Bool = false
    @Published var isLoading: Bool = false
    
    // Premium subscription limits
    static let freeTrackLimit = 1000
    static let premiumTrackLimit = -1 // Unlimited
    
    private init() {
        // For testing purposes, enable premium access to test all fonts
        // In production, this would check actual StoreKit subscription status
        isPremium = true // TODO: Replace with actual subscription check
    }
    
    // MARK: - Track Limits
    
    var maxTrackLimit: Int {
        return isPremium ? Self.premiumTrackLimit : Self.freeTrackLimit
    }
    
    var isUnlimited: Bool {
        return isPremium && maxTrackLimit == -1
    }
    
    func trackLimitText() -> String {
        if isPremium {
            return "unlimited tracks"
        } else {
            return "up to \(Self.freeTrackLimit.formatted()) tracks"
        }
    }
    
    func shouldLimitTracks(_ trackCount: Int) -> Bool {
        guard !isPremium else { return false }
        return trackCount > Self.freeTrackLimit
    }
    
    func limitedTrackCount(_ tracks: [SpotifyTrack]) -> [SpotifyTrack] {
        guard !isPremium else { return tracks }
        
        // Return most recent tracks up to the limit
        let sortedTracks = tracks.sorted { $0.playedAt > $1.playedAt }
        return Array(sortedTracks.prefix(Self.freeTrackLimit))
    }
    
    // MARK: - Premium Features
    
    func canAccessPremiumFonts() -> Bool {
        return isPremium
    }
    
    func canAccessUnlimitedHistory() -> Bool {
        return isPremium
    }
    
    // MARK: - Subscription Management (Future Implementation)
    
    func purchasePremium() async {
        isLoading = true
        // TODO: Implement StoreKit 2 purchase flow
        // For now, just simulate success
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isPremium = true
        isLoading = false
    }
    
    func restorePurchases() async {
        isLoading = true
        // TODO: Implement StoreKit 2 restore
        try? await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
    }
}