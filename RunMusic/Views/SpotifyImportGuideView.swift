import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct SpotifyImportGuideView: View {
    @StateObject private var spotifyService = SpotifyService.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var importStatus: String?
    @State private var importError: String?
    @State private var isEnrichingAlbumArt = false
    @State private var albumArtEnrichmentStatus: String?
    @State private var showSignInPrompt = false
    @StateObject private var importSession = SpotifyImportSession()
    @State private var showingProgressView = false
    
    // New background import states
    @State private var showingPreviewView = false
    @State private var scanSummary: SpotifyFileScanner.ScanSummary?
    @State private var selectedFiles: [URL] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.largeTitle)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("spotify extended history")
                                    .font(.custom("Helvetica Neue", size: 24))
                                    .fontWeight(.bold)
                                
                                Text("access your complete listening history")
                                    .font(.custom("Helvetica Neue", size: 16))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("by importing your extended streaming history, you can see spotify songs for runs from any time period—not just the last 50 tracks.")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.primary)
                            
                            HStack {
                                Image(systemName: subscriptionService.isPremium ? "crown.fill" : "person.fill")
                                    .foregroundColor(subscriptionService.isPremium ? .orange : .blue)
                                Text(subscriptionService.trackLimitText())
                                    .font(.custom("Helvetica Neue", size: 14))
                                    .fontWeight(.medium)
                                    .foregroundColor(subscriptionService.isPremium ? .orange : .blue)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Current Import Status
                    if spotifyService.hasImportedTracks() {
                        let info = spotifyService.getImportedTracksInfo()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("imported data available")
                                    .font(.custom("Helvetica Neue", size: 16))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            Text("\(info.count.formatted()) tracks")
                                .font(.custom("Helvetica Neue", size: 20))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("\(info.dateRange)")
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.secondary)
                            
                            // Background sync status
                            if spotifyService.isAuthenticated && firebaseAuth.isAuthenticated {
                                Text("✨ new spotify data is automatically synced in the background")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                                    .padding(.top, 4)
                            }
                            
                            // Action Buttons Section
                            HStack(spacing: 12) {
                                if isEnrichingAlbumArt {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("enriching album art...")
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Button("enrich album art") {
                                        Task {
                                            await enrichAlbumArt()
                                        }
                                    }
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        LinearGradient(
                                            colors: [.green, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                                }
                                
                                Spacer()
                                
                                Button("add more data") {
                                    if firebaseAuth.isAuthenticated {
                                        // If user is already connected to Spotify, show helpful message
                                        if spotifyService.isAuthenticated {
                                            albumArtEnrichmentStatus = "✨ background sync is active - new spotify data is automatically collected. you only need to import additional historical data if you want older listening history."
                                            
                                            // Clear status after 8 seconds
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                                                albumArtEnrichmentStatus = nil
                                            }
                                        }
                                        showingFilePicker = true
                                    } else {
                                        showSignInPrompt = true
                                    }
                                }
                                .font(.custom("Helvetica Neue", size: 12))
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .padding(.top, 8)
                            
                            // Album Art Enrichment Status
                            if let status = albumArtEnrichmentStatus {
                                Text(status)
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(16)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }
                    
                    // Steps
                    VStack(alignment: .leading, spacing: 20) {
                        StepView(
                            number: 1,
                            title: "request your data from spotify",
                            description: "go to spotify's privacy settings and request your extended streaming history",
                            action: {
                                if let url = URL(string: "https://www.spotify.com/us/account/privacy/") {
                                    UIApplication.shared.open(url)
                                }
                            },
                            actionText: "open spotify privacy"
                        )
                        
                        StepView(
                            number: 2,
                            title: "wait for your data",
                            description: "spotify will email you when your data is ready (usually within 30 days)",
                            icon: "clock"
                        )
                        
                        StepView(
                            number: 3,
                            title: "download and extract",
                            description: "download the zip file from spotify and extract all the JSON files (they'll be named like 'Streaming_History_Audio_2023_0.json')",
                            icon: "archivebox"
                        )
                        
                        StepView(
                            number: 4,
                            title: "import to run the tunes",
                            description: "sign in to your account to securely store your spotify data across devices. \(subscriptionService.trackLimitText()) will be imported from your selected files.",
                            action: {
                                if firebaseAuth.isAuthenticated {
                                    showingFilePicker = true
                                } else {
                                    showSignInPrompt = true
                                }
                            },
                            actionText: firebaseAuth.isAuthenticated ? "choose json files" : "sign in to import",
                            isPrimary: true
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Temporary import status (shows only briefly after import)
                    if let status = importStatus {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("import complete")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                            
                            Text(status)
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .onAppear {
                            // Clear the temporary status after 5 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                withAnimation {
                                    importStatus = nil
                                }
                            }
                        }
                    }
                    
                    if let error = importError {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("import failed")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                            
                            Text(error)
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }
                    
                    // FAQ
                    VStack(alignment: .leading, spacing: 16) {
                        Text("frequently asked questions")
                            .font(.custom("Helvetica Neue", size: 20))
                            .fontWeight(.bold)
                            .padding(.horizontal, 20)
                        
                        FAQView(
                            question: "what is extended streaming history?",
                            answer: "spotify's extended streaming history contains your complete listening history with accurate timestamps, going back to when you first used spotify. the regular api only shows your last 50 tracks."
                        )
                        
                        FAQView(
                            question: "is this data secure?",
                            answer: "yes, your data is secure. if you're signed in, your spotify history is stored in your private firebase account and synced across devices. if not signed in, data is stored locally on your device. we never share your data with third parties."
                        )
                        
                        FAQView(
                            question: "how long does spotify take to provide the data?",
                            answer: "spotify typically takes 5-30 days to prepare your extended streaming history after you request it."
                        )
                        
                        FAQView(
                            question: "will my imported data persist if I reinstall the app?",
                            answer: "yes, if you're signed in to your account, your imported spotify data is stored in the cloud and will be restored when you sign in on any device. without signing in, data is only stored locally."
                        )
                        
                        FAQView(
                            question: "how many tracks can I import?",
                            answer: "free accounts can import up to 1,000 tracks from your most recent listening history. premium accounts get unlimited track imports. if you have more tracks than your limit, the most recent ones will be imported first."
                        )
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("import guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done") {
                        dismiss()
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.orange)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showSignInPrompt) {
            SignInPromptView(
                context: .spotifyImport,
                onSignIn: {
                    showSignInPrompt = false
                    Task {
                        await firebaseAuth.signInWithGoogle()
                    }
                },
                onDismiss: {
                    showSignInPrompt = false
                },
                onContinueWithoutSignIn: {
                    showSignInPrompt = false
                }
            )
        }
        .sheet(isPresented: $showingPreviewView) {
            if let summary = scanSummary {
                SpotifyImportPreviewView(
                    scanSummary: summary,
                    onImportRecent: {
                        showingPreviewView = false
                        Task {
                            await startBackgroundImport(importType: .recent)
                        }
                    },
                    onImportAll: {
                        showingPreviewView = false
                        Task {
                            await startBackgroundImport(importType: .all)
                        }
                    },
                    onCancel: {
                        showingPreviewView = false
                        scanSummary = nil
                        selectedFiles = []
                    }
                )
            }
        }
        .overlay(
            // Background import progress overlay
            BackgroundImportProgressView(importSession: importSession),
            alignment: .bottom
        )
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let jsonUrls = urls.filter { $0.pathExtension.lowercased() == "json" }
            selectedFiles = jsonUrls
            
            print("🔍 Starting smart file scanning for \(jsonUrls.count) files...")
            
            Task {
                do {
                    // Quick scan files to show preview
                    let scanner = SpotifyFileScanner.shared
                    let summary = try await scanner.quickScanFiles(jsonUrls)
                    
                    await MainActor.run {
                        scanSummary = summary
                        showingPreviewView = true
                    }
                } catch {
                    await MainActor.run {
                        importError = "Failed to scan files: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            importError = "Failed to select files: \(error.localizedDescription)"
        }
    }
    
    private func importFilesWithProgress(_ urls: [URL]) async {
        await MainActor.run {
            importSession.isImporting = true
            importSession.isCompleted = false
        }
        
        print("🎵 Starting import of \(urls.count) files with progress tracking")
        
        // Process all JSON files with individual progress tracking
        for (index, url) in urls.enumerated() {
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Could not access security scoped resource: \(url.lastPathComponent)")
                await updateFileProgress(index: index, status: .failed, errorMessage: "Could not access file")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            await updateFileProgress(index: index, status: .reading, progress: 0.1)
            
            do {
                print("📁 Processing: \(url.lastPathComponent)")
                let data = try Data(contentsOf: url)
                print("📁 File size: \(data.count) bytes")
                
                await updateFileProgress(index: index, status: .parsing, progress: 0.3)
                
                // Enhanced import method that provides progress callbacks
                let tracks = try await spotifyService.importExtendedStreamingHistoryWithProgress(from: data) { progress in
                    Task { @MainActor in
                        if index < importSession.files.count {
                            importSession.files[index].progress = 0.3 + (progress * 0.4) // Parsing takes 30-70%
                        }
                    }
                }
                
                await updateFileProgress(index: index, status: .storing, progress: 0.7)
                
                // Apply subscription-based track limits
                let limitedTracks = subscriptionService.limitedTrackCount(tracks)
                let wasLimited = tracks.count != limitedTracks.count
                
                // The storing happens inside the import method, but we'll update to completed
                await updateFileProgress(
                    index: index, 
                    status: .completed, 
                    progress: 1.0,
                    tracksRead: tracks.count,
                    tracksImported: limitedTracks.count
                )
                
                if wasLimited {
                    print("🎵 Track limit applied: \(tracks.count) tracks read, \(limitedTracks.count) imported (\(subscriptionService.trackLimitText()))")
                }
                
                print("✅ Successfully processed \(url.lastPathComponent) - \(limitedTracks.count) tracks imported")
            } catch {
                print("❌ Failed to process JSON file \(url.lastPathComponent): \(error)")
                await updateFileProgress(
                    index: index, 
                    status: .failed, 
                    errorMessage: error.localizedDescription
                )
            }
        }
        
        await MainActor.run {
            importSession.isImporting = false
            importSession.isCompleted = true
        }
        
        print("🎵 Import session completed - \(importSession.successfulFiles)/\(importSession.totalFilesSelected) files successful")
    }
    
    @MainActor
    private func updateFileProgress(
        index: Int, 
        status: FileImportProgress.ImportStatus, 
        progress: Double = 0.0,
        tracksRead: Int = 0,
        tracksImported: Int = 0,
        errorMessage: String? = nil
    ) {
        guard index < importSession.files.count else { return }
        
        importSession.files[index].status = status
        importSession.files[index].progress = progress
        if tracksRead > 0 { importSession.files[index].tracksRead = tracksRead }
        if tracksImported > 0 { importSession.files[index].tracksImported = tracksImported }
        if let error = errorMessage { importSession.files[index].errorMessage = error }
    }
    
    // MARK: - Background Import Methods
    
    enum ImportType {
        case recent // Import recent 1000 tracks (free tier)
        case all    // Import all tracks (premium)
    }
    
    private func startBackgroundImport(importType: ImportType) async {
        guard let summary = scanSummary, !selectedFiles.isEmpty else {
            print("❌ No scan summary or files available for import")
            return
        }
        
        await MainActor.run {
            // Initialize import session for background processing
            importSession.files = selectedFiles.map { url in
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                return FileImportProgress(fileName: url.lastPathComponent, fileSize: fileSize)
            }
        }
        
        print("🚀 Starting background import (\(importType == .recent ? "recent" : "all") tracks)")
        
        // Apply track limits based on subscription and import type
        let trackLimit = importType == .recent ? SubscriptionService.freeTrackLimit : 
                        (subscriptionService.isPremium ? nil : SubscriptionService.freeTrackLimit)
        
        await importFilesWithTrackLimit(selectedFiles, trackLimit: trackLimit)
    }
    
    private func importFilesWithTrackLimit(_ urls: [URL], trackLimit: Int?) async {
        await MainActor.run {
            importSession.isImporting = true
            importSession.isCompleted = false
        }
        
        print("🎵 Starting scalable background import of \(urls.count) files (limit: \(trackLimit?.formatted() ?? "unlimited"))")
        
        var totalTracksProcessed = 0
        // Use reasonable maximum to prevent memory issues (50,000 tracks should be plenty)
        let maxTracksToImport = trackLimit ?? 50000
        
        // Sort files by number (highest first for most recent)
        let sortedUrls = urls.sorted { url1, url2 in
            let number1 = extractFileNumber(from: url1.lastPathComponent)
            let number2 = extractFileNumber(from: url2.lastPathComponent)
            return number1 > number2 // Process highest numbered files first
        }
        
        print("🔢 Processing files in order (highest number = most recent):")
        for url in sortedUrls {
            let fileNumber = extractFileNumber(from: url.lastPathComponent)
            print("   - \(url.lastPathComponent) (file #\(fileNumber))")
        }
        
        // Process files in order of recency, stopping when we hit the limit
        for (index, url) in sortedUrls.enumerated() {
            guard totalTracksProcessed < maxTracksToImport else {
                print("📊 Track limit reached (\(maxTracksToImport)), stopping import")
                await updateFileProgress(index: index, status: .completed, progress: 1.0)
                break
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Could not access security scoped resource: \(url.lastPathComponent)")
                await updateFileProgress(index: index, status: .failed, errorMessage: "Could not access file")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            await updateFileProgress(index: index, status: .reading, progress: 0.1)
            
            do {
                print("📁 Processing: \(url.lastPathComponent) (\(totalTracksProcessed)/\(maxTracksToImport) tracks)")
                let data = try Data(contentsOf: url)
                
                await updateFileProgress(index: index, status: .parsing, progress: 0.3)
                
                // Parse tracks but limit the number we process
                let remainingLimit = maxTracksToImport - totalTracksProcessed
                let tracks = try await spotifyService.importExtendedStreamingHistoryWithLimit(
                    from: data,
                    trackLimit: remainingLimit
                ) { progress in
                    Task { @MainActor in
                        if index < importSession.files.count {
                            importSession.files[index].progress = 0.3 + (progress * 0.4)
                        }
                    }
                }
                
                await updateFileProgress(index: index, status: .storing, progress: 0.7)
                
                let actualTracksImported = tracks.count
                totalTracksProcessed += actualTracksImported
                
                await updateFileProgress(
                    index: index,
                    status: .completed,
                    progress: 1.0,
                    tracksRead: actualTracksImported,
                    tracksImported: actualTracksImported
                )
                
                print("✅ Successfully processed \(url.lastPathComponent) - \(actualTracksImported) tracks imported (\(totalTracksProcessed) total)")
                
            } catch {
                print("❌ Failed to process JSON file \(url.lastPathComponent): \(error)")
                await updateFileProgress(
                    index: index,
                    status: .failed,
                    errorMessage: error.localizedDescription
                )
            }
        }
        
        await MainActor.run {
            importSession.isImporting = false
            importSession.isCompleted = true
            
            // Show completion status
            if totalTracksProcessed >= maxTracksToImport && maxTracksToImport < Int.max {
                importStatus = "Successfully imported \(totalTracksProcessed.formatted()) tracks (\(subscriptionService.trackLimitText()) limit reached)"
            } else {
                importStatus = "Successfully imported \(totalTracksProcessed.formatted()) tracks from \(importSession.successfulFiles) files"
            }
        }
        
        print("🎵 Background import completed - \(totalTracksProcessed) MOST RECENT tracks imported")
        
        // Auto-enrich album art if Spotify is authenticated
        if spotifyService.isAuthenticated {
            print("🎨 Auto-enriching album art for imported tracks...")
            await MainActor.run {
                isEnrichingAlbumArt = true
                albumArtEnrichmentStatus = "automatically enriching album art..."
            }
            
            await spotifyService.enrichImportedTracksWithAlbumArt()
            
            await MainActor.run {
                isEnrichingAlbumArt = false
                albumArtEnrichmentStatus = "album art enriched! your tracks now have covers"
                
                // Clear status after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    albumArtEnrichmentStatus = nil
                }
            }
        }
    }
    
    // Extract file number from Spotify export filename (e.g., "Streaming_History_Audio_2023_4.json" -> 4)
    private func extractFileNumber(from filename: String) -> Int {
        // Look for pattern like "_X.json" where X is a number
        let components = filename.replacingOccurrences(of: ".json", with: "").components(separatedBy: "_")
        
        // Try to find a number at the end
        for component in components.reversed() {
            if let number = Int(component) {
                return number
            }
        }
        
        // If no number found, return 0 (will be processed last)
        return 0
    }
    
    private func enrichAlbumArt() async {
        await MainActor.run {
            isEnrichingAlbumArt = true
            albumArtEnrichmentStatus = nil
        }
        
        // Check if Spotify is authenticated
        guard spotifyService.isAuthenticated else {
            await MainActor.run {
                isEnrichingAlbumArt = false
                albumArtEnrichmentStatus = "please connect to spotify first to enrich album art"
            }
            return
        }
        
        print("🎨 Starting album art enrichment...")
        await spotifyService.enrichImportedTracksWithAlbumArt()
        
        await MainActor.run {
            isEnrichingAlbumArt = false
            albumArtEnrichmentStatus = "album art enrichment complete! your imported tracks now have album covers"
            
            // Clear status after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                albumArtEnrichmentStatus = nil
            }
        }
    }
}

struct StepView: View {
    let number: Int
    let title: String
    let description: String
    var action: (() -> Void)? = nil
    var actionText: String? = nil
    var icon: String? = nil
    var isPrimary: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number or icon
            ZStack {
                Circle()
                    .fill(isPrimary ? Color.green : Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(isPrimary ? .white : .blue)
                } else {
                    Text("\(number)")
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(isPrimary ? .white : .blue)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let action = action, let actionText = actionText {
                    Button(action: action) {
                        HStack(spacing: 8) {
                            Text(actionText)
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                            
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isPrimary ? Color.green : Color.blue.opacity(0.1))
                        .foregroundColor(isPrimary ? .white : .blue)
                        .cornerRadius(20)
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
    }
}

struct FAQView: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(answer)
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(12)
                    .padding(.top, -12)
            }
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    SpotifyImportGuideView()
}