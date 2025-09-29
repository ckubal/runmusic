import Foundation

// MARK: - Import Progress Models

class SpotifyImportSession: ObservableObject {
    @Published var files: [FileImportProgress] = []
    @Published var isImporting: Bool = false
    @Published var isCompleted: Bool = false
    
    init() {
        // Default initialization
    }
    
    var totalFilesProcessed: Int {
        files.filter { $0.status == .completed || $0.status == .failed }.count
    }
    
    var totalFilesSelected: Int {
        files.count
    }
    
    var totalTracksRead: Int {
        files.reduce(0) { $0 + $1.tracksRead }
    }
    
    var totalTracksImported: Int {
        files.reduce(0) { $0 + $1.tracksImported }
    }
    
    var successfulFiles: Int {
        files.filter { $0.status == .completed }.count
    }
    
    var failedFiles: Int {
        files.filter { $0.status == .failed }.count
    }
    
    var hasErrors: Bool {
        files.contains { $0.status == .failed }
    }
    
    var overallProgress: Double {
        guard !files.isEmpty else { return 0.0 }
        let totalProgress = files.reduce(0.0) { total, file in
            switch file.status {
            case .completed:
                return total + 1.0
            case .failed:
                return total + 1.0  // Count failed as "complete" for progress
            case .reading, .parsing, .storing:
                return total + file.progress
            case .pending:
                return total + 0.0
            }
        }
        return totalProgress / Double(files.count)
    }
    
    var totalTracksSkipped: Int {
        // For now, return 0 as we don't track skipped tracks in FileImportProgress
        // This could be enhanced later to track duplicates skipped
        return 0
    }
}

struct FileImportProgress: Identifiable {
    let id = UUID()
    let fileName: String
    let fileSize: Int
    var status: ImportStatus = .pending
    var tracksRead: Int = 0
    var tracksImported: Int = 0
    var errorMessage: String?
    var progress: Double = 0.0 // 0.0 to 1.0
    
    enum ImportStatus {
        case pending
        case reading
        case parsing
        case storing
        case completed
        case failed
        
        var displayName: String {
            switch self {
            case .pending: return "Waiting..."
            case .reading: return "Reading file..."
            case .parsing: return "Parsing tracks..."
            case .storing: return "Storing to Firebase..."
            case .completed: return "✅ Complete"
            case .failed: return "❌ Failed"
            }
        }
        
        var isActive: Bool {
            switch self {
            case .reading, .parsing, .storing: return true
            default: return false
            }
        }
    }
}

// MARK: - Import Result Summary

struct SpotifyImportSummary {
    let totalFiles: Int
    let successfulFiles: Int
    let failedFiles: Int
    let totalTracksRead: Int
    let totalTracksImported: Int
    let newTracksAdded: Int
    let duplicatesSkipped: Int
    let timeElapsed: TimeInterval
    
    var successRate: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(successfulFiles) / Double(totalFiles)
    }
    
    var isFullSuccess: Bool {
        failedFiles == 0
    }
}