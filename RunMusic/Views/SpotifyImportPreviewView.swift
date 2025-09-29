import SwiftUI

struct SpotifyImportPreviewView: View {
    let scanSummary: SpotifyFileScanner.ScanSummary
    let onImportRecent: () -> Void
    let onImportAll: () -> Void
    let onCancel: () -> Void
    
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showingPremiumInfo = false
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Summary header
                    summaryHeader
                    
                    // Recent tracks preview
                    if !scanSummary.recentTracks.isEmpty {
                        recentTracksSection
                    }
                    
                    // Import options
                    importOptionsSection
                    
                    // Premium info
                    if !subscriptionService.isPremium && scanSummary.totalTracks > 1000 {
                        premiumBanner
                    }
                }
                .padding()
            }
            .navigationTitle("import preview")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel") {
                        onCancel()
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingPremiumInfo) {
            // TODO: Add premium subscription view
            VStack(spacing: 20) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("unlock unlimited imports")
                    .font(.custom("Helvetica Neue", size: 24))
                    .fontWeight(.bold)
                
                Text("premium members can import their complete spotify history without limits")
                    .font(.custom("Helvetica Neue", size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button("learn more") {
                    // TODO: Show subscription options
                }
                .font(.custom("Helvetica Neue", size: 16))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.orange)
                .cornerRadius(25)
                
                Button("not now") {
                    showingPremiumInfo = false
                }
                .font(.custom("Helvetica Neue", size: 14))
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            .padding(40)
        }
    }
    
    private var summaryHeader: some View {
        VStack(spacing: 16) {
            // File count badge
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                
                Text("\(scanSummary.totalFiles) files selected")
                    .font(.custom("Helvetica Neue", size: 18))
                    .fontWeight(.semibold)
            }
            
            // Stats grid
            HStack(spacing: 20) {
                StatCard(
                    icon: "music.note",
                    value: formatNumber(scanSummary.totalTracks),
                    label: "total tracks",
                    color: .blue
                )
                
                if let dateRange = scanSummary.dateRange {
                    StatCard(
                        icon: "calendar",
                        value: "\(dateFormatter.string(from: dateRange.lowerBound))",
                        label: "oldest track",
                        color: .purple
                    )
                    
                    StatCard(
                        icon: "clock.fill",
                        value: "\(dateFormatter.string(from: dateRange.upperBound))",
                        label: "newest track",
                        color: .orange
                    )
                }
            }
        }
        .padding(.vertical, 20)
    }
    
    private var recentTracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("recent tracks preview")
                .font(.custom("Helvetica Neue", size: 16))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(Array(scanSummary.recentTracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .font(.custom("Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .lineLimit(1)
                            
                            Text("\(track.artist) • \(formatRelativeDate(track.playedAt))")
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            
            if scanSummary.recentTracks.count > 5 {
                Text("and \(scanSummary.recentTracks.count - 5) more recent tracks...")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            }
        }
    }
    
    private var importOptionsSection: some View {
        VStack(spacing: 12) {
            // Import recent tracks button
            Button(action: onImportRecent) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("import recent tracks")
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                        
                        Text("up to \(min(scanSummary.recentTracks.count, 1000)) most recent tracks")
                            .font(.custom("Helvetica Neue", size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .foregroundColor(.white)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            
            // Import all button (premium)
            Button(action: {
                if subscriptionService.isPremium || scanSummary.totalTracks <= 1000 {
                    onImportAll()
                } else {
                    showingPremiumInfo = true
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("import all tracks")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                            
                            if !subscriptionService.isPremium && scanSummary.totalTracks > 1000 {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Text("\(formatNumber(scanSummary.totalTracks)) total tracks")
                            .font(.custom("Helvetica Neue", size: 13))
                            .foregroundColor(.primary.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .foregroundColor(.primary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private var premiumBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("premium required for full import")
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.semibold)
                
                Text("upgrade to import more than 1,000 tracks")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.custom("Helvetica Neue", size: 16))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            
            Text(label)
                .font(.custom("Helvetica Neue", size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    SpotifyImportPreviewView(
        scanSummary: SpotifyFileScanner.ScanSummary(
            totalFiles: 12,
            totalTracks: 14523,
            mostRecentFile: nil,
            recentTracks: [],
            dateRange: Date(timeIntervalSince1970: 0)...Date()
        ),
        onImportRecent: {},
        onImportAll: {},
        onCancel: {}
    )
}