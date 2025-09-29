import SwiftUI
import MapKit
import UIKit

/// High-quality card export service that captures pixel-perfect snapshots of rendered views
@MainActor
class CardExportService: ObservableObject {
    
    enum ExportError: LocalizedError {
        case mapSnapshotFailed
        case imageRenderFailed
        case layoutNotReady
        
        var errorDescription: String? {
            switch self {
            case .mapSnapshotFailed:
                return "Failed to capture map snapshot"
            case .imageRenderFailed:
                return "Failed to render card image"
            case .layoutNotReady:
                return "View layout not ready for export"
            }
        }
    }
    
    /// Export a SwiftUI card view to high-quality UIImage
    /// - Parameters:
    ///   - cardView: The SwiftUI view to export
    ///   - exportSize: Target size for export (default: native card size)
    ///   - scale: Pixel scale factor (default: screen scale)
    ///   - includeMapSnapshot: Whether to use static map snapshot for better quality
    /// - Returns: High-quality UIImage of the card
    func exportCard<CardView: View>(
        cardView: CardView,
        exportSize: CGSize? = nil,
        scale: CGFloat = UIScreen.main.scale,
        includeMapSnapshot: Bool = true
    ) async throws -> UIImage {
        
        print("📸 CardExportService: Starting export with scale \(scale)")
        
        // Step 1: Allow layout to fully settle
        await ensureLayoutSettled()
        
        // Step 2: Prepare the card for export
        let exportView = prepareCardForExport(cardView, includeMapSnapshot: includeMapSnapshot)
        
        // Step 3: Configure renderer
        var renderer = ImageRenderer(content: exportView)
        
        if let exportSize = exportSize {
            renderer.proposedSize = ProposedViewSize(width: exportSize.width, height: exportSize.height)
            print("📸 Using custom export size: \(exportSize)")
        } else {
            renderer.proposedSize = ProposedViewSize.unspecified
            print("📸 Using natural view size")
        }
        
        renderer.scale = scale
        renderer.isOpaque = true
        
        // Step 4: Render the image
        guard let image = renderer.uiImage else {
            print("❌ CardExportService: ImageRenderer returned nil")
            throw ExportError.imageRenderFailed
        }
        
        print("✅ CardExportService: Successfully exported image \(image.size) @ \(image.scale)x scale")
        return image
    }
    
    /// Export card at Instagram Stories dimensions (1080x1920)
    func exportCardForInstagram<CardView: View>(
        cardView: CardView,
        includeMapSnapshot: Bool = true
    ) async throws -> UIImage {
        
        let instagramSize = CGSize(width: 1080, height: 1920)
        return try await exportCard(
            cardView: cardView,
            exportSize: instagramSize,
            scale: 1.0, // Use 1.0 scale for exact pixel dimensions
            includeMapSnapshot: includeMapSnapshot
        )
    }
    
    /// Prepare card view with optional map snapshot replacement
    private func prepareCardForExport<CardView: View>(
        _ cardView: CardView,
        includeMapSnapshot: Bool
    ) -> some View {
        
        if includeMapSnapshot {
            // For future: could implement map snapshot overlay if SwiftUI Map has issues
            // For now, SwiftUI Map with overlays should render correctly in iOS 17+
            return cardView
        } else {
            return cardView
        }
    }
    
    /// Ensure all layout and visual effects are fully settled
    private func ensureLayoutSettled() async {
        // Force a layout pass
        await MainActor.run {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.layoutIfNeeded()
            }
        }
        
        // Allow Core Animation and blur effects to settle
        CATransaction.flush()
        
        // Give SwiftUI a tick to finalize any pending updates
        try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame at 60fps
    }
    
    /// Create a static map snapshot for overlay purposes (fallback if needed)
    func createMapSnapshot(
        region: MKCoordinateRegion,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        songPositions: [CLLocationCoordinate2D] = []
    ) async throws -> UIImage? {
        
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = scale
        options.region = region
        options.mapType = .standard
        options.showsBuildings = true
        
        // Configure visual appearance
        if #available(iOS 17.0, *) {
            options.preferredConfiguration = MKStandardMapConfiguration()
        }
        
        let snapshotter = MKMapSnapshotter(options: options)
        
        do {
            let snapshot = try await snapshotter.start()
            
            // If we need route/song overlays, composite them here
            if !routeCoordinates.isEmpty || !songPositions.isEmpty {
                return try await compositeOverlays(
                    baseImage: snapshot.image,
                    snapshot: snapshot,
                    routeCoordinates: routeCoordinates,
                    songPositions: songPositions
                )
            }
            
            return snapshot.image
            
        } catch {
            print("❌ CardExportService: Map snapshot failed: \(error)")
            throw ExportError.mapSnapshotFailed
        }
    }
    
    /// Composite route and song position overlays onto map snapshot
    private func compositeOverlays(
        baseImage: UIImage,
        snapshot: MKMapSnapshotter.Snapshot,
        routeCoordinates: [CLLocationCoordinate2D],
        songPositions: [CLLocationCoordinate2D]
    ) async throws -> UIImage {
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = baseImage.scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: baseImage.size, format: format)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Draw base map
            baseImage.draw(at: .zero)
            
            // Draw route path
            if routeCoordinates.count >= 2 {
                drawRoutePath(
                    coordinates: routeCoordinates,
                    snapshot: snapshot,
                    in: cgContext
                )
            }
            
            // Draw song position markers
            for coordinate in songPositions {
                drawSongMarker(
                    at: coordinate,
                    snapshot: snapshot,
                    in: cgContext
                )
            }
        }
    }
    
    /// Draw route path on Core Graphics context
    private func drawRoutePath(
        coordinates: [CLLocationCoordinate2D],
        snapshot: MKMapSnapshotter.Snapshot,
        in context: CGContext
    ) {
        guard coordinates.count >= 2 else { return }
        
        // Convert coordinates to screen points
        let points = coordinates.compactMap { coordinate in
            snapshot.point(for: coordinate)
        }
        
        guard points.count >= 2 else { return }
        
        // Configure route drawing
        context.setStrokeColor(UIColor.orange.cgColor)
        context.setLineWidth(3.0 * snapshot.image.scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw the path
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }
    
    /// Draw song position marker on Core Graphics context  
    private func drawSongMarker(
        at coordinate: CLLocationCoordinate2D,
        snapshot: MKMapSnapshotter.Snapshot,
        in context: CGContext
    ) {
        let point = snapshot.point(for: coordinate)
        let radius: CGFloat = 6.0 * snapshot.image.scale
        
        // Draw marker circle
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        
        // Draw inner dot
        let innerRadius = radius * 0.6
        context.setFillColor(UIColor.green.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - innerRadius,
            y: point.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
    }
    
    /// Save image to Photos library (requires photo library permission)
    func saveToPhotos(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { continuation in
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            continuation.resume()
        }
    }
}

// MARK: - Convenience Extensions

extension CardExportService {
    
    /// Export current card state from RunDetailView
    func exportRunCard(
        run: RunActivity
    ) async throws -> UIImage {
        
        // Create the exact card view that's displayed
        let cardView = ShareableCardView(
            run: run
        )
        .frame(width: 390, height: 640) // Standard card dimensions
        
        return try await exportCard(
            cardView: cardView,
            exportSize: CGSize(width: 390, height: 640),
            scale: UIScreen.main.scale,
            includeMapSnapshot: true
        )
    }
}

// MARK: - Preview Support

#Preview {
    Text("CardExportService - Use in RunDetailView")
}