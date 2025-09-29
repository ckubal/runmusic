import Foundation
import SwiftUI
import FirebaseAuth

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    @Published var distanceUnit: DistanceUnit {
        didSet {
            UserDefaults.standard.set(distanceUnit.rawValue, forKey: "distanceUnit")
        }
    }
    
    @Published var showCityByDefault: Bool {
        didSet {
            UserDefaults.standard.set(showCityByDefault, forKey: "showCityByDefault")
        }
    }
    
    @Published var showSongsByDefault: Bool {
        didSet {
            UserDefaults.standard.set(showSongsByDefault, forKey: "showSongsByDefault")
        }
    }
    
    @Published var defaultColorScheme: RunColorScheme {
        didSet {
            if let data = try? JSONEncoder().encode(defaultColorScheme) {
                UserDefaults.standard.set(data, forKey: "defaultColorScheme")
            }
        }
    }
    
    @Published var defaultFontFamily: FontFamily {
        didSet {
            if let data = try? JSONEncoder().encode(defaultFontFamily) {
                UserDefaults.standard.set(data, forKey: "defaultFontFamily")
            }
        }
    }
    
    @Published var pushNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pushNotificationsEnabled, forKey: "pushNotificationsEnabled")
        }
    }
    
    @Published var temperatureUnit: TemperatureUnit {
        didSet {
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: "temperatureUnit")
        }
    }
    
    enum TemperatureUnit: String, CaseIterable {
        case fahrenheit = "fahrenheit"
        case celsius = "celsius"
        
        var displayName: String {
            switch self {
            case .fahrenheit: return "fahrenheit"
            case .celsius: return "celsius"
            }
        }
        
        var symbol: String {
            switch self {
            case .fahrenheit: return "°F"
            case .celsius: return "°C"
            }
        }
    }
    
    enum DistanceUnit: String, CaseIterable {
        case miles = "miles"
        case kilometers = "kilometers"
        
        var displayName: String {
            switch self {
            case .miles: return "miles"
            case .kilometers: return "kilometers"
            }
        }
        
        var abbreviation: String {
            switch self {
            case .miles: return "mi"
            case .kilometers: return "km"
            }
        }
    }
    
    private init() {
        self.distanceUnit = DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "miles") ?? .miles
        self.temperatureUnit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: "temperatureUnit") ?? "fahrenheit") ?? .fahrenheit
        self.showCityByDefault = UserDefaults.standard.object(forKey: "showCityByDefault") as? Bool ?? true
        self.showSongsByDefault = UserDefaults.standard.object(forKey: "showSongsByDefault") as? Bool ?? true
        self.pushNotificationsEnabled = UserDefaults.standard.object(forKey: "pushNotificationsEnabled") as? Bool ?? false
        
        // Load color scheme from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "defaultColorScheme"),
           let colorScheme = try? JSONDecoder().decode(RunColorScheme.self, from: data) {
            self.defaultColorScheme = colorScheme
        } else {
            self.defaultColorScheme = RunColorScheme.default
        }
        
        // Load font family from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "defaultFontFamily"),
           let fontFamily = try? JSONDecoder().decode(FontFamily.self, from: data) {
            self.defaultFontFamily = fontFamily
        } else {
            self.defaultFontFamily = FontFamily.default
        }
    }
    
    func formatDistance(_ meters: Double) -> String {
        switch distanceUnit {
        case .miles:
            let miles = meters / 1609.34
            if miles >= 10 {
                return String(format: "%.1f", miles)
            } else {
                return String(format: "%.2f", miles)
            }
        case .kilometers:
            let km = meters / 1000.0
            if km >= 10 {
                return String(format: "%.1f", km)
            } else {
                return String(format: "%.2f", km)
            }
        }
    }
    
    func formatPace(_ paceInSecondsPerKm: Double) -> String {
        let paceInSeconds: Double
        switch distanceUnit {
        case .miles:
            paceInSeconds = paceInSecondsPerKm * 1.60934
        case .kilometers:
            paceInSeconds = paceInSecondsPerKm
        }
        
        let minutes = Int(paceInSeconds / 60)
        let seconds = Int(paceInSeconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func formatTemperature(_ fahrenheit: Double) -> String {
        switch temperatureUnit {
        case .fahrenheit:
            return String(format: "%.0f°F", fahrenheit)
        case .celsius:
            let celsius = (fahrenheit - 32) * 5 / 9
            return String(format: "%.0f°C", celsius)
        }
    }
    
    // MARK: - Run Saving
    
    func saveRun(_ run: RunActivity) {
        // Create a key for this run's custom settings
        let runKey = "run_\(run.id)"
        
        // Save run-specific customizations
        var runSettings: [String: Any] = [:]
        
        if let showCity = run.showCity {
            runSettings["showCity"] = showCity
        }
        
        if let showSongs = run.showSongs {
            runSettings["showSongs"] = showSongs
        }
        
        // Save Portrait layout settings
        if let portraitData = try? JSONEncoder().encode(run.portraitSettings) {
            runSettings["portraitSettings"] = portraitData
        }
        
        // Landscape settings removed - portrait only now
        
        // Save metadata
        runSettings["lastSaved"] = Date()
        runSettings["version"] = "2.0" // Track layout system version
        
        // Save to UserDefaults
        UserDefaults.standard.set(runSettings, forKey: runKey)
        
        // Also save photo background via PhotoService if needed (from portrait layout for legacy support)
        if let photoBackground = run.portraitSettings.backgroundPhoto {
            PhotoService.shared.savePhotoBackground(photoBackground, for: run.id)
        }
    }
    
    func loadRunSettings(for run: inout RunActivity) {
        let runKey = "run_\(run.id)"
        
        guard let runSettings = UserDefaults.standard.dictionary(forKey: runKey) else { return }
        
        // Load saved settings (legacy support)
        run.showCity = runSettings["showCity"] as? Bool
        run.showSongs = runSettings["showSongs"] as? Bool
        
        // Load Portrait layout settings
        if let portraitData = runSettings["portraitSettings"] as? Data,
           let portraitSettings = try? JSONDecoder().decode(LayoutSpecificSettings.self, from: portraitData) {
            run.portraitSettings = portraitSettings
        }
        
        // Landscape settings removed - portrait only now
        
        // Legacy support for old format
        if let colorData = runSettings["colorScheme"] as? Data,
           let colorScheme = try? JSONDecoder().decode(RunColorScheme.self, from: colorData) {
            run.portraitSettings.colorScheme = colorScheme
        }
        
        if let albumData = runSettings["albumArtDisplays"] as? Data,
           let albumArtDisplays = try? JSONDecoder().decode([AlbumArtDisplay].self, from: albumData) {
            run.portraitSettings.albumArtDisplays = albumArtDisplays
        }
        
        // Load photo background via PhotoService (apply to both layouts for now)
        if let photoBackground = PhotoService.shared.loadPhotoBackground(for: run.id) {
            run.portraitSettings.backgroundPhoto = photoBackground
        }
    }
    
    // MARK: - Firebase Integration
    
    func exportToFirebase() -> FirebaseUserPreferences {
        var prefs = FirebaseUserPreferences()
        prefs.unitSystem = distanceUnit.rawValue
        prefs.preferredExportFormat = "instagram"
        prefs.autoSaveEnabled = true
        prefs.notificationsEnabled = true
        return prefs
    }
    
    func importFromFirebase(_ firebasePrefs: FirebaseUserPreferences) {
        distanceUnit = DistanceUnit(rawValue: firebasePrefs.unitSystem) ?? .miles
    }
    
    func syncToFirebase() async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            let firestoreService = FirestoreService.shared
            let firebasePrefs = exportToFirebase()
            
            if var userProfile = try await firestoreService.getUserProfile(userId: user.uid) {
                userProfile.preferences = firebasePrefs
                userProfile.lastActiveAt = Date()
                try await firestoreService.updateUserProfile(userProfile)
            }
        } catch {
            print("Error syncing preferences to Firebase: \(error)")
        }
    }
    
    func syncFromFirebase() async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            let firestoreService = FirestoreService.shared
            if let userProfile = try await firestoreService.getUserProfile(userId: user.uid) {
                await MainActor.run {
                    importFromFirebase(userProfile.preferences)
                }
            }
        } catch {
            print("Error syncing preferences from Firebase: \(error)")
        }
    }
    
    func saveRunToFirebase(_ run: RunActivity) async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            var customization = RunCustomization()
            customization.colorScheme = run.portraitSettings.colorScheme?.name
            customization.showCity = run.showCity
            customization.showSongs = run.showSongs
            customization.visibleSongs = nil
            customization.photoSettings = nil
            
            customization.portraitSettings = LayoutSettings(
                colorScheme: run.portraitSettings.colorScheme?.name,
                showCity: run.portraitSettings.showCity,
                showSongs: run.portraitSettings.showSongs,
                visibleSongs: nil,
                photoSettings: nil
            )
            
            // Landscape settings removed - portrait only now
            
            customization.updatedAt = Date()
            
            try await FirestoreService.shared.saveRunCustomization(
                userId: user.uid,
                runId: run.id,
                customization: customization
            )
        } catch {
            print("Error saving run to Firebase: \(error)")
        }
    }
}