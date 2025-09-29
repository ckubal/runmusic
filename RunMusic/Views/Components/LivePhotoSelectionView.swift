import SwiftUI
import Photos
import PhotosUI

// MARK: - Live Photo Selection View

struct LivePhotoSelectionView: View {
    @Binding var run: RunActivity
    let layoutType: ShareableCardLayoutType
    let availablePhotos: [PHAsset]
    
    @StateObject private var photoService = PhotoService.shared
    @State private var selectedPhoto: PHAsset?
    @State private var selectedLibraryPhoto: UIImage?
    @State private var selectedFilter: RunPhotoBackground.PhotoFilterType = .blur
    @State private var selectedOpacity: Double = 0.7
    @State private var photoPreviewImages: [String: UIImage] = [:]
    @State private var isLoadingPhoto = false
    
    // Smart photo filtering
    private var smartFilteredPhotos: [PHAsset] {
        let runStartTime = run.date
        let runEndTime = run.date.addingTimeInterval(run.elapsedTime)
        
        // Add buffer around run time (30 minutes before and after)
        let bufferTime: TimeInterval = 30 * 60
        let searchStartTime = runStartTime.addingTimeInterval(-bufferTime)
        let searchEndTime = runEndTime.addingTimeInterval(bufferTime)
        
        // Filter photos by timeframe
        let timeFilteredPhotos = availablePhotos.filter { asset in
            guard let creationDate = asset.creationDate else { return false }
            return creationDate >= searchStartTime && creationDate <= searchEndTime
        }
        
        // Sort by how close they are to the run timeframe
        let sortedPhotos = timeFilteredPhotos.sorted { asset1, asset2 in
            guard let date1 = asset1.creationDate,
                  let date2 = asset2.creationDate else { return false }
            
            // Calculate distance from run timeframe
            let distance1 = min(abs(date1.timeIntervalSince(runStartTime)), 
                              abs(date1.timeIntervalSince(runEndTime)))
            let distance2 = min(abs(date2.timeIntervalSince(runStartTime)), 
                              abs(date2.timeIntervalSince(runEndTime)))
            
            return distance1 < distance2
        }
        
        // If we have run-time photos, prioritize them
        if !sortedPhotos.isEmpty {
            return sortedPhotos
        }
        
        // Fallback to all available photos if none found in timeframe
        return availablePhotos.sorted { asset1, asset2 in
            guard let date1 = asset1.creationDate,
                  let date2 = asset2.creationDate else { return false }
            return date1 > date2 // Most recent first
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if !availablePhotos.isEmpty {
                VStack(spacing: 16) {
                    // Inline Photo Picker
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if smartFilteredPhotos.count != availablePhotos.count {
                                Text("\(smartFilteredPhotos.count) during run")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                // Add photo from library option
                                AddPhotoFromLibraryButton(
                                    selectedLibraryPhoto: $selectedLibraryPhoto,
                                    selectedPhoto: $selectedPhoto
                                )
                                
                                // Available photos
                                ForEach(smartFilteredPhotos, id: \.localIdentifier) { asset in
                                    InlinePhotoThumbnail(
                                        asset: asset,
                                        isSelected: selectedPhoto?.localIdentifier == asset.localIdentifier,
                                        previewImage: photoPreviewImages[asset.localIdentifier],
                                        onTap: {
                                            selectedPhoto = asset
                                            selectedLibraryPhoto = nil
                                            // No need to reload - image should already be preloaded
                                        }
                                    )
                                    .onAppear {
                                        // Ensure this specific photo loads when it comes into view
                                        loadPreviewIfNeeded(for: asset, priority: .userInitiated)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Inline Filter Controls - Only show if photo is selected
                    if selectedPhoto != nil || selectedLibraryPhoto != nil {
                        InlineFilterControls(
                            selectedFilter: $selectedFilter,
                            selectedOpacity: $selectedOpacity
                        )
                    }
                }
            } else {
                // No photos available - show library picker prominently
                VStack(spacing: 16) {
                    NoPhotosAvailableView()
                    
                    // Prominent library picker when no photos found
                    VStack(spacing: 12) {
                        Text("choose from library")
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        AddPhotoFromLibraryButton(
                            selectedLibraryPhoto: $selectedLibraryPhoto,
                            selectedPhoto: $selectedPhoto
                        )
                        .scaleEffect(1.5)  // Make it larger when it's the only option
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    // Show filter controls even when no photos found
                    if selectedLibraryPhoto != nil {
                        InlineFilterControls(
                            selectedFilter: $selectedFilter,
                            selectedOpacity: $selectedOpacity
                        )
                    }
                }
            }
        }
        .onAppear {
            loadPreviewImages()
        }
        .onChange(of: smartFilteredPhotos.count) { _, _ in
            // Reload when filtered photos change
            loadPreviewImages()
        }
        .onChange(of: selectedPhoto) { _, _ in
            updateRunPhotoBackground()
        }
        .onChange(of: selectedLibraryPhoto) { _, _ in
            updateRunPhotoBackground()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateRunPhotoBackground()  
        }
        .onChange(of: selectedOpacity) { _, _ in
            updateRunPhotoBackground()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadPreviewImages() {
        // Load all photos immediately for better UX - these are thumbnails so they're small
        let allPhotos = smartFilteredPhotos
        
        // Load first 12 photos with high priority (likely to be visible)
        let highPriorityBatch = min(12, allPhotos.count)
        for asset in allPhotos.prefix(highPriorityBatch) {
            loadPreviewIfNeeded(for: asset, priority: .userInitiated)
        }
        
        // Load remaining photos in background
        if allPhotos.count > highPriorityBatch {
            DispatchQueue.global(qos: .utility).async {
                for asset in allPhotos.dropFirst(highPriorityBatch) {
                    self.loadPreviewIfNeeded(for: asset, priority: .utility)
                }
            }
        }
    }
    
    private func loadPreviewIfNeeded(for asset: PHAsset, priority: DispatchQoS.QoSClass = .userInitiated) {
        guard photoPreviewImages[asset.localIdentifier] == nil else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // Get good quality immediately
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false // Ensure async loading
        options.resizeMode = .exact
        
        // Use appropriate target size for crisp thumbnails
        let targetSize = CGSize(width: 120, height: 120) // 2x the display size (60pt)
        
        // Use the appropriate queue based on priority
        let requestQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: priority.rawValue) ?? .userInitiated)
        
        requestQueue.async {
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Handle errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("⚠️ Photo loading error for asset \(asset.localIdentifier): \(error.localizedDescription)")
                    return
                }
                
                // Check if request was cancelled
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    return
                }
                
                if let image = image {
                    DispatchQueue.main.async {
                        self.photoPreviewImages[asset.localIdentifier] = image
                    }
                } else {
                    print("⚠️ Photo loading failed for asset \(asset.localIdentifier) - no image returned")
                }
            }
        }
    }
    
    private func updateRunPhotoBackground() {
        guard selectedPhoto != nil || selectedLibraryPhoto != nil else {
            // Remove photo background
            // Remove photo background (portrait only)
            run.portraitSettings.backgroundPhoto = nil
            return
        }
        
        // Get photo data
        var photoData: Data?
        
        if let libraryPhoto = selectedLibraryPhoto {
            photoData = libraryPhoto.jpegData(compressionQuality: 0.8)
        } else if let asset = selectedPhoto,
                  let previewImage = photoPreviewImages[asset.localIdentifier] {
            photoData = previewImage.jpegData(compressionQuality: 0.8)
        }
        
        guard let data = photoData else { return }
        
        let photoBackground = RunPhotoBackground(
            photoId: selectedPhoto?.localIdentifier ?? UUID().uuidString,
            photoData: data,
            filterType: selectedFilter,
            opacity: selectedOpacity
        )
        
        // Update the appropriate layout settings
        // Apply photo background (portrait only)
        run.portraitSettings.backgroundPhoto = photoBackground
    }
}


// MARK: - Inline Photo Thumbnail

struct InlinePhotoThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    let previewImage: UIImage?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(0.6)
                        )
                }
                
                // Selection indicator
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange, lineWidth: 3)
                        .frame(width: 60, height: 60)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.orange)
                                .background(Color.white.clipShape(Circle()))
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .frame(width: 60, height: 60)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Photo From Library Button

struct AddPhotoFromLibraryButton: View {
    @Binding var selectedLibraryPhoto: UIImage?
    @Binding var selectedPhoto: PHAsset?
    @State private var photosPickerItem: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker(
            selection: $photosPickerItem,
            matching: .images
        ) {
            VStack(spacing: 4) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.title3)
                    .foregroundColor(.blue)
                
                Text("library")
                    .font(.custom("Helvetica Neue", size: 10))
                    .foregroundColor(.blue)
            }
            .frame(width: 60, height: 60)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onChange(of: photosPickerItem) { _, newItem in
            if let newItem = newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedLibraryPhoto = image
                            selectedPhoto = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Inline Filter Controls

struct InlineFilterControls: View {
    @Binding var selectedFilter: RunPhotoBackground.PhotoFilterType
    @Binding var selectedOpacity: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("effects")
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Filter buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(RunPhotoBackground.PhotoFilterType.allCases, id: \.self) { filterType in
                        FilterButton(
                            filterType: filterType,
                            isSelected: selectedFilter == filterType,
                            onTap: {
                                selectedFilter = filterType
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Intensity slider
            VStack(alignment: .leading, spacing: 8) {
                Text("intensity")
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack {
                    Text("subtle")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                    
                    Slider(value: $selectedOpacity, in: 0.3...1.0, step: 0.1)
                        .tint(.orange)
                    
                    Text("strong")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let filterType: RunPhotoBackground.PhotoFilterType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(filterType.displayName)
                .font(.custom("Helvetica Neue", size: 12))
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.orange : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - No Photos Available View

struct NoPhotosAvailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("no photos found")
                .font(.custom("Helvetica Neue", size: 16))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("no photos found in the 1-hour window around your run")
                .font(.custom("Helvetica Neue", size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

