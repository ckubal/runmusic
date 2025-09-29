import SwiftUI
import CoreLocation

struct PreviewRunHistoryView: View {
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var spotifyService = SpotifyService.shared
    @State private var sampleRuns: [RunActivity] = []
    @State private var showingConnectSheet = false
    
    var body: some View {
        let backgroundColors = [
            Color.orange.opacity(0.05),
            Color.pink.opacity(0.03),
            Color.white
        ]
        
        return NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Connect with Strava prompt at top
                    connectPromptSection
                    
                    // Sample runs list
                    sampleRunsSection
                }
            }
            .navigationTitle("preview")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            loadSampleData()
        }
        .sheet(isPresented: $showingConnectSheet) {
            AuthenticationView()
        }
    }
    
    private var connectPromptSection: some View {
        VStack(spacing: 16) {
            // Main connect banner
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect with Strava")
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Get your own run data")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Connect") {
                        showingConnectSheet = true
                    }
                    .font(.custom("Helvetica Neue", size: 15))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(22)
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(16)
                
                // Preview note
                Text("Below are sample runs to show you what the app looks like")
                    .font(.custom("Helvetica Neue", size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
    
    private var sampleRunsSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(sampleRuns) { run in
                    NavigationLink(destination: PreviewRunDetailView(run: run)) {
                        SampleRunRowView(run: run)
                    }
                }
                
                // Another connect button at the bottom
                Button(action: {
                    showingConnectSheet = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to see your own runs?")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Connect with Strava to get started")
                                .font(.custom("Helvetica Neue", size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.1), Color.pink.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.3), Color.pink.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    private func loadSampleData() {
        sampleRuns = SampleDataService.shared.createSampleRuns()
    }
}

struct SampleRunRowView: View {
    let run: RunActivity
    
    var body: some View {
        HStack(spacing: 0) {
            // Route visualization with gradient background
            let routeGradientColors = [
                Color.orange.opacity(0.2),
                Color.pink.opacity(0.15),
                Color.purple.opacity(0.1)
            ]
            let routeGradient = LinearGradient(
                colors: routeGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            ZStack {
                // Gradient background
                routeGradient
                
                RoutePathView(coordinates: run.routeCoordinates, lineWidth: 3)
                    .padding(8)
            }
            .frame(width: 80, height: 80)
            .cornerRadius(12)
            
            // Run details
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(run.name.lowercased())
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Sample badge
                    Text("SAMPLE")
                        .font(.custom("Helvetica Neue", size: 8))
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    
                    if let tracks = run.spotifyTracks, !tracks.isEmpty {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                HStack(spacing: 12) {
                    RunStatBadge(
                        icon: "figure.run",
                        value: String(format: "%.1f", run.distanceInMiles),
                        unit: "mi",
                        color: .orange
                    )
                    
                    RunStatBadge(
                        icon: "clock",
                        value: run.formattedDuration,
                        unit: "",
                        color: .blue
                    )
                    
                    RunStatBadge(
                        icon: "speedometer",
                        value: run.pacePerMile,
                        unit: "/mi",
                        color: .green
                    )
                }
                
                HStack {
                    if let city = run.city {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(city.lowercased())
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(formatDateForDisplay(run.date))
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }
}

struct PreviewRunDetailView: View {
    let run: RunActivity
    @StateObject private var userPreferences = UserPreferences.shared
    @State private var selectedFont: FontFamily?
    @State private var showingConnectSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Connect with Strava prompt at top
                connectBannerSection
                
                // Style controls section (but non-functional in preview)
                styleControlsSection
                
                // Interactive card
                InteractiveShareableCardView(
                    run: .constant(run),
                    layoutType: .portrait,
                    fontFamily: selectedFont
                )
                .aspectRatio(9.0/16.0, contentMode: .fit)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 20)
                
                // Sample disclaimer
                sampleDisclaimerSection
            }
            .padding(.vertical, 20)
        }
        .navigationTitle("sample run")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConnectSheet) {
            AuthenticationView()
        }
    }
    
    private var connectBannerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("This is a sample run")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Connect with Strava to see your own data")
                        .font(.custom("Helvetica Neue", size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Connect") {
                    showingConnectSheet = true
                }
                .font(.custom("Helvetica Neue", size: 14))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange)
                .cornerRadius(20)
            }
            .padding(16)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    private var styleControlsSection: some View {
        HStack(spacing: 16) {
            Text("Style Preview")
                .font(.custom("Helvetica Neue", size: 16))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Font selector (disabled in preview)
            FontSelectorButton(
                selectedFont: selectedFont ?? FontFamily.default,
                onFontSelected: { _ in
                    // No-op in preview mode
                }
            )
            .disabled(true)
            .opacity(0.6)
            
            // Color selector (disabled in preview)
            ColorSelectorButton(
                selectedScheme: run.portraitSettings.colorScheme ?? userPreferences.defaultColorScheme,
                onSchemeSelected: { _ in
                    // No-op in preview mode
                }
            )
            .disabled(true)
            .opacity(0.6)
        }
        .padding(.horizontal, 20)
    }
    
    private var sampleDisclaimerSection: some View {
        VStack(spacing: 12) {
            Text("Sample Data")
                .font(.custom("Helvetica Neue", size: 18))
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("This run includes sample route data, music tracks, and customizations to demonstrate the app's features. Connect with Strava to create cards with your own running and music data.")
                .font(.custom("Helvetica Neue", size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
            
            Button(action: {
                showingConnectSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                    Text("Connect with Strava")
                        .fontWeight(.semibold)
                }
                .font(.custom("Helvetica Neue", size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

#Preview {
    PreviewRunHistoryView()
}