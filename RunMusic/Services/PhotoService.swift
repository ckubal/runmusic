import Foundation
import UIKit
import Photos
import SwiftUI

class PhotoService: ObservableObject {
    static let shared = PhotoService()
    
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var availablePhotos: [PHAsset] = []
    
    private let imageManager = PHCachingImageManager()
    
    private init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    func requestPhotoLibraryAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        await MainActor.run {
            self.authorizationStatus = status
        }
        
        return status == .authorized || status == .limited
    }
    
    func fetchPhotosForRun(date: Date, duration: TimeInterval) async -> [PHAsset] {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("⚠️ Photo library access not authorized")
            return []
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        print("📷 ========== PHOTO FETCH DEBUG ==========")
        print("📷 Run date: \(dateFormatter.string(from: date))")
        print("📷 Run duration: \(Int(duration/60)) minutes")
        
        // Add timezone debugging for photo search
        let utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        utcFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let pacificFormatter = DateFormatter()
        pacificFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        pacificFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        
        print("📷 PHOTO TIMEZONE DEBUG:")
        print("📷   Run date (UTC): \(utcFormatter.string(from: date))")
        print("📷   Run date (Pacific): \(pacificFormatter.string(from: date))")
        print("📷   System timezone: \(TimeZone.current.identifier)")
        
        var allAssets: [PHAsset] = []
        var seenIdentifiers = Set<String>()  // Track duplicates
        
        // First, try to get photos during run time (prioritized)
        let runStartTime = date.addingTimeInterval(-60 * 60)  // 1 hour before
        let runEndTime = date.addingTimeInterval(duration + 60 * 60)  // 1 hour after
        
        print("📷 Searching for photos between:")
        print("📷   Start: \(dateFormatter.string(from: runStartTime))")
        print("📷   End: \(dateFormatter.string(from: runEndTime))")
        
        let runTimeFetchOptions = PHFetchOptions()
        runTimeFetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType = %d",
            runStartTime as NSDate,
            runEndTime as NSDate,
            PHAssetMediaType.image.rawValue
        )
        runTimeFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let runTimeResult = PHAsset.fetchAssets(with: runTimeFetchOptions)
        runTimeResult.enumerateObjects { asset, _, _ in
            if !seenIdentifiers.contains(asset.localIdentifier) {
                allAssets.append(asset)
                seenIdentifiers.insert(asset.localIdentifier)
                if let creationDate = asset.creationDate {
                    print("📷   Found run-time photo: \(dateFormatter.string(from: creationDate))")
                }
            }
        }
        
        print("📷 Found \(allAssets.count) photos during run time")
        
        // If no run-time photos, expand search to wider time range (1 day before/after)
        if allAssets.isEmpty {
            let expandedStartTime = date.addingTimeInterval(-24 * 60 * 60)  // 1 day before
            let expandedEndTime = date.addingTimeInterval(duration + 24 * 60 * 60)  // 1 day after
            
            print("📷 No run-time photos, expanding to 1 day before/after:")
            print("📷   Expanded start: \(dateFormatter.string(from: expandedStartTime))")
            print("📷   Expanded end: \(dateFormatter.string(from: expandedEndTime))")
            
            let expandedFetchOptions = PHFetchOptions()
            expandedFetchOptions.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@ AND mediaType = %d",
                expandedStartTime as NSDate,
                expandedEndTime as NSDate,
                PHAssetMediaType.image.rawValue
            )
            expandedFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            expandedFetchOptions.fetchLimit = 30  // Increased limit for wider search
            
            let expandedResult = PHAsset.fetchAssets(with: expandedFetchOptions)
            expandedResult.enumerateObjects { asset, _, _ in
                if !seenIdentifiers.contains(asset.localIdentifier) {
                    allAssets.append(asset)
                    seenIdentifiers.insert(asset.localIdentifier)
                    if let creationDate = asset.creationDate {
                        print("📷   Found expanded timeframe photo: \(dateFormatter.string(from: creationDate))")
                    }
                }
            }
            
            print("📷 Found \(allAssets.count) photos in expanded timeframe")
        }
        
        // If still no photos, get recent photos from camera roll
        if allAssets.isEmpty {
            print("📷 No same-day photos, getting recent photos from camera roll")
            
            let recentFetchOptions = PHFetchOptions()
            recentFetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            recentFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            recentFetchOptions.fetchLimit = 50  // Increased to 50 for better selection
            
            let recentResult = PHAsset.fetchAssets(with: recentFetchOptions)
            recentResult.enumerateObjects { asset, _, _ in
                if !seenIdentifiers.contains(asset.localIdentifier) {
                    allAssets.append(asset)
                    seenIdentifiers.insert(asset.localIdentifier)
                    if let creationDate = asset.creationDate {
                        print("📷   Found recent photo: \(dateFormatter.string(from: creationDate))")
                    }
                }
            }
            
            print("📷 Found \(allAssets.count) recent photos from camera roll")
        }
        
        print("📷 Total unique photos: \(allAssets.count)")
        print("📷 =========================================")
        
        await MainActor.run {
            self.availablePhotos = allAssets
        }
        
        return allAssets
    }
    
    func loadImage(from asset: PHAsset, targetSize: CGSize = CGSize(width: 400, height: 400)) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    func createPhotoBackground(
        from asset: PHAsset,
        filterType: RunPhotoBackground.PhotoFilterType = .blur,
        opacity: Double = 0.7
    ) async -> RunPhotoBackground? {
        guard let image = await loadImage(from: asset) else {
            print("❌ Failed to load image from asset")
            return nil
        }
        
        // Compress image for storage
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to data")
            return nil
        }
        
        let photoId = asset.localIdentifier
        
        return RunPhotoBackground(
            photoId: photoId,
            photoData: imageData,
            filterType: filterType,
            opacity: opacity
        )
    }
    
    func isLikelyScreenshot(_ asset: PHAsset) -> Bool {
        // Check if photo dimensions match common screenshot dimensions
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        
        // Common iPhone screenshot dimensions (various models)
        let screenshotDimensions: [(Int, Int)] = [
            (1284, 2778), // iPhone 12/13/14 Pro
            (1170, 2532), // iPhone 12/13/14
            (1125, 2436), // iPhone X/XS/11 Pro
            (828, 1792),  // iPhone XR/11
            (750, 1334),  // iPhone 6/7/8
            (640, 1136),  // iPhone 5/5s/SE
            (2048, 2732), // iPad Pro 12.9"
            (1668, 2388), // iPad Pro 11"
            (1536, 2048), // iPad
        ]
        
        // Check if dimensions match any known screenshot size (or flipped)
        for (screenWidth, screenHeight) in screenshotDimensions {
            if (width == screenWidth && height == screenHeight) ||
               (width == screenHeight && height == screenWidth) {
                return true
            }
        }
        
        // Additional heuristics: very rectangular aspect ratios are often screenshots
        let aspectRatio = Double(max(width, height)) / Double(min(width, height))
        if aspectRatio > 2.5 { // Very tall/wide ratio suggests screenshot
            return true
        }
        
        return false
    }
    
    func selectRandomNonScreenshotPhoto(from assets: [PHAsset]) -> PHAsset? {
        let nonScreenshots = assets.filter { !isLikelyScreenshot($0) }
        
        print("📷 Filtered out \(assets.count - nonScreenshots.count) likely screenshots")
        print("📷 \(nonScreenshots.count) potential background photos available")
        
        guard !nonScreenshots.isEmpty else {
            print("📷 No non-screenshot photos available")
            return nil
        }
        
        // Return a random photo from the non-screenshot photos
        return nonScreenshots.randomElement()
    }
    
    func createPhotoBackground(
        from image: UIImage,
        filterType: RunPhotoBackground.PhotoFilterType = .blur,
        opacity: Double = 0.7
    ) async -> RunPhotoBackground? {
        // Compress image for storage
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert library image to data")
            return nil
        }
        
        // Generate a unique ID for library photo
        let photoId = "library_\(UUID().uuidString)"
        
        return RunPhotoBackground(
            photoId: photoId,
            photoData: imageData,
            filterType: filterType,
            opacity: opacity
        )
    }
    
    func selectRandomPhoto(from assets: [PHAsset], filterType: RunPhotoBackground.PhotoFilterType = .blur) async -> RunPhotoBackground? {
        // Use the smarter photo selection with screenshot filtering
        guard let randomAsset = selectRandomNonScreenshotPhoto(from: assets) else {
            return nil
        }
        
        return await createPhotoBackground(from: randomAsset, filterType: filterType)
    }
    
    // MARK: - Photo Storage Management
    
    func savePhotoBackground(_ background: RunPhotoBackground, for runId: String) {
        let key = "photo_background_\(runId)"
        
        do {
            let data = try JSONEncoder().encode(background)
            UserDefaults.standard.set(data, forKey: key)
            print("💾 Saved photo background for run \(runId)")
        } catch {
            print("❌ Failed to save photo background: \(error)")
        }
    }
    
    func loadPhotoBackground(for runId: String) -> RunPhotoBackground? {
        let key = "photo_background_\(runId)"
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        do {
            let background = try JSONDecoder().decode(RunPhotoBackground.self, from: data)
            return background
        } catch {
            print("❌ Failed to load photo background: \(error)")
            return nil
        }
    }
    
    func removePhotoBackground(for runId: String) {
        let key = "photo_background_\(runId)"
        UserDefaults.standard.removeObject(forKey: key)
        print("🗑️ Removed photo background for run \(runId)")
    }
    
    func getAllStoredPhotoBackgrounds() -> [String: RunPhotoBackground] {
        var backgrounds: [String: RunPhotoBackground] = [:]
        
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("photo_background_") {
                let runId = String(key.dropFirst("photo_background_".count))
                if let background = loadPhotoBackground(for: runId) {
                    backgrounds[runId] = background
                }
            }
        }
        
        return backgrounds
    }
    
    func clearAllPhotoBackgrounds() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("photo_background_") }
        
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        
        print("🗑️ Cleared all photo backgrounds")
    }
}