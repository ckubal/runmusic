import SwiftUI
import Foundation

struct SpotifyHistoryImportPrompt: View {
    let run: RunActivity
    let onImportTapped: () -> Void
    let onDismiss: (() -> Void)?
    
    @StateObject private var spotifyService = SpotifyService.shared
    @State private var isVisible = true
    
    /// Determines if this run qualifies for a history import prompt
    private var shouldShowPrompt: Bool {
        guard isVisible else { return false }
        
        // Only show if Spotify is connected but run has no music data
        guard spotifyService.isAuthenticated else { return false }
        guard run.spotifyTracks?.isEmpty != false else { return false }
        
        // Show for any run without music data (outside the 50 most recent tracks)
        // No need to check date - if it has no music, it needs import
        
        return true
    }
    
    /// Smart messaging based on run age and context
    private var promptMessage: PromptMessage {
        // Simple, direct message as per requirements
        return PromptMessage(
            title: "import spotify history to get music for all your historical runs",
            description: "your recent listening history only includes the last 50 tracks",
            urgency: .medium
        )
    }
    
    private struct PromptMessage {
        let title: String
        let description: String
        let urgency: Urgency
        
        enum Urgency {
            case low, medium, high
            
            var iconColor: Color {
                switch self {
                case .low: return .blue
                case .medium: return .orange
                case .high: return .purple
                }
            }
            
            var icon: String {
                switch self {
                case .low: return "music.note"
                case .medium: return "clock.arrow.circlepath"
                case .high: return "sparkles"
                }
            }
        }
    }
    
    var body: some View {
        if shouldShowPrompt {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: promptMessage.urgency.icon)
                        .font(.title2)
                        .foregroundColor(promptMessage.urgency.iconColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(promptMessage.title)
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(promptMessage.description)
                            .font(.custom("Helvetica Neue", size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let onDismiss = onDismiss {
                        Button {
                            withAnimation {
                                isVisible = false
                            }
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
                
                Button {
                    onImportTapped()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("import spotify history")
                    }
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [promptMessage.urgency.iconColor, promptMessage.urgency.iconColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(promptMessage.urgency.iconColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(promptMessage.urgency.iconColor.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Smart Prompt Detection

struct SpotifyHistoryBanner: View {
    let run: RunActivity
    @State private var showImportGuide = false
    
    var body: some View {
        SpotifyHistoryImportPrompt(
            run: run,
            onImportTapped: {
                showImportGuide = true
            },
            onDismiss: {
                // User dismissed the prompt - could save this preference
                print("📝 User dismissed Spotify history import prompt for run: \(run.name)")
            }
        )
        .sheet(isPresented: $showImportGuide) {
            SpotifyImportGuideView()
        }
    }
}

// MARK: - Run List Banner

struct SpotifyHistoryListBanner: View {
    let runs: [RunActivity]
    @StateObject private var spotifyService = SpotifyService.shared
    @State private var showImportGuide = false
    @State private var isVisible = true
    
    /// Analyzes runs to determine if we should show list-level import prompt
    private var shouldShowListBanner: Bool {
        guard isVisible else { return false }
        guard spotifyService.isAuthenticated else { return false }
        guard !spotifyService.hasImportedTracks() else { return false }
        
        // Count runs older than 30 days without music data
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let oldRunsWithoutMusic = runs.filter { run in
            run.date < thirtyDaysAgo && (run.spotifyTracks?.isEmpty != false)
        }
        
        // Show banner if user has 3+ old runs without music data
        return oldRunsWithoutMusic.count >= 3
    }
    
    private var bannerMessage: String {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let oldRunsCount = runs.filter { run in
            run.date < thirtyDaysAgo && (run.spotifyTracks?.isEmpty != false)
        }.count
        
        return "unlock music for \(oldRunsCount) older runs"
    }
    
    var body: some View {
        if shouldShowListBanner {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundColor(.purple)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bannerMessage)
                            .font(.custom("Helvetica Neue", size: 15))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("import your spotify history to see music for past runs")
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            isVisible = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                
                Button {
                    showImportGuide = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                        Text("import history")
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .sheet(isPresented: $showImportGuide) {
                SpotifyImportGuideView()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Usage in Run Lists (Individual Runs)

struct RunRowWithHistoryPrompt: View {
    let run: RunActivity
    let destination: AnyView
    @State private var showImportGuide = false
    
    var body: some View {
        VStack(spacing: 8) {
            // The actual run row
            destination
            
            // History import prompt if applicable
            SpotifyHistoryImportPrompt(
                run: run,
                onImportTapped: {
                    showImportGuide = true
                },
                onDismiss: nil // Don't show dismiss in list context
            )
        }
        .sheet(isPresented: $showImportGuide) {
            SpotifyImportGuideView()
        }
    }
}

// MARK: - Analytics Helper

extension SpotifyHistoryImportPrompt {
    
    /// Get analytics context for this prompt
    private var analyticsContext: [String: Any] {
        let monthsAgo = Calendar.current.dateComponents([.month], from: run.date, to: Date()).month ?? 0
        
        return [
            "run_age_months": monthsAgo,
            "run_date": run.date.timeIntervalSince1970,
            "urgency_level": promptMessage.urgency,
            "has_imported_history": spotifyService.hasImportedTracks(),
            "spotify_authenticated": spotifyService.isAuthenticated
        ]
    }
}

// MARK: - Preview

#Preview("Recent Run - No Prompt") {
    SpotifyHistoryImportPrompt(
        run: RunActivity(
            id: "1",
            name: "Recent Run", 
            date: Date(), // Today
            distance: 5000,
            elapsedTime: 1800,
            averagePace: 360,
            startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            routeCoordinates: [
                LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
                LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date())
            ],
            city: "San Francisco",
            neighborhood: "Mission District"
        ),
        onImportTapped: { print("Import tapped") },
        onDismiss: { print("Dismissed") }
    )
    .padding()
}

#Preview("Old Run - Shows Prompt") {
    SpotifyHistoryImportPrompt(
        run: RunActivity(
            id: "1",
            name: "Old Run", 
            date: Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date(),
            distance: 5000,
            elapsedTime: 1800,
            averagePace: 360,
            startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            routeCoordinates: [
                LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
                LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date())
            ],
            city: "San Francisco",
            neighborhood: "Mission District"
        ),
        onImportTapped: { print("Import tapped") },
        onDismiss: { print("Dismissed") }
    )
    .padding()
}