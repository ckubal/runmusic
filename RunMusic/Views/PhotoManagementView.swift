import SwiftUI
import Photos
import PhotosUI

struct PhotoManagementView: View {
    @Binding var run: RunActivity
    let availablePhotos: [PHAsset]
    let onPhotoSelected: (RunPhotoBackground) -> Void
    
    @StateObject private var photoService = PhotoService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPhoto: PHAsset?
    @State private var selectedFilter: RunPhotoBackground.PhotoFilterType = .blur
    private let fixedOpacity: Double = 0.7
    @State private var isLoadingPhoto = false
    @State private var previewImages: [String: UIImage] = [:]
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var selectedLibraryPhoto: UIImage?
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: true) {
                VStack(spacing: 24) {
                    if availablePhotos.isEmpty {
                        // No photos available
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            
                            Text("no photos found")
                                .font(.custom("Helvetica Neue", size: 20))
                                .fontWeight(.semibold)
                            
                            Text("no photos were found during your run time. try taking photos during your next run to add custom backgrounds!")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        // Header with Surprise Me button
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("choose a photo")
                                    .font(.custom("Helvetica Neue", size: 24))
                                    .fontWeight(.bold)
                                
                                Text("select from \(availablePhotos.count) photo\(availablePhotos.count == 1 ? "" : "s") taken during your run")
                                    .font(.custom("Helvetica Neue", size: 16))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Subtle Surprise Me button (only show if there are 2+ photos)
                            if availablePhotos.count >= 2 {
                                Button(action: selectRandomPhoto) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "shuffle")
                                            .font(.caption)
                                        Text("surprise me")
                                            .font(.custom("Helvetica Neue", size: 12))
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Photo Grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(availablePhotos, id: \.localIdentifier) { asset in
                                PhotoGridItem(
                                    asset: asset,
                                    isSelected: selectedPhoto?.localIdentifier == asset.localIdentifier,
                                    previewImage: previewImages[asset.localIdentifier],
                                    onTap: {
                                        selectedPhoto = asset
                                        selectedLibraryPhoto = nil // Clear library photo selection
                                        loadPreviewIfNeeded(for: asset)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Selected library photo preview
                        if let libraryPhoto = selectedLibraryPhoto {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("selected from library")
                                    .font(.custom("Helvetica Neue", size: 16))
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 20)
                                
                                Button(action: {
                                    // Handle library photo selection
                                }) {
                                    ZStack {
                                        Image(uiImage: libraryPhoto)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 200)
                                            .clipped()
                                            .cornerRadius(12)
                                        
                                        // Selection indicator
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.orange, lineWidth: 3)
                                        
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.orange)
                                                    .background(Color.white.clipShape(Circle()))
                                                    .font(.title2)
                                            }
                                            Spacer()
                                        }
                                        .padding(8)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 20)
                            }
                            .padding(.top, 20)
                        }
                        
                        // Manual photo library selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("or browse all photos")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                            
                            PhotosPicker(
                                selection: $photosPickerItem,
                                matching: .images
                            ) {
                                HStack {
                                    Image(systemName: "photo.stack")
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("select from library")
                                            .font(.custom("Helvetica Neue", size: 16))
                                            .fontWeight(.medium)
                                        
                                        Text("choose any photo from your library")
                                            .font(.custom("Helvetica Neue", size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(.primary)
                                .padding(16)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 20)
                        
                        // Filter Selection (only show if photo is selected)
                        if selectedPhoto != nil || selectedLibraryPhoto != nil {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("customize appearance")
                                    .font(.custom("Helvetica Neue", size: 20))
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 20)
                                
                                // Show filter selection for either PHAsset or library photo
                                if let imageData = getSelectedPhotoData() {
                                    PhotoFilterSelectionView(
                                        photoData: imageData,
                                        selectedFilter: $selectedFilter
                                    )
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.top, 20)
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("background photo")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(
                leading: Button("cancel") {
                    dismiss()
                }
                .foregroundColor(.secondary),
                trailing: selectedPhoto != nil || selectedLibraryPhoto != nil ? 
                    AnyView(Button(action: applySelectedPhoto) {
                        Text("confirm")
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }) : AnyView(EmptyView())
            )
        }
        .onAppear {
            loadPreviewImages()
        }
        .onChange(of: photosPickerItem) { newItem in
            if let newItem = newItem {
                Task.detached {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedLibraryPhoto = image
                            selectedPhoto = nil // Clear run photo selection
                        }
                    }
                }
            }
        }
    }
    
    private func getSelectedPhotoData() -> Data? {
        if let libraryPhoto = selectedLibraryPhoto {
            return libraryPhoto.jpegData(compressionQuality: 0.8)
        } else if let asset = selectedPhoto,
                  let previewImage = previewImages[asset.localIdentifier] {
            return previewImage.jpegData(compressionQuality: 0.8)
        }
        return nil
    }
    
    private func loadPreviewImages() {
        // Load preview for first few photos
        for asset in availablePhotos.prefix(6) {
            loadPreviewIfNeeded(for: asset)
        }
    }
    
    private func loadPreviewIfNeeded(for asset: PHAsset) {
        guard previewImages[asset.localIdentifier] == nil else { return }
        
        Task {
            if let image = await photoService.loadImage(from: asset, targetSize: CGSize(width: 200, height: 200)) {
                await MainActor.run {
                    previewImages[asset.localIdentifier] = image
                }
            }
        }
    }
    
    private func selectRandomPhoto() {
        guard let randomAsset = availablePhotos.randomElement() else { return }
        
        selectedPhoto = randomAsset
        selectedFilter = RunPhotoBackground.PhotoFilterType.allCases.randomElement() ?? .blur
        // Fixed opacity is used instead of random
        
        loadPreviewIfNeeded(for: randomAsset)
    }
    
    private func applySelectedPhoto() {
        isLoadingPhoto = true
        
        Task {
            var photoBackground: RunPhotoBackground?
            
            if let libraryPhoto = selectedLibraryPhoto {
                // Handle library photo
                photoBackground = await photoService.createPhotoBackground(
                    from: libraryPhoto,
                    filterType: selectedFilter,
                    opacity: fixedOpacity
                )
            } else if let asset = selectedPhoto {
                // Handle PHAsset photo
                photoBackground = await photoService.createPhotoBackground(
                    from: asset,
                    filterType: selectedFilter,
                    opacity: fixedOpacity
                )
            }
            
            await MainActor.run {
                if let photoBackground = photoBackground {
                    onPhotoSelected(photoBackground)
                    dismiss()
                }
                isLoadingPhoto = false
            }
        }
    }
}

struct PhotoGridItem: View {
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
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 120)
                        .cornerRadius(12)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(0.8)
                        )
                }
                
                // Selection indicator
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 3)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.orange)
                                .background(Color.white.clipShape(Circle()))
                                .font(.title2)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PhotoManagementView(
        run: .constant(RunActivity(
            id: "1",
            name: "Test Run",
            date: Date(),
            distance: 5000,
            elapsedTime: 1800,
            averagePace: 360,
            startLocation: nil as LocationData?,
            endLocation: nil as LocationData?,
            routeCoordinates: [],
            city: "Test City",
            neighborhood: "Test Neighborhood",
            spotifyTracks: nil as [SpotifyTrack]?
        )),
        availablePhotos: [],
        onPhotoSelected: { _ in }
    )
}