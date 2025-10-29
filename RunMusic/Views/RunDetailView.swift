import SwiftUI
import Photos
import AVFoundation
import MapKit

struct RunDetailView: View {
    @State private var run: RunActivity
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var photoService = PhotoService.shared
    @StateObject private var spotifyService = SpotifyService.shared
    @State private var showShareSheet = false
    @State private var showShareMenu = false
    @State private var renderedImage: UIImage?
    @State private var showingPhotoManagement = false
    @State private var availablePhotos: [PHAsset] = []
    @State private var isLoadingPhotos = false
    @State private var currentCardTransforms: ShareableCardTransforms?
    @State private var interactiveCardView: InteractiveShareableCardView?
    // Always use portrait mode (simplified)
    private let currentLayoutType: ShareableCardLayoutType = .portrait
    @State private var isSongSelectionExpanded = false
    @State private var showAdvancedShareSheet = false
    @State private var showSignInPrompt = false
    @State private var showAlbumArtInfo = false
    @State private var albumArtUpdateTrigger = UUID() // Force UI updates when album art changes
    @State private var pendingSaveAction: (() -> Void)?
    @State private var showSpotifyImportGuide = false
    @State private var selectedFont: FontFamily?
    @State private var showPhotoPermissionPrompt = false
    // Stats visibility - now bound to run settings instead of local state
    private var showDate: Bool {
        run.portraitSettings.showDate ?? true
    }
    
    private var showTime: Bool {
        run.portraitSettings.showTime ?? true
    }
    
    private var showPace: Bool {
        run.portraitSettings.showPace ?? true
    }
    
    private var showTemperature: Bool {
        run.portraitSettings.showTemperature ?? true
    }
    @State private var showStatsExpanded = false
    @State private var showUnsavedChangesAlert = false
    @State private var exportedScreenshot: UIImage?
    @State private var showExportSheet = false
    @State private var originalRunSettings: LayoutSpecificSettings?
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    @Environment(\.dismiss) private var dismiss
    
    init(run: RunActivity) {
        self._run = State(initialValue: run)
        print("🐛 DEBUG: RunDetailView initialized for run: \(run.name)")
    }
    
    // MARK: - Reset Functionality
    
    private func resetAllCustomizations() {
        // Reset all layout-specific settings to defaults
        run.portraitSettings = LayoutSpecificSettings()
        
        // Reset global preferences to defaults  
        selectedFont = nil
        
        // Clear any custom photo background
        run.portraitSettings.backgroundPhoto = nil
        
        // Reset any album art displays to empty array
        run.portraitSettings.albumArtDisplays = []
        
        // Reset card transforms to defaults
        currentCardTransforms = ShareableCardTransforms(
            trackListOffset: .zero,
            trackListScale: 1.0,
            trackListRotation: .zero,
            trackListZIndex: 0,
            routeOffset: .zero,
            routeScale: 1.0,
            routeRotation: .zero,
            routeZIndex: 0
        )
        
        // Force view update by triggering state change
        albumArtUpdateTrigger = UUID()
        
        print("🔄 Reset all customizations to defaults")
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                styleControlsSection
                shareableCardSection
                livePhotoSelectionSection
                cardCustomizationSection
                powerSongSection
                
                // Spotify History Import Prompt for Old Runs
                SpotifyHistoryBanner(run: run)
                
                runDetailsSection
                
                // Debug section for weather data source (can be removed later)
                if let weather = run.weatherData, let dataSource = weather.dataSource {
                    HStack {
                        Spacer()
                        Text("Weather: \(dataSource.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
                
                locationSection
                
                // Reset button section
                resetButtonSection
                
                Spacer(minLength: 20)
            }
            .padding(.top, 16)
        }
        .navigationTitle("run details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    handleBackNavigation()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.orange)
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button("Save") {
                        handleSaveAction()
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    
                    Button {
                        handleShareAction(for: currentLayoutType)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = renderedImage {
                ShareSheetView(activityItems: [image])
            }
        }
        .sheet(isPresented: $showingPhotoManagement) {
            PhotoManagementView(
                run: $run,
                availablePhotos: availablePhotos,
                onPhotoSelected: { photoBackground in
                    setCurrentLayoutBackgroundPhoto(photoBackground)
                    photoService.savePhotoBackground(photoBackground, for: run.id)
                }
            )
        }
        .sheet(isPresented: $showAdvancedShareSheet) {
            AdvancedShareView(run: $run, currentLayout: currentLayoutType, showDate: showDate, showTime: showTime, showPace: showPace, showTemperature: showTemperature)
        }
        .sheet(isPresented: $showSpotifyImportGuide) {
            SpotifyImportGuideView()
                .environmentObject(firebaseAuth)
        }
        .sheet(isPresented: $showExportSheet) {
            if let image = exportedScreenshot {
                ShareSheetView(activityItems: [image])
            }
        }
        .alert("album art info", isPresented: $showAlbumArtInfo) {
            Button("got it") { }
        } message: {
            Text("album art appears when you've listened to a few songs from the same album.")
        }
        .alert("unsaved changes", isPresented: $showUnsavedChangesAlert) {
            Button("discard changes", role: .destructive) {
                dismiss()
            }
            Button("save changes") {
                handleSaveAction()
            }
            Button("cancel", role: .cancel) { }
        } message: {
            Text("you have unsaved changes to this run. would you like to save them?")
        }
        .onAppear {
            print("🐛 DEBUG: RunDetailView appeared for run: \(run.name)")
            // Load saved settings for this run
            userPreferences.loadRunSettings(for: &run)
            
            // Capture original settings for change detection
            originalRunSettings = LayoutSpecificSettings(
                showCity: run.portraitSettings.showCity,
                showSongs: run.portraitSettings.showSongs,
                showDate: run.portraitSettings.showDate,
                showTime: run.portraitSettings.showTime,
                showPace: run.portraitSettings.showPace,
                backgroundPhoto: run.portraitSettings.backgroundPhoto,
                colorScheme: run.portraitSettings.colorScheme,
                fontFamily: run.portraitSettings.fontFamily,
                albumArtDisplays: run.portraitSettings.albumArtDisplays,
                powerSongDisplay: run.portraitSettings.powerSongDisplay,
                hasUnsavedChanges: false,
                lastModified: run.portraitSettings.lastModified
            )
            
            // Only load saved photo background, don't request photo access until needed
            loadSavedPhotoBackground()
            // Check photo permissions and load photos if authorized
            photoService.checkAuthorizationStatus()
            if photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited {
                loadPhotosForRun()
            }
            // Lazy load album art when opening run details
            loadAlbumArtWhenNeeded()
            // Calculate Power Song if not already calculated
            calculatePowerSongIfNeeded()
            // Initialize Power Song display if it exists but isn't set up
            initializePowerSongDisplayIfNeeded()
        }
        .onChange(of: photoService.authorizationStatus) { _, newStatus in
            // When permission status changes, load photos if now authorized
            if newStatus == .authorized || newStatus == .limited {
                loadPhotosForRun()
            }
        }
    }
    
    // MARK: - View Sections
    
    private var shareableCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InteractiveShareableCardView(
                run: $run,
                layoutType: currentLayoutType,
                fontFamily: selectedFont,
                showDate: showDate,
                showTime: showTime,
                showPace: showPace,
                showTemperature: showTemperature
            ) { transforms in
                currentCardTransforms = transforms
            }
            .aspectRatio(currentLayoutType.aspectRatio, contentMode: .fit)
            .shadow(radius: 8)
            .padding(.horizontal, 20)
            .allowsHitTesting(true) // Ensure touch events reach the interactive elements
            .background(
                // This allows us to capture the card view as a reference
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            // Store the geometry for screenshot capture
                        }
                }
            )
            .onAppear {
                // Initialize font selection if not set
                if selectedFont == nil {
                    selectedFont = run.portraitSettings.fontFamily ?? userPreferences.defaultFontFamily
                }
            }
            
            // Enhanced export button with animation
            AnimatedActionButton(
                title: "export card",
                systemImage: "square.and.arrow.down",
                color: .orange,
                action: exportCardScreenshot
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
    
    private var styleControlsSection: some View {
        HStack(spacing: 12) {
            // Left side: All toggle controls (Date, Time, Pace, Temperature, Location)
            HStack(spacing: 12) {
                // Date toggle
                BouncyIconButton(
                    iconName: "calendar",
                    isActive: showDate,
                    activeColor: .gray,
                    size: 18
                ) {
                    print("🐛 DEBUG: Date toggle tapped, current showDate: \(showDate)")
                    withAnimation {
                        run.portraitSettings.showDate = !showDate
                        run.markAsChanged(layout: currentLayoutType)
                        print("🐛 DEBUG: Date toggle updated, new showDate: \(!showDate)")
                    }
                }
                
                // Time toggle
                BouncyIconButton(
                    iconName: "clock.fill",
                    isActive: showTime,
                    activeColor: .gray,
                    size: 18
                ) {
                    print("🐛 DEBUG: Time toggle tapped, current showTime: \(showTime)")
                    withAnimation {
                        run.portraitSettings.showTime = !showTime
                        run.markAsChanged(layout: currentLayoutType)
                        print("🐛 DEBUG: Time toggle updated, new showTime: \(!showTime)")
                    }
                }
                
                // Pace toggle
                BouncyIconButton(
                    iconName: "speedometer",
                    isActive: showPace,
                    activeColor: .gray,
                    size: 18
                ) {
                    print("🐛 DEBUG: Pace toggle tapped, current showPace: \(showPace)")
                    withAnimation {
                        run.portraitSettings.showPace = !showPace
                        run.markAsChanged(layout: currentLayoutType)
                        print("🐛 DEBUG: Pace toggle updated, new showPace: \(!showPace)")
                    }
                }
                
                // Temperature toggle
                if run.weatherData != nil {
                    BouncyIconButton(
                        iconName: "thermometer",
                        isActive: showTemperature,
                        activeColor: .gray,
                        size: 18
                    ) {
                        print("🐛 DEBUG: Temperature toggle tapped, current showTemperature: \(showTemperature)")
                        withAnimation {
                            run.portraitSettings.showTemperature = !showTemperature
                            run.markAsChanged(layout: currentLayoutType)
                            print("🐛 DEBUG: Temperature toggle updated, new showTemperature: \(!showTemperature)")
                        }
                    }
                }
                
                // Location toggle (moved from cardCustomizationSection)
                BouncyIconButton(
                    iconName: "location.fill",
                    isActive: run.portraitSettings.showCity ?? userPreferences.showCityByDefault,
                    activeColor: .gray,
                    size: 18
                ) {
                    withAnimation {
                        run.portraitSettings.showCity = !(run.portraitSettings.showCity ?? userPreferences.showCityByDefault)
                        run.markAsChanged(layout: currentLayoutType)
                    }
                }
            }
            
            Spacer()
            
            // Right side: Font and color selectors
            HStack(spacing: 12) {
                // Font selector button
                FontSelectorButton(
                    selectedFont: selectedFont ?? UserPreferences.shared.defaultFontFamily,
                    onFontSelected: { font in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedFont = font
                            run.portraitSettings.fontFamily = font
                            run.markAsChanged(layout: currentLayoutType)
                        }
                    }
                )
                
                // Color selector button  
                ColorSelectorButton(
                    selectedScheme: run.portraitSettings.colorScheme ?? UserPreferences.shared.defaultColorScheme,
                    onSchemeSelected: { scheme in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            run.portraitSettings.colorScheme = scheme
                            run.markAsChanged(layout: currentLayoutType)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    
    private var livePhotoSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("background photo")
                .font(.custom("Helvetica Neue", size: 18))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
            
            if needsPhotoPermission {
                photoPermissionPromptView
            } else {
                LivePhotoSelectionView(
                    run: $run,
                    layoutType: currentLayoutType,
                    availablePhotos: availablePhotos
                )
            }
        }
    }
    
    private var needsPhotoPermission: Bool {
        let status = photoService.authorizationStatus
        return status == .notDetermined || status == .denied || status == .restricted
    }
    
    private var cardCustomizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("card options")
                .font(.custom("Helvetica Neue", size: 18))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                
                // Spotify Connection Prompt for Track Selection
                if !spotifyService.isAuthenticated && (run.spotifyTracks?.isEmpty != false) {
                    SpotifyConnectionBanner(context: .trackSelection)
                }
                
                // Animated songs toggle
                if run.spotifyTracks != nil && !run.spotifyTracks!.isEmpty {
                    AnimatedToggleButton(
                        title: "show songs",
                        systemImage: "music.note",
                        isOn: showSongsBinding,
                        tintColor: .green
                    )
                    
                    // Song selection UI when songs are enabled
                    if currentLayoutSettings.showSongs ?? userPreferences.showSongsByDefault {
                        AnimatedDropdown(
                            title: {
                                let visibleCount = run.spotifyTracks?.filter { $0.isVisible }.count ?? 0
                                return "select songs to display (\(visibleCount) selected)"
                            }(),
                            isExpanded: $isSongSelectionExpanded
                        ) {
                            VStack(spacing: 8) {
                                LazyVStack(spacing: 4) {
                                    let sortedTracks = run.spotifyTracks!.sorted { $0.playedAt < $1.playedAt }
                                    let indexedTracks = Array(sortedTracks.enumerated())
                                    ForEach(indexedTracks, id: \.offset) { index, track in
                                        CompactSongSelectionRow(
                                            track: track,
                                            index: index + 1,
                                            isVisible: Binding(
                                                get: { track.isVisible },
                                                set: { newValue in
                                                    if let trackIndex = run.spotifyTracks?.firstIndex(where: { $0.id == track.id }) {
                                                        run.spotifyTracks?[trackIndex].isVisible = newValue
                                                        run.markAsChanged(layout: currentLayoutType)
                                                    }
                                                }
                                            )
                                        )
                                    }
                                }
                                .padding(.horizontal, 12)
                                
                                // Warning if more than 10 selected
                                let visibleCount = run.spotifyTracks?.filter { $0.isVisible }.count ?? 0
                                if visibleCount > 10 {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        
                                        Text("only first 10 songs will show on card")
                                            .font(.custom("Helvetica Neue", size: 11))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 12)
                                } else {
                                    Spacer()
                                        .frame(height: 12)
                                }
                            }
                        }
                    }
                    
                    // Spotify Connection Prompt for Album Art
                    if !spotifyService.isAuthenticated && (run.spotifyTracks?.isEmpty != false) {
                        SpotifyConnectionBanner(context: .albumArt)
                    }
                    
                    // Album Art Section
                    if !run.availableAlbumArt.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("album art")
                                    .font(.custom("Helvetica Neue", size: 14))
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    showAlbumArtInfo = true
                                }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                                
                                let visibleAlbumCount = currentLayoutSettings.albumArtDisplays?.filter { $0.isVisible }.count ?? 0
                                Text("\(visibleAlbumCount) selected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.orange)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            
                            // Album art selection grid (horizontal scroll)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(run.availableAlbumArt) { albumArt in
                                        AlbumArtSelectionTile(
                                            albumArt: albumArt,
                                            isSelected: isAlbumArtSelected(albumArt),
                                            onToggle: {
                                                toggleAlbumArtVisibility(albumArt)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                                .id(albumArtUpdateTrigger) // Force refresh when album art selection changes
                            }
                        }
                    }
                }
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    private var missingSpotifyDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "music.note.slash")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("no spotify data for this run")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("connect spotify or import historical data to see what music powered this run")
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Action buttons
            VStack(spacing: 12) {
                if !spotifyService.isAuthenticated {
                    Button(action: {
                        if let authURL = spotifyService.authURL {
                            UIApplication.shared.open(authURL)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                            Text("connect spotify")
                        }
                        .font(.custom("Helvetica Neue", size: 15))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                    }
                }
                
                Button(action: {
                    showSpotifyImportGuide = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("import historical data")
                    }
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var photoBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("background photo")
                .font(.custom("Helvetica Neue", size: 18))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                if currentLayoutSettings.backgroundPhoto != nil {
                    // Current photo preview
                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("photo background active")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.primary)
                            
                            Text("\(currentLayoutSettings.backgroundPhoto?.filterType.displayName ?? "unknown") filter")
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("change") {
                            loadPhotosForRun()
                            showingPhotoManagement = true
                        }
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    
                    // Remove photo option
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.title2)
                        
                        Text("remove background photo")
                            .font(.custom("Helvetica Neue", size: 16))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button("remove") {
                            setCurrentLayoutBackgroundPhoto(nil)
                            photoService.removePhotoBackground(for: run.id)
                        }
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                } else {
                    // Add photo option
                    HStack {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("add background photo")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.primary)
                            
                            if isLoadingPhotos {
                                Text("loading photos...")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            } else if availablePhotos.isEmpty {
                                Text("camera roll access required")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                let runTimeCount = availablePhotos.count // We'll assume some are from run time
                                if runTimeCount > 0 {
                                    Text("\(availablePhotos.count) photo\(availablePhotos.count == 1 ? "" : "s") available")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.green)
                                } else {
                                    Text("recent photos available")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if isLoadingPhotos {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if photoService.authorizationStatus == .denied {
                            Button("settings") {
                                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsUrl)
                                }
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.blue)
                        } else {
                            Button("choose") {
                                loadPhotosForRun()
                                showingPhotoManagement = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    private var runDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("run details")
                .font(.custom("Helvetica Neue", size: 16))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            // Condensed single-line run details
            HStack(spacing: 20) {
                // Distance
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("\(userPreferences.formatDistance(run.distance)) \(userPreferences.distanceUnit.displayName)")
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.medium)
                }
                
                // Duration
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(run.formattedDuration)
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.medium)
                }
                
                // Pace
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(userPreferences.formatPace(run.averagePace))/\(userPreferences.distanceUnit.displayName.dropLast())")
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // Date
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundColor(.purple)
                        .font(.caption)
                    Text("\(run.date.formatted(.dateTime.month(.abbreviated).day())), \(run.date.formatted(.dateTime.year()))")
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.medium)
                }
                
                // Weather
                if let weather = run.weatherData {
                    HStack(spacing: 4) {
                        Text(weatherEmoji(for: weather.condition))
                            .font(.caption)
                        Text(UserPreferences.shared.formatTemperature(weather.temperature))
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 20)
        }
    }
    
    /// Determines if we should show the power song section
    private var shouldShowPowerSongSection: Bool {
        // Show if we already have a power song
        if run.powerSong != nil {
            return true
        }
        
        // Show if we have the data needed to calculate a power song
        let hasRouteData = !run.routeCoordinates.isEmpty
        let hasSongData = run.spotifyTracks?.isEmpty == false
        
        return hasRouteData && hasSongData
    }
    
    private var powerSongSection: some View {
        Group {
            // Show Spotify connection prompt for power songs when missing music data
            if !spotifyService.isAuthenticated && !run.routeCoordinates.isEmpty && (run.spotifyTracks?.isEmpty != false) {
                SpotifyConnectionBanner(context: .powerSong)
            }
            
            // Show power song section if we have a power song OR if we have data to calculate one
            if shouldShowPowerSongSection {
                if let powerSong = run.powerSong {
                    // Existing power song display
                VStack(alignment: .leading, spacing: 16) {
                    Text("power song")
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("🔥")
                                .font(.system(size: 18))
                            
                            Text("power song")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(powerSong.name)
                                    .font(.custom("Helvetica Neue", size: 14))
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(powerSong.artist)
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if let pace = run.powerSongPacePerMile {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(pace)
                                        .font(.custom("Helvetica Neue", size: 14))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                    
                                    Text("per mile")
                                        .font(.custom("Helvetica Neue", size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    
                    // Power Song Card Control Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("power song card")
                                .font(.custom("Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Toggle(isOn: Binding(
                                get: { run.portraitSettings.powerSongDisplay?.isVisible ?? false },
                                set: { newValue in
                                    if run.portraitSettings.powerSongDisplay == nil {
                                        // Initialize if toggling on for the first time
                                        if let powerSong = run.powerSong,
                                           let pacePerMile = run.powerSongPacePerMile {
                                            var powerSongDisplay = PowerSongDisplay(
                                                songName: powerSong.name,
                                                artistName: powerSong.artist,
                                                pacePerMile: pacePerMile
                                            )
                                            powerSongDisplay.isVisible = true // Always default to visible
                                            
                                            // Set default position (bottom right, below album art, aligned like watermark)
                                            let cardWidth: CGFloat = 362.0
                                            let cardHeight: CGFloat = 595.5555555555555
                                            powerSongDisplay.offsetX = cardWidth - 50 // Closer to right edge for straight-line appearance
                                            powerSongDisplay.offsetY = cardHeight - 80 // 80px from bottom, below album art
                                            powerSongDisplay.zIndex = 3.0
                                            
                                            run.portraitSettings.powerSongDisplay = powerSongDisplay
                                        }
                                    } else {
                                        run.portraitSettings.powerSongDisplay?.isVisible = newValue
                                        
                                        // If toggling back on, reset to default position
                                        if newValue == true {
                                            run.portraitSettings.powerSongDisplay?.offsetXPercent = 0.86   // 86% from left (default position)
                                            run.portraitSettings.powerSongDisplay?.offsetYPercent = 0.92   // 92% from top (default position)
                                            run.portraitSettings.powerSongDisplay?.scale = 1.0
                                            run.portraitSettings.powerSongDisplay?.rotation = .zero
                                        }
                                    }
                                    
                                    // Note: Using hasActualUnsavedChanges() for proper change detection
                                }
                            )) {
                                Text(run.portraitSettings.powerSongDisplay?.isVisible == true ? "show on card" : "hide from card")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.primary)
                            }
                            .toggleStyle(.switch)
                        }
                        .padding(.horizontal, 20)
                        
                        if run.portraitSettings.powerSongDisplay?.isVisible == true {
                            Text("your power song will appear as a draggable card on your run card. drag and resize to position it wherever you want!")
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                }
                } else {
                    // No power song calculated but we have data to calculate one
                    VStack(alignment: .leading, spacing: 16) {
                        Text("power song")
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("this run has route and music data needed to calculate a power song")
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                            
                            Button(action: {
                                calculatePowerSongManually()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("get power song")
                                        .font(.custom("Helvetica Neue", size: 16))
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
    }
    
    private var locationSection: some View {
        Group {
            if let smartLocation = run.smartLocationDisplay {
                VStack(alignment: .leading, spacing: 8) {
                    Text("location")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text(smartLocation)
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        // Show analysis type if available (more compact)
                        if let analysis = run.locationAnalysis {
                            Text("• \(analysisTypeDescription(analysis.type))")
                                .font(.custom("Helvetica Neue", size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var resetButtonSection: some View {
        VStack(spacing: 16) {
            // Removed "reset customizations" text as requested
            
            Button(action: {
                resetAllCustomizations()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("reset to defaults")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.red.opacity(0.8), Color.pink.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }
    
    
    // Layout switching removed - portrait only now
    
    // MARK: - Layout-Specific Settings Helpers
    
    private var currentLayoutSettings: LayoutSpecificSettings {
        return run.portraitSettings
    }
    
    private var showCityBinding: Binding<Bool> {
        Binding(
            get: { currentLayoutSettings.showCity ?? userPreferences.showCityByDefault },
            set: { newValue in
                run.portraitSettings.showCity = newValue
                run.markAsChanged(layout: currentLayoutType)
            }
        )
    }
    
    private var showSongsBinding: Binding<Bool> {
        Binding(
            get: { currentLayoutSettings.showSongs ?? userPreferences.showSongsByDefault },
            set: { newValue in
                run.portraitSettings.showSongs = newValue
                run.markAsChanged(layout: currentLayoutType)
            }
        )
    }
    
    
    private func setCurrentLayoutBackgroundPhoto(_ photo: RunPhotoBackground?) {
        run.portraitSettings.backgroundPhoto = photo
        run.markAsChanged(layout: currentLayoutType)
    }
    
    private func generateShareableImage(for layoutType: ShareableCardLayoutType? = nil) {
        // Use the same improved screenshot method that captures exact user view
        let exactCardView = InteractiveShareableCardView(
            run: $run,
            layoutType: currentLayoutType,
            fontFamily: selectedFont,
            showDate: showDate,
            showTime: showTime,
            showPace: showPace,
            showTemperature: showTemperature
        ) { _ in
            // No transform callback needed for screenshot
        }
        .aspectRatio(currentLayoutType.aspectRatio, contentMode: .fit)
        .frame(width: 1080, height: 1920) // Instagram Stories dimensions
        
        // Use ImageRenderer to capture the view exactly as rendered
        let renderer = ImageRenderer(content: exactCardView)
        renderer.scale = UIScreen.main.scale // Use device's native scale for crisp images
        
        print("📸 Sharing card screenshot: \(1080)x\(1920) @ \(renderer.scale)x scale")
        
        if let image = renderer.uiImage {
            print("✅ Share screenshot captured successfully: \(image.size.width)x\(image.size.height)")
            renderedImage = image
            showShareSheet = true
        } else {
            print("❌ Failed to capture share screenshot")
        }
    }
    
    
    
    
    
    
    private func loadPhotosForRun() {
        Task {
            // Request permission if not determined
            if photoService.authorizationStatus == .notDetermined {
                let granted = await photoService.requestPhotoLibraryAccess()
                if !granted {
                    await MainActor.run {
                        self.isLoadingPhotos = false
                    }
                    return
                }
            }
            
            guard photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited else {
                await MainActor.run {
                    self.isLoadingPhotos = false
                }
                return
            }
            
            await MainActor.run {
                self.isLoadingPhotos = true
            }
            
            let photos = await photoService.fetchPhotosForRun(date: run.date, duration: run.elapsedTime)
            
            await MainActor.run {
                self.availablePhotos = photos
                self.isLoadingPhotos = false
                print("📷 RunDetailView: Loaded \(photos.count) photos for run '\(self.run.name)'")
                print("📷 Run date: \(self.run.date)")
                print("📷 Run duration: \(self.run.elapsedTime) seconds")
                if photos.isEmpty {
                    print("📷 ⚠️ No photos found! Check PhotoService logs above for details.")
                }
            }
            
            // Auto-select random photo background if none is set
            await autoSelectPhotoBackground(from: photos)
        }
    }
    
    private func loadSavedPhotoBackground() {
        if let savedBackground = photoService.loadPhotoBackground(for: run.id) {
            // Load saved photo background into portrait settings
            run.portraitSettings.backgroundPhoto = savedBackground
        }
    }
    
    private func loadAlbumArtWhenNeeded() {
        // Check if we have tracks that need album art enrichment
        guard let tracks = run.spotifyTracks, !tracks.isEmpty else {
            print("🎨 LAZY LOADING: No tracks available for album art enrichment")
            return
        }
        
        // First, identify albums that have 3+ tracks (qualify for album art display)
        let albumGroups = Dictionary(grouping: tracks) { track in
            "\(track.album ?? "Unknown")||\(track.artist)"
        }
        
        let qualifyingAlbums = Set(albumGroups.compactMap { (key, tracks) in
            tracks.count >= 3 ? key : nil
        })
        
        // Only fetch album art for tracks from qualifying albums that need it
        let tracksNeedingArt = tracks.filter { track in
            let albumKey = "\(track.album ?? "Unknown")||\(track.artist)"
            return qualifyingAlbums.contains(albumKey) && 
                   (track.albumImageURL == nil || track.albumImageURL?.isEmpty == true) && 
                   !(track.album?.isEmpty ?? true)
        }
        
        if !tracksNeedingArt.isEmpty {
            print("🎨 LAZY LOADING: Found \(tracksNeedingArt.count) tracks needing album art enrichment (from \(qualifyingAlbums.count) qualifying albums)")
            print("🎨 OPTIMIZATION: Skipping \(tracks.count - tracksNeedingArt.count) tracks from albums with <3 songs")
            Task {
                let enrichedTracks = await spotifyService.enrichTracksWithAlbumArt(tracksNeedingArt)
                await MainActor.run {
                    // Update only the tracks that were enriched (merge back into original track list)
                    var updatedTracks = tracks
                    let enrichedTrackIds = Set(enrichedTracks.map { $0.id })
                    
                    for (index, track) in updatedTracks.enumerated() {
                        if enrichedTrackIds.contains(track.id) {
                            if let enrichedTrack = enrichedTracks.first(where: { $0.id == track.id }) {
                                updatedTracks[index] = enrichedTrack
                            }
                        }
                    }
                    
                    run.spotifyTracks = updatedTracks
                    
                    // Update any existing album art displays with new URLs
                    updateExistingAlbumArtDisplays()
                    
                    // Initialize album art displays if they don't exist (after enrichment)
                    initializeAlbumArtAfterEnrichment()
                    
                    // Save the enriched data to avoid re-enrichment
                    userPreferences.saveRun(run)
                    
                    // Also save to Firebase if authenticated
                    Task {
                        await userPreferences.saveRunToFirebase(run)
                    }
                    
                    print("🎨 LAZY LOADING: Album art enrichment completed, displays updated, and data saved")
                }
            }
        } else {
            print("🎨 LAZY LOADING: All tracks already have album art URLs")
            // Initialize album art displays if they don't exist (already have URLs)
            initializeAlbumArtAfterEnrichment()
        }
    }
    
    private func initializePowerSongDisplayIfNeeded() {
        // Initialize Power Song display if not already set up and Power Song exists
        guard run.portraitSettings.powerSongDisplay == nil,
              let powerSong = run.powerSong,
              let pacePerMile = run.powerSongPacePerMile else {
            return
        }
        
        print("🔥 Initializing Power Song display for '\(powerSong.name)' by \(powerSong.artist)")
        
        let powerSongDisplay = PowerSongDisplay(
            songName: powerSong.name,
            artistName: powerSong.artist,
            pacePerMile: pacePerMile
        )
        
        // DISABLED: Use InteractiveShareableCardView single code path instead
        // This prevents conflicts between initialization paths
        print("🔥 RunDetailView: Power Song creation detected - letting InteractiveShareableCardView handle positioning")
        
        // Just store the basic power song data, let the card view handle positioning
        run.portraitSettings.powerSongDisplay = powerSongDisplay
        // Note: Using hasActualUnsavedChanges() for proper change detection
    }
    
    private func calculatePowerSongManually() {
        print("🔥 Manual Power Song calculation requested for run: \(run.name)")
        
        // Ensure we have the necessary data
        guard !run.routeCoordinates.isEmpty else {
            print("🔥 Manual Power Song: No route data available")
            return
        }
        
        guard let tracks = run.spotifyTracks, !tracks.isEmpty else {
            print("🔥 Manual Power Song: No Spotify tracks available")
            return
        }
        
        Task {
            do {
                guard let activityId = Int(run.id) else {
                    print("🔥 Manual Power Song: Invalid activity ID: \(run.id)")
                    return
                }
                
                let streams = try await StravaService.shared.fetchActivityStreams(id: activityId, types: ["time", "latlng"])
                
                await MainActor.run {
                    // Calculate Power Song using the same logic
                    DataConversionService.shared.calculatePowerSong(for: &run, from: streams)
                    
                    if let powerSong = run.powerSong {
                        let pace = run.powerSongPacePerMile ?? "Unknown"
                        print("🔥 Manual Power Song SUCCESS: '\(powerSong.name)' by \(powerSong.artist) - Pace: \(pace)")
                        
                        // Initialize power song display
                        initializePowerSongDisplayIfNeeded()
                        
                        // Save the Power Song data immediately
                        userPreferences.saveRun(run)
                        
                        // Also save to Firebase if authenticated
                        Task {
                            await userPreferences.saveRunToFirebase(run)
                        }
                    } else {
                        print("🔥 Manual Power Song: No Power Song could be calculated for \(run.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    print("🔥 Manual Power Song ERROR: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func calculatePowerSongIfNeeded() {
        // Only calculate if Power Song is not already calculated
        guard run.powerSong == nil else {
            print("🎵 LAZY POWER SONG: Already calculated for run: \(run.name)")
            return
        }
        
        // Only calculate if we have Spotify tracks
        guard let tracks = run.spotifyTracks, !tracks.isEmpty else {
            print("🎵 LAZY POWER SONG: No Spotify tracks available for run: \(run.name)")
            return
        }
        
        // Limit to recent runs or user-opened runs (more generous than the 7-day limit in RunHistoryView)
        let runAge = Date().timeIntervalSince(run.date)
        let maxAgeForOnDemand = 30 * 24 * 60 * 60.0 // 30 days in seconds (more generous for on-demand)
        
        guard runAge <= maxAgeForOnDemand else {
            print("🎵 LAZY POWER SONG: Run too old for on-demand calculation: \(run.name)")
            return
        }
        
        print("🎵 LAZY POWER SONG: Starting calculation for run: \(run.name)")
        
        Task {
            do {
                guard let activityId = Int(run.id) else {
                    print("🎵 LAZY POWER SONG: Invalid activity ID: \(run.id)")
                    return
                }
                
                let streams = try await StravaService.shared.fetchActivityStreams(id: activityId, types: ["time", "latlng"])
                
                await MainActor.run {
                    // Calculate Power Song using the same logic as RunHistoryView
                    DataConversionService.shared.calculatePowerSong(for: &run, from: streams)
                    
                    if let powerSong = run.powerSong {
                        let pace = run.powerSongPacePerMile ?? "Unknown"
                        print("🎵 LAZY POWER SONG SUCCESS: '\(powerSong.name)' by \(powerSong.artist) - Pace: \(pace)")
                        
                        // Save the Power Song data immediately for persistence
                        userPreferences.saveRun(run)
                        
                        // Also save to Firebase if authenticated
                        Task {
                            await userPreferences.saveRunToFirebase(run)
                        }
                    } else {
                        print("🎵 LAZY POWER SONG: No Power Song calculated for \(run.name)")
                    }
                }
                
            } catch {
                print("🎵 LAZY POWER SONG ERROR: Failed to fetch streams for \(run.name): \(error)")
            }
        }
    }
    
    private func updateExistingAlbumArtDisplays() {
        // Update portrait album art displays if they exist
        if var albumArtDisplays = run.portraitSettings.albumArtDisplays {
            var updated = false
            
            for i in 0..<albumArtDisplays.count {
                let display = albumArtDisplays[i]
                
                // Find a track from this album that now has an image URL
                if let trackWithURL = run.spotifyTracks?.first(where: { track in
                    track.album == display.albumName && 
                    track.artist == display.artistName &&
                    track.albumImageURL != nil && 
                    !(track.albumImageURL?.isEmpty ?? true)
                }) {
                    // Update the display with the new URL while preserving all other properties
                    var updatedDisplay = AlbumArtDisplay(id: display.id, albumName: display.albumName, artistName: display.artistName, imageURL: trackWithURL.albumImageURL)
                    // Preserve all positioning and visibility settings
                    updatedDisplay.offsetX = display.offsetX
                    updatedDisplay.offsetY = display.offsetY
                    updatedDisplay.scale = display.scale
                    updatedDisplay.rotationDegrees = display.rotationDegrees
                    updatedDisplay.zIndex = display.zIndex
                    updatedDisplay.isVisible = display.isVisible
                    
                    albumArtDisplays[i] = updatedDisplay
                    updated = true
                    print("🎨 LAZY LOADING: Updated album art display for '\(display.albumName)' with new URL: \(trackWithURL.albumImageURL ?? "nil")")
                }
            }
            
            if updated {
                run.portraitSettings.albumArtDisplays = albumArtDisplays
            }
        }
    }
    
    private func initializeAlbumArtAfterEnrichment() {
        print("🎨 ALBUM ART DEBUG: initializeAlbumArtAfterEnrichment() called")
        print("🎨 ALBUM ART DEBUG: Current albumArtDisplays: \(run.portraitSettings.albumArtDisplays?.count ?? 0) displays")
        print("🎨 ALBUM ART DEBUG: Available album art count: \(run.availableAlbumArt.count)")
        
        // First, validate existing album art displays against current 3+ song requirement
        if let existingDisplays = run.portraitSettings.albumArtDisplays {
            let currentlyAvailable = Set(run.availableAlbumArt.map { $0.albumName })
            let existingAlbumNames = Set(existingDisplays.map { $0.albumName })
            
            // Check if any existing displays are no longer valid
            let invalidDisplays = existingAlbumNames.subtracting(currentlyAvailable)
            if !invalidDisplays.isEmpty {
                print("🎨 VALIDATION: Found invalid cached album art displays: \(invalidDisplays)")
                print("🎨 VALIDATION: Clearing cached displays to regenerate with 3+ song requirement")
                run.portraitSettings.albumArtDisplays = nil
            } else {
                print("🎨 VALIDATION: All existing album art displays are still valid")
                return // Keep existing displays
            }
        }
        
        // Initialize album art displays if they don't exist, but only after enrichment
        // This ensures we have URLs when creating the displays
        if run.portraitSettings.albumArtDisplays == nil {
            print("🎨 POST-ENRICHMENT INIT: Initializing album art displays with enriched URLs")
            
            // Debug album grouping
            if let tracks = run.spotifyTracks {
                print("🎨 POST-ENRICHMENT DEBUG: Analyzing \(tracks.count) tracks for album art")
                let albumGroups = Dictionary(grouping: tracks) { track in
                    "\(track.album ?? "Unknown Album")|\(track.artist)"
                }
                
                for (albumKey, albumTracks) in albumGroups {
                    let components = albumKey.components(separatedBy: "|")
                    let albumName = components.first ?? "Unknown Album"
                    let artistName = components.count > 1 ? components[1] : "Unknown Artist"
                    print("🎨   Album: '\(albumName)' by '\(artistName)' - \(albumTracks.count) tracks")
                    if albumTracks.count >= 3 {
                        print("🎨   ✅ Qualifies for album art (3+ tracks)")
                    } else {
                        print("🎨   ❌ Does not qualify (needs 3+ tracks, has \(albumTracks.count))")
                    }
                }
            }
            
            let availableAlbumArt = run.availableAlbumArt
            print("🎨 POST-ENRICHMENT DEBUG: Found \(availableAlbumArt.count) available album art displays")
            
            if let firstAlbum = availableAlbumArt.first {
                print("🎨 POST-ENRICHMENT INIT: First album art - Name: '\(firstAlbum.albumName)' - URL: '\(firstAlbum.imageURL ?? "nil")'")
                
                let cardWidth: CGFloat = 362.0  // Standard portrait width
                let cardHeight: CGFloat = 595.5555555555555  // Standard portrait height
                
                var defaultAlbumArt = firstAlbum
                defaultAlbumArt.isVisible = true
                
                // Position at bottom-right with 80px margin from edges
                let position = CGPoint(
                    x: cardWidth - 80,
                    y: cardHeight - 80
                )
                defaultAlbumArt.offsetX = position.x
                defaultAlbumArt.offsetY = position.y
                defaultAlbumArt.scale = 0.8
                defaultAlbumArt.zIndex = 2.0
                
                run.portraitSettings.albumArtDisplays = [defaultAlbumArt]
                print("🎨 POST-ENRICHMENT INIT: Initialized album art display with URL: '\(defaultAlbumArt.imageURL ?? "nil")' at position (\(position.x), \(position.y))")
            } else {
                print("🎨 POST-ENRICHMENT INIT: No available album art found - this means no album has 3+ tracks")
            }
        }
    }
    
    private func autoSelectPhotoBackground(from photos: [PHAsset]) async {
        // Only auto-select if no background is already set
        guard run.portraitSettings.backgroundPhoto == nil else {
            print("📷 Background already set - skipping auto-selection")
            return
        }
        
        guard !photos.isEmpty else {
            print("📷 No photos available for auto-selection")
            return
        }
        
        // Select a random non-screenshot photo
        guard let selectedAsset = photoService.selectRandomNonScreenshotPhoto(from: photos) else {
            print("📷 No suitable photos for auto-background selection")
            return
        }
        
        print("📷 Auto-selecting photo background from \(photos.count) available photos")
        
        // Create photo background with default blur filter
        if let photoBackground = await photoService.createPhotoBackground(
            from: selectedAsset,
            filterType: .blur,
            opacity: 0.6
        ) {
            await MainActor.run {
                self.run.portraitSettings.backgroundPhoto = photoBackground
                print("✅ Auto-selected photo background for run")
                
                // Save the background
                self.photoService.savePhotoBackground(photoBackground, for: self.run.id)
            }
        }
    }
    
    
    // MARK: - Album Art Helpers
    
    private func getAvailableAlbumArt(from tracks: [SpotifyTrack]) -> [AlbumArtDisplay] {
        // Group tracks by album using a custom key structure
        struct AlbumKey: Hashable {
            let albumName: String
            let artistName: String
        }
        
        let albumGroups = Dictionary(grouping: tracks) { track in
            AlbumKey(
                albumName: track.album ?? "Unknown Album",
                artistName: track.artist
            )
        }
        
        // Only include albums with 3+ songs
        return albumGroups.compactMap { (albumKey, albumTracks) in
            guard albumTracks.count >= 3 else { return nil }
            
            let imageURL = albumTracks.first?.albumImageURL
            
            return AlbumArtDisplay(
                albumName: albumKey.albumName,
                artistName: albumKey.artistName,
                imageURL: imageURL
            )
        }.sorted { $0.albumName < $1.albumName }
    }
    
    private func getAlbumTrackCount(_ albumName: String, from tracks: [SpotifyTrack]) -> Int {
        return tracks.filter { $0.album == albumName }.count
    }
    
    // MARK: - Percentage-based positioning helpers
    
    private func percentagePosition(x: Double, y: Double, cardWidth: CGFloat, cardHeight: CGFloat) -> (x: CGFloat, y: CGFloat) {
        return (
            x: CGFloat(x / 100.0) * cardWidth,
            y: CGFloat(y / 100.0) * cardHeight
        )
    }
    
    private func initializeDefaultAlbumArt() {
        print("🎨 INITIALIZATION DEBUG - Starting initializeDefaultAlbumArt()")
        
        // Only initialize if we don't already have album art displays set up
        let availableAlbums = run.availableAlbumArt
        print("🎨 INITIALIZATION DEBUG - Available albums count: \(availableAlbums.count)")
        for (index, album) in availableAlbums.enumerated() {
            print("🎨 INITIALIZATION DEBUG - Available album \(index): \(album.albumName) by \(album.artistName)")
        }
        
        guard !availableAlbums.isEmpty else { 
            print("🎨 INITIALIZATION DEBUG - ❌ No available album art to initialize")
            return 
        }
        
        print("🎨 INITIALIZATION DEBUG - ✅ Found \(availableAlbums.count) available albums, proceeding with initialization")
        
        // Initialize portrait layout album art only
        print("🎨 INITIALIZATION DEBUG - Checking portrait layout")
        let currentDisplays = run.portraitSettings.albumArtDisplays
        print("🎨 INITIALIZATION DEBUG - Current displays for portrait: \(currentDisplays?.count ?? 0) items")
        print("🎨 INITIALIZATION DEBUG - Current displays nil check: \(currentDisplays == nil ? "NIL" : "NOT NIL")")
        
        // If no album art displays exist, initialize with first available album (up to 1 by default)
        if currentDisplays == nil || currentDisplays?.isEmpty == true {
            print("🎨 INITIALIZATION DEBUG - ✅ Need to initialize portrait - creating new album art")
            var defaultAlbumArt = availableAlbums.first!
            defaultAlbumArt.isVisible = true
            
            // Use actual card dimensions from logs: 362x595 for portrait
            // Lower right positioning: 70% right, 65% down for bottom right corner
            let cardWidth: CGFloat = 362
            let cardHeight: CGFloat = 595
            let pos = percentagePosition(x: 70, y: 65, cardWidth: cardWidth, cardHeight: cardHeight)
            defaultAlbumArt.offsetX = pos.x
            defaultAlbumArt.offsetY = pos.y
            print("🎨 PERCENTAGE: Portrait album art positioned at \(pos.x), \(pos.y) (70%, 65%) on card \(cardWidth)x\(cardHeight)")
            
            defaultAlbumArt.scale = 0.8  // 80% of original size (20% smaller)
            
            run.portraitSettings.albumArtDisplays = [defaultAlbumArt]
            
            print("🎨 Initialized default album art for portrait: \(defaultAlbumArt.albumName) with ID: \(defaultAlbumArt.id)")
        } else {
            print("🎨 Album art displays already exist for portrait: \(currentDisplays?.count ?? 0) items")
            // Debug existing album art positions and fix if they're using old coordinates
            if let displays = currentDisplays {
                var needsUpdate = false
                for (index, display) in displays.enumerated() {
                    print("🎨 Existing album art \(index): \(display.albumName) - Position: (\(display.offsetX), \(display.offsetY)), Scale: \(display.scale), Visible: \(display.isVisible)")
                    
                    // Check if album art needs updating to new lower right positioning
                    // New lower right should be around 253,386 for portrait (70% of 362, 65% of 595)
                    let expectedPortraitX: CGFloat = 253 // 70% of 362
                    let expectedPortraitY: CGFloat = 386 // 65% of 595
                    let tolerance: CGFloat = 30 // Reduced tolerance to catch more positions
                    
                    let isOldPosition = (abs(display.offsetX - expectedPortraitX) > tolerance || 
                                       abs(display.offsetY - expectedPortraitY) > tolerance)
                    
                    if isOldPosition {
                        print("🎨 ⚠️ Found album art with old positioning! Updating to new coordinates...")
                        needsUpdate = true
                    }
                }
                
                // Update positions if needed
                if needsUpdate {
                    var updatedDisplays = displays
                    for i in 0..<updatedDisplays.count {
                        // Use same logic as new initialization
                        let row = i / 2
                        let col = i % 2
                        
                        // Use actual card dimensions and lower right positioning
                        let cardWidth: CGFloat = 362
                        let cardHeight: CGFloat = 595
                        let basePos = percentagePosition(x: 70, y: 65, cardWidth: cardWidth, cardHeight: cardHeight)
                        updatedDisplays[i].offsetX = basePos.x + CGFloat(col * 30)
                        updatedDisplays[i].offsetY = basePos.y + CGFloat(row * 30)
                        
                        updatedDisplays[i].scale = 0.8
                        updatedDisplays[i].isVisible = true // CRITICAL: Ensure album art is visible after position update
                        print("🎨 ✅ Updated album art \(i) to position: (\(updatedDisplays[i].offsetX), \(updatedDisplays[i].offsetY)), visible: \(updatedDisplays[i].isVisible)")
                    }
                    
                    // Apply the updates
                    run.portraitSettings.albumArtDisplays = updatedDisplays
                }
            }
        }
    }
    
    
    // MARK: - Export Screenshot
    
    private func exportCardScreenshot() {
        // Create the exact card view that matches what user sees on screen
        let exactCardView = InteractiveShareableCardView(
            run: $run,
            layoutType: currentLayoutType,
            fontFamily: selectedFont,
            showDate: showDate,
            showTime: showTime,
            showPace: showPace,
            showTemperature: showTemperature
        ) { _ in
            // No transform callback needed for screenshot
        }
        .aspectRatio(currentLayoutType.aspectRatio, contentMode: .fit)
        .frame(width: 1080, height: 1920) // Instagram Stories dimensions
        
        // Use ImageRenderer to capture the view exactly as rendered
        let renderer = ImageRenderer(content: exactCardView)
        renderer.scale = UIScreen.main.scale // Use device's native scale for crisp images
        
        print("📸 Capturing screenshot of card: \(1080)x\(1920) @ \(renderer.scale)x scale")
        
        if let image = renderer.uiImage {
            print("✅ Screenshot captured successfully: \(image.size.width)x\(image.size.height)")
            exportedScreenshot = image
            showExportSheet = true
        } else {
            print("❌ Failed to capture screenshot")
        }
    }
    
    // MARK: - Navigation
    
    private func handleBackNavigation() {
        if hasActualUnsavedChanges() {
            showUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }
    
    private func hasActualUnsavedChanges() -> Bool {
        guard let original = originalRunSettings else { return false }
        let current = run.portraitSettings
        
        // Compare each setting to detect actual changes
        if original.showCity != current.showCity { return true }
        if original.showSongs != current.showSongs { return true }
        if original.colorScheme?.id != current.colorScheme?.id { return true }
        if original.fontFamily?.id != current.fontFamily?.id { return true }
        
        // Compare background photo
        if original.backgroundPhoto?.photoId != current.backgroundPhoto?.photoId { return true }
        if original.backgroundPhoto?.filterType != current.backgroundPhoto?.filterType { return true }
        if original.backgroundPhoto?.opacity != current.backgroundPhoto?.opacity { return true }
        
        // Compare album art displays (count and visibility)
        let originalAlbumArts = original.albumArtDisplays ?? []
        let currentAlbumArts = current.albumArtDisplays ?? []
        let originalVisible = originalAlbumArts.filter { $0.isVisible }
        let currentVisible = currentAlbumArts.filter { $0.isVisible }
        if originalVisible.count != currentVisible.count { return true }
        for (orig, curr) in zip(originalVisible.sorted { $0.albumName < $1.albumName }, 
                               currentVisible.sorted { $0.albumName < $1.albumName }) {
            if orig.albumName != curr.albumName || orig.isVisible != curr.isVisible { return true }
        }
        
        // Compare power song display
        if original.powerSongDisplay?.isVisible != current.powerSongDisplay?.isVisible { return true }
        
        return false
    }
    
    // MARK: - Sign-In Prompts
    
    private func handleSaveAction() {
        if firebaseAuth.isAuthenticated {
            saveRunEdits()
        } else {
            // Check if this is first customization or user has multiple runs
            // let context: SignInContext = hasSignificantCustomizations() ? .savingRun : .firstCustomization
            pendingSaveAction = { saveRunEdits() }
            showSignInPrompt = true
        }
    }
    
    private func handleShareAction(for layout: ShareableCardLayoutType) {
        if firebaseAuth.isAuthenticated {
            generateShareableImage(for: layout)
        } else if hasSignificantCustomizations() {
            pendingSaveAction = { generateShareableImage(for: layout) }
            showSignInPrompt = true
        } else {
            generateShareableImage(for: layout)
        }
    }
    
    private func hasSignificantCustomizations() -> Bool {
        // Check if user has made meaningful customizations worth saving (portrait only)
        return run.portraitSettings.colorScheme != nil ||
               run.portraitSettings.backgroundPhoto != nil ||
               run.portraitSettings.showCity != nil ||
               run.portraitSettings.showSongs != nil
    }
    
    private func executeWithCloudSync(_ action: @escaping () -> Void) {
        action()
        if firebaseAuth.isAuthenticated {
            Task {
                await userPreferences.saveRunToFirebase(run)
            }
        }
    }
    
    private func isAlbumArtSelected(_ albumArt: AlbumArtDisplay) -> Bool {
        guard let displays = run.portraitSettings.albumArtDisplays else { return false }
        return displays.contains { display in
            display.albumName == albumArt.albumName && 
            display.artistName == albumArt.artistName && 
            display.isVisible
        }
    }
    
    private func toggleAlbumArtVisibility(_ albumArt: AlbumArtDisplay) {
        // Get the portrait settings (simplified for portrait-only)
        let settings = run.portraitSettings
        
        // Initialize album art displays if nil
        if settings.albumArtDisplays == nil {
            run.portraitSettings.albumArtDisplays = []
        }
        
        // Check if album art is already in the list (match by album name and artist, not ID)
        if let existingIndex = settings.albumArtDisplays?.firstIndex(where: { $0.albumName == albumArt.albumName && $0.artistName == albumArt.artistName }) {
            // Toggle visibility
            run.portraitSettings.albumArtDisplays?[existingIndex].isVisible.toggle()
        } else {
            // Add new album art with default visibility and position
            var newAlbumArt = albumArt
            newAlbumArt.isVisible = true
            
            // Position based on how many are already visible (max 4)
            let visibleCount = settings.albumArtDisplays?.filter { $0.isVisible }.count ?? 0
            
            if visibleCount < 4 {
                // Position them in lower right within card bounds (80% size as requested)
                let row = visibleCount / 2
                let col = visibleCount % 2
                
                // Lower right positioning using actual card dimensions (portrait only)
                let cardWidth: CGFloat = 362
                let cardHeight: CGFloat = 595
                let basePos = percentagePosition(x: 70, y: 65, cardWidth: cardWidth, cardHeight: cardHeight)
                newAlbumArt.offsetX = basePos.x + CGFloat(col * 30)
                newAlbumArt.offsetY = basePos.y + CGFloat(row * 30)
                newAlbumArt.scale = 0.8 // 80% of original size (20% smaller)
            }
            
            run.portraitSettings.albumArtDisplays?.append(newAlbumArt)
        }
        
        // Force UI update by triggering a state change
        albumArtUpdateTrigger = UUID()
        
        // Mark as changed
        run.markAsChanged(layout: currentLayoutType)
    }
    
    private func saveRunEdits() {
        // Mark current layout as saved
        run.markAsSaved(layout: currentLayoutType)
        
        // Save the current state of the run
        userPreferences.saveRun(run)
        
        // Save to Firebase if authenticated
        if firebaseAuth.isAuthenticated {
            Task {
                await userPreferences.saveRunToFirebase(run)
            }
        }
        
        // Show save confirmation
        let alert = UIAlertController(
            title: "Saved",
            message: firebaseAuth.isAuthenticated ? 
                "Your \(currentLayoutType.displayName) layout has been saved to the cloud." :
                "Your \(currentLayoutType.displayName) layout has been saved locally.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            // Dismiss the view after user acknowledges the save
            DispatchQueue.main.async {
                self.dismiss()
            }
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Photo Permission Prompt View
    
    private var photoPermissionPromptView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("Photo Access Needed")
                        .font(.custom("Helvetica Neue", size: 20))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Run The Tunes needs access to your photo library to add photo backgrounds to your run cards.")
                        .font(.custom("Helvetica Neue", size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            
            VStack(spacing: 12) {
                if photoService.authorizationStatus == .notDetermined {
                    Button(action: requestPhotoPermission) {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text("Allow Photo Access")
                        }
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                } else if photoService.authorizationStatus == .denied {
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    
                    Button(action: {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }) {
                        Text("photo access was previously denied. please enable it in settings > run the tunes > photos.")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.blue)
                            .underline()
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                } else if photoService.authorizationStatus == .restricted {
                    VStack(spacing: 8) {
                        Text("Photo Access Restricted")
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        
                        Text("Photo access is restricted on this device. Contact your device administrator for assistance.")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else if photoService.authorizationStatus == .limited {
                    VStack(spacing: 12) {
                        Text("Limited Photo Access")
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        Text("You've granted limited photo access. You can still add photo backgrounds, but only from selected photos.")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Button(action: requestFullPhotoAccess) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Allow Full Access")
                            }
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    private func requestPhotoPermission() {
        Task {
            let granted = await photoService.requestPhotoLibraryAccess()
            await MainActor.run {
                if granted {
                    loadPhotosForRun()
                }
            }
        }
    }
    
    private func requestFullPhotoAccess() {
        Task {
            let granted = await photoService.requestPhotoLibraryAccess()
            await MainActor.run {
                if granted {
                    loadPhotosForRun()
                }
            }
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private func analysisTypeDescription(_ type: RunLocationType) -> String {
        switch type {
        case .singleLocation:
            return "Single location"
        case .neighborhoodInCity:
            return "Neighborhood run"  // Simplified as requested
        case .multiCity:
            return "Multi-city route"
        case .complexRoute:
            return "Complex route"
        }
    }
}

struct CompactSongSelectionRow: View {
    let track: SpotifyTrack
    let index: Int
    @Binding var isVisible: Bool
    
    var body: some View {
        Button(action: {
            isVisible.toggle()
        }) {
            HStack(spacing: 8) {
                // Checkbox
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isVisible ? .green : .secondary)
                
                // Song info (compact)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.custom("Helvetica Neue", size: 13))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Duration
                Text(track.formattedDuration)
                    .font(.custom("Helvetica Neue", size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isVisible ? Color.green.opacity(0.05) : Color.clear)
            .cornerRadius(6)
            .opacity(isVisible ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
    }
}

struct DetailStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private func weatherEmoji(for condition: WeatherData.WeatherCondition) -> String {
    switch condition {
    case .clear: return "☀️"
    case .cloudy: return "☁️"
    case .rain: return "🌧️"
    case .snow: return "❄️"
    case .fog: return "🌫️"
    case .thunderstorm: return "⛈️"
    case .unknown: return "🌤️"
    }
}

#Preview {
    let sampleRun = RunActivity(
        id: "1",
        name: "Morning Run",
        date: Date(),
        distance: 5000,
        elapsedTime: 1800,
        averagePace: 360,
        startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        routeCoordinates: [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Mission District"
    )
    
    RunDetailView(run: sampleRun)
}

struct AdvancedShareView: View {
    @Binding var run: RunActivity
    let currentLayout: ShareableCardLayoutType
    let showDate: Bool
    let showTime: Bool
    let showPace: Bool
    let showTemperature: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Share Portrait Card")
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.top, 20)
                    
                    // Portrait option only
                    VStack(spacing: 12) {
                        Button(action: {
                            generateAndShare(layout: .portrait)
                        }) {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                                    .aspectRatio(9.0/16.0, contentMode: .fit)
                                    .overlay(
                                        VStack {
                                            Image(systemName: "rectangle.portrait")
                                                .font(.system(size: 24))
                                                .foregroundColor(.blue)
                                            Text("1080×1920")
                                                .font(.custom("Helvetica Neue", size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 2)
                                    )
                                
                                Text("Portrait (Instagram Stories)")
                                    .font(.custom("Helvetica Neue", size: 14))
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("Perfect for Instagram Stories\nand mobile sharing")
                                    .font(.custom("Helvetica Neue", size: 11))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    
                    Text("Uses your saved settings including colors, songs, and background photo.")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheetView(activityItems: [image])
            }
        }
    }
    
    private func generateAndShare(layout: ShareableCardLayoutType) {
        let dimensions = layout.dimensions
        let width: CGFloat = dimensions.width
        let height: CGFloat = dimensions.height
        
        // Create a view controller to host our SwiftUI view
        let hostingController = UIHostingController(
            rootView: InteractiveShareableCardView(
                run: $run, 
                layoutType: layout,
                fontFamily: nil,
                showDate: self.showDate,
                showTime: self.showTime,
                showPace: self.showPace,
                showTemperature: self.showTemperature
            ) { _ in }
                .frame(width: width, height: height)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        
        hostingController.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        hostingController.view.backgroundColor = UIColor.clear
        
        // Create snapshot
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: width, height: height))
        let image = renderer.image { ctx in
            hostingController.view.layer.render(in: ctx.cgContext)
        }
        
        shareImage = image
        showShareSheet = true
    }
}

// MARK: - Album Art Selection Tile

struct AlbumArtSelectionTile: View {
    let albumArt: AlbumArtDisplay
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var imageLoadFailed = false
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 4) {
                // Album art image
                AsyncImage(url: URL(string: albumArt.imageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        Rectangle()
                            .fill(Color.red.opacity(0.2))
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("No Image")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            )
                            .onAppear { imageLoadFailed = true }
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "music.note")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    if albumArt.imageURL == nil {
                                        Text("No URL")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
                
                // Album name - smaller when image fails to de-emphasize text
                Text(albumArt.albumName)
                    .font(imageLoadFailed || albumArt.imageURL == nil ? .caption : .caption2)
                    .lineLimit(1) // Single line to reduce prominence
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundColor(imageLoadFailed || albumArt.imageURL == nil ? .secondary : .primary)
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .frame(width: 80, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
