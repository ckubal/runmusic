import SwiftUI

struct SpotifyImportProgressView: View {
    @ObservedObject var importSession: SpotifyImportSession
    @Environment(\.dismiss) private var dismiss
    let onImportMore: () -> Void
    let onComplete: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Summary
                headerSummaryView
                
                // Progress List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(importSession.files) { fileProgress in
                            FileProgressRowView(fileProgress: fileProgress)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                
                // Bottom Actions
                if importSession.isCompleted {
                    bottomActionsView
                }
            }
            .navigationTitle("Import Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if importSession.isCompleted {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            onComplete()
                        }
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.medium)
                    }
                }
            }
        }
    }
    
    private var headerSummaryView: some View {
        VStack(spacing: 16) {
            // Overall Progress
            VStack(spacing: 8) {
                if importSession.isImporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if importSession.isCompleted {
                    Image(systemName: importSession.hasErrors ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(importSession.hasErrors ? .orange : .green)
                }
                
                Text(importStatusText)
                    .font(.custom("Helvetica Neue", size: 18))
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            
            // Stats Grid
            HStack(spacing: 24) {
                StatItemView(
                    title: "Files",
                    value: "\(importSession.totalFilesProcessed)/\(importSession.totalFilesSelected)",
                    color: .blue
                )
                
                StatItemView(
                    title: "Tracks Read",
                    value: "\(importSession.totalTracksRead.formatted())",
                    color: .purple
                )
                
                StatItemView(
                    title: "Imported",
                    value: "\(importSession.totalTracksImported.formatted())",
                    color: .green
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
    }
    
    private var importStatusText: String {
        if importSession.isImporting {
            return "Importing your Spotify history..."
        } else if importSession.isCompleted {
            if importSession.hasErrors {
                return "Import completed with \(importSession.failedFiles) error\(importSession.failedFiles == 1 ? "" : "s")"
            } else {
                return "Successfully imported \(importSession.totalTracksImported.formatted()) tracks!"
            }
        } else {
            return "Preparing to import..."
        }
    }
    
    private var bottomActionsView: some View {
        VStack(spacing: 12) {
            Divider()
            
            VStack(spacing: 12) {
                // Import More Button
                Button(action: onImportMore) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Import More Files")
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                // Done Button
                Button(action: onComplete) {
                    Text("Done")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

struct FileProgressRowView: View {
    let fileProgress: FileImportProgress
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File name and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileProgress.fileName)
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(fileSizeText)
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if fileProgress.status.isActive {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        
                        Text(fileProgress.status.displayName)
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                    }
                    
                    if fileProgress.tracksRead > 0 {
                        Text("\(fileProgress.tracksImported)/\(fileProgress.tracksRead) tracks")
                            .font(.custom("Helvetica Neue", size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress bar
            if fileProgress.status.isActive || fileProgress.status == .completed {
                ProgressView(value: fileProgress.progress)
                    .tint(progressColor)
            }
            
            // Error message
            if let errorMessage = fileProgress.errorMessage {
                Text(errorMessage)
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private var fileSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileProgress.fileSize))
    }
    
    private var statusColor: Color {
        switch fileProgress.status {
        case .pending: return .secondary
        case .reading, .parsing, .storing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private var progressColor: Color {
        switch fileProgress.status {
        case .completed: return .green
        case .failed: return .red
        default: return .blue
        }
    }
}

struct StatItemView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("Helvetica Neue", size: 20))
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.custom("Helvetica Neue", size: 12))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    let session = SpotifyImportSession()
    session.files = [
        FileImportProgress(fileName: "Streaming_History_Audio_2023_1.json", fileSize: 12000000, status: .completed, tracksRead: 15000, tracksImported: 12000, progress: 1.0),
        FileImportProgress(fileName: "Streaming_History_Audio_2023_2.json", fileSize: 8000000, status: .storing, tracksRead: 8000, tracksImported: 6000, progress: 0.75),
        FileImportProgress(fileName: "Streaming_History_Audio_2023_3.json", fileSize: 10000000, status: .pending, progress: 0.0)
    ]
    session.isImporting = true
    
    return SpotifyImportProgressView(
        importSession: session,
        onImportMore: {},
        onComplete: {}
    )
}