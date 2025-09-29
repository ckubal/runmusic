import SwiftUI

struct RunCanvasView: View {
    @Binding var run: RunActivity
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAsset: CanvasAsset?
    @State private var assets: [CanvasAsset] = []
    @State private var canvasSize: CGSize = .zero
    @State private var showingAddAssetMenu = false
    @State private var showingEditSheet = false
    @State private var editingAsset: CanvasAsset?
    
    // Canvas interaction state
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas background (photo or gradient)
                backgroundView(geometry: geometry)
                
                // Canvas area - NO SCROLLING, pure canvas
                canvasArea
                
                // Minimal UI overlay (just back button and add button)
                controlsOverlay
            }
            .onAppear {
                canvasSize = geometry.size
                setupCanvasAssets()
            }
            .onChange(of: run) { _, _ in
                // Regenerate assets if run data changes
                setupCanvasAssets()
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea()
        .sheet(isPresented: $showingAddAssetMenu) {
            AddAssetMenu { assetType in
                addNewAsset(type: assetType)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let editingAsset = editingAsset {
                AssetEditSheet(asset: editingAsset) { updatedAsset in
                    updateAsset(updatedAsset)
                    self.editingAsset = nil
                }
            }
        }
    }
    
    // MARK: - Canvas Area
    
    private var canvasArea: some View {
        ZStack {
            // Tap area to deselect
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedAsset = nil
                    }
                }
            
            // Canvas drag gesture for overall pan (when nothing is selected)
            .gesture(
                selectedAsset == nil ? 
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    } : nil
            )
            .offset(dragOffset)
            
            // Render all assets
            ForEach(assets.filter { $0.isVisible }) { asset in
                EnhancedAssetView(
                    asset: asset,
                    isSelected: selectedAsset?.id == asset.id,
                    canvasSize: canvasSize,
                    onSelect: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedAsset = asset
                        }
                    },
                    onUpdate: updateAsset,
                    onEdit: { asset in
                        editingAsset = asset
                        showingEditSheet = true
                    }
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            // Top controls - just back button
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                Spacer()
                
                // Canvas info (optional - shows selected asset info)
                if let selectedAsset = selectedAsset {
                    Text(selectedAsset.type.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                        )
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Bottom controls
            HStack {
                Spacer()
                
                VStack(spacing: 16) {
                    // Contextual controls for selected asset
                    if let selectedAsset = selectedAsset {
                        contextualControls(for: selectedAsset)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Add asset button
                    Button {
                        showingAddAssetMenu = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
                            )
                    }
                    .scaleEffect(showingAddAssetMenu ? 0.95 : 1.0)
                    .animation(.spring(response: 0.3), value: showingAddAssetMenu)
                }
            }
            .padding(.bottom, 60)
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Contextual Controls
    
    private func contextualControls(for asset: CanvasAsset) -> some View {
        VStack(spacing: 8) {
            // Edit button (if editable)
            if asset.editableType != .none {
                contextButton("pencil", "Edit") {
                    editingAsset = asset
                    showingEditSheet = true
                }
            }
            
            // Duplicate button (if allowed)
            if asset.canDuplicate {
                contextButton("doc.on.doc", "Duplicate") {
                    duplicateAsset(asset)
                }
            }
            
            // Hide/Show button
            contextButton(asset.isVisible ? "eye.slash" : "eye", asset.isVisible ? "Hide" : "Show") {
                toggleAssetVisibility(asset)
            }
            
            // Delete button (if allowed)
            if asset.canDelete {
                contextButton("trash", "Delete", isDestructive: true) {
                    deleteAsset(asset)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.05))
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
    
    private func contextButton(_ icon: String, _ label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isDestructive ? .red : .white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isDestructive ? 0.1 : 0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Background
    
    private func backgroundView(geometry: GeometryProxy) -> some View {
        Group {
            if let photoBackground = run.backgroundPhoto {
                PhotoBackgroundView(photoBackground: photoBackground)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                // Default gradient background
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.3),
                        Color.purple.opacity(0.2),
                        Color.pink.opacity(0.1),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    // MARK: - Asset Management
    
    private func setupCanvasAssets() {
        print("🎨 Setting up canvas assets for run: \(run.name)")
        assets = CanvasAsset.generateDefaultAssets(for: run, canvasSize: canvasSize)
        print("🎨 Generated \(assets.count) assets")
    }
    
    private func updateAsset(_ asset: CanvasAsset) {
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        }
    }
    
    private func addNewAsset(type: AssetType) {
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        
        var newAsset: CanvasAsset
        
        switch type {
        case .text:
            newAsset = CanvasAsset(
                type: .text,
                content: .text("Tap to edit"),
                position: CGPoint(x: centerX, y: centerY),
                fontSize: 18,
                fontWeight: .medium,
                editableType: .text
            )
            
        case .image:
            newAsset = CanvasAsset(
                type: .image,
                content: .image(nil),
                position: CGPoint(x: centerX, y: centerY),
                editableType: .image
            )
            
        case .songList:
            newAsset = CanvasAsset.createSongList(for: run, position: CGPoint(x: centerX, y: centerY))
            
        case .powerSong:
            guard let powerSongAsset = CanvasAsset.createPowerSong(for: run, position: CGPoint(x: centerX, y: centerY)) else {
                // No power song available for this run
                return
            }
            newAsset = powerSongAsset
            
        default:
            // For other types, we could create specific factory methods
            return
        }
        
        withAnimation(.spring(response: 0.4)) {
            assets.append(newAsset)
            selectedAsset = newAsset
        }
    }
    
    private func duplicateAsset(_ asset: CanvasAsset) {
        var duplicatedAsset = asset
        duplicatedAsset.position.x += 30
        duplicatedAsset.position.y += 30
        
        withAnimation(.spring(response: 0.4)) {
            assets.append(duplicatedAsset)
            selectedAsset = duplicatedAsset
        }
    }
    
    private func toggleAssetVisibility(_ asset: CanvasAsset) {
        updateAsset(CanvasAsset(
            type: asset.type,
            content: asset.content,
            position: asset.position,
            rotation: asset.rotation,
            scale: asset.scale,
            fontSize: asset.fontSize,
            fontWeight: asset.fontWeight,
            color: asset.color,
            isVisible: !asset.isVisible,
            isSelected: asset.isSelected,
            zIndex: asset.zIndex,
            editableType: asset.editableType,
            canDelete: asset.canDelete,
            canDuplicate: asset.canDuplicate
        ))
    }
    
    private func deleteAsset(_ asset: CanvasAsset) {
        withAnimation(.spring(response: 0.4)) {
            assets.removeAll { $0.id == asset.id }
            if selectedAsset?.id == asset.id {
                selectedAsset = nil
            }
        }
    }
}

// MARK: - Supporting Views

struct AddAssetMenu: View {
    let onAssetTypeSelected: (AssetType) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add Canvas Element")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    ForEach([AssetType.text, AssetType.image, AssetType.songList, AssetType.powerSong], id: \.self) { type in
                        Button(action: {
                            onAssetTypeSelected(type)
                            dismiss()
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: type.systemIcon)
                                    .font(.system(size: 32))
                                    .foregroundColor(.blue)
                                
                                Text(type.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(400)])
    }
}

struct AssetEditSheet: View {
    let asset: CanvasAsset
    let onSave: (CanvasAsset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var editedContent = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Edit \(asset.type.displayName)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if asset.editableType == .text {
                    TextField("Enter text", text: $editedContent)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedAsset = asset
                        if asset.editableType == .text {
                            updatedAsset.content = .text(editedContent)
                        }
                        onSave(updatedAsset)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            editedContent = asset.content.displayText
        }
        .presentationDetents([.height(400)])
    }
}

#Preview {
    let sampleRun = RunActivity(
        id: "1",
        name: "Morning Run in Golden Gate Park",
        date: Date(),
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
        neighborhood: "Golden Gate Park"
    )
    
    RunCanvasView(run: .constant(sampleRun))
}