import Foundation
import UniformTypeIdentifiers

class SpotifyFileScanner {
    static let shared = SpotifyFileScanner()
    
    private init() {}
    
    struct FileScanResult {
        let fileName: String
        let fileSize: Int
        let trackCount: Int
        let dateRange: ClosedRange<Date>?
        let mostRecentTrack: SpotifyTrack?
        let sampleTracks: [SpotifyTrack] // First 10 tracks for preview
    }
    
    struct ScanSummary {
        let totalFiles: Int
        let totalTracks: Int
        let mostRecentFile: FileScanResult?
        let recentTracks: [SpotifyTrack] // Most recent 1000 tracks across all files
        let dateRange: ClosedRange<Date>?
    }
    
    // Quick scan multiple files to find the most recent tracks
    func quickScanFiles(_ urls: [URL]) async throws -> ScanSummary {
        print("🔍 Starting quick scan of \(urls.count) files...")
        
        var scanResults: [FileScanResult] = []
        var allRecentTracks: [SpotifyTrack] = []
        
        // Scan each file in parallel for efficiency
        await withTaskGroup(of: FileScanResult?.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        return try await self.scanSingleFile(url)
                    } catch {
                        print("❌ Failed to scan \(url.lastPathComponent): \(error)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let result = result {
                    scanResults.append(result)
                    
                    // Collect sample tracks from each file
                    allRecentTracks.append(contentsOf: result.sampleTracks)
                }
            }
        }
        
        // Sort results by filename number (highest first for most recent)
        scanResults.sort { file1, file2 in
            let number1 = extractFileNumber(from: file1.fileName)
            let number2 = extractFileNumber(from: file2.fileName)
            return number1 > number2 // Highest numbered file first
        }
        
        // Sort all collected tracks by date and take the most recent 1000
        allRecentTracks.sort { $0.playedAt > $1.playedAt }
        let recentTracks = Array(allRecentTracks.prefix(1000))
        
        // Calculate overall date range
        let allDates = scanResults.compactMap { $0.dateRange }
        let overallDateRange: ClosedRange<Date>? = {
            guard !allDates.isEmpty else { return nil }
            let minDate = allDates.map { $0.lowerBound }.min()!
            let maxDate = allDates.map { $0.upperBound }.max()!
            return minDate...maxDate
        }()
        
        let totalTracks = scanResults.reduce(0) { $0 + $1.trackCount }
        
        print("✅ Scan complete: \(scanResults.count) files, \(totalTracks) total tracks")
        print("📅 Date range: \(overallDateRange?.lowerBound.formatted() ?? "unknown") to \(overallDateRange?.upperBound.formatted() ?? "unknown")")
        
        return ScanSummary(
            totalFiles: scanResults.count,
            totalTracks: totalTracks,
            mostRecentFile: scanResults.first,
            recentTracks: recentTracks,
            dateRange: overallDateRange
        )
    }
    
    // Scan a single file to extract metadata without full parsing
    private func scanSingleFile(_ url: URL) async throws -> FileScanResult {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "SpotifyFileScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int ?? 0
        
        // Read file data
        let data = try Data(contentsOf: url)
        
        // Quick parse to extract sample tracks and metadata
        let decoder = JSONDecoder()
        let spotifyData = try decoder.decode([SpotifyImportedTrack].self, from: data)
        
        // Convert first batch to SpotifyTrack format for preview
        let sampleTracks = spotifyData.prefix(100).compactMap { item -> SpotifyTrack? in
            // Parse the ISO 8601 timestamp with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            guard let playedAt = formatter.date(from: item.ts) else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                guard let fallbackDate = formatter.date(from: item.ts) else { return nil }
                
                return SpotifyTrack(
                    id: UUID().uuidString, // Generate unique ID
                    name: item.master_metadata_track_name ?? "Unknown Track",
                    artist: item.master_metadata_album_artist_name ?? "Unknown Artist",
                    album: item.master_metadata_album_album_name,
                    playedAt: fallbackDate,
                    durationMs: item.ms_played,
                    albumImageURL: nil
                )
            }
            
            return SpotifyTrack(
                id: UUID().uuidString,
                name: item.master_metadata_track_name ?? "Unknown Track",
                artist: item.master_metadata_album_artist_name ?? "Unknown Artist",
                album: item.master_metadata_album_album_name,
                playedAt: playedAt,
                durationMs: item.ms_played,
                albumImageURL: nil
            )
        }
        
        // Find date range
        let dates = sampleTracks.map { $0.playedAt }
        let dateRange: ClosedRange<Date>? = {
            guard !dates.isEmpty else { return nil }
            // Note: In the actual file, oldest tracks are first, newest are last
            return dates.min()!...dates.max()!
        }()
        
        return FileScanResult(
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            trackCount: spotifyData.count,
            dateRange: dateRange,
            mostRecentTrack: sampleTracks.last, // Last track is most recent in Spotify export
            sampleTracks: Array(sampleTracks.suffix(10)) // Last 10 tracks are most recent
        )
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
        
        // If no number found, return 0 (will be sorted last)
        return 0
    }
}

// Spotify import data structure
private struct SpotifyImportedTrack: Codable {
    let ts: String
    let ms_played: Int
    let master_metadata_track_name: String?
    let master_metadata_album_artist_name: String?
    let master_metadata_album_album_name: String?
    let spotify_track_uri: String?
}