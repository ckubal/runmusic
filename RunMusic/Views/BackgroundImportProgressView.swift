import SwiftUI

struct BackgroundImportProgressView: View {
    @ObservedObject var importSession: SpotifyImportSession
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            if importSession.isImporting || importSession.isCompleted {
                // Collapsed view - small progress bar at bottom of screen
                if !isExpanded {
                    collapsedView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Expanded view - shows file details
                    expandedView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3), value: isExpanded)
        .animation(.spring(response: 0.3), value: importSession.isImporting)
    }
    
    private var collapsedView: some View {
        HStack(spacing: 12) {
            // Progress indicator
            if importSession.isImporting {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
            } else if importSession.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Expand/collapse button
            Button(action: {
                isExpanded.toggle()
            }) {
                Image(systemName: "chevron.up.circle.fill")
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.9), Color.green.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            // Overall progress bar
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: geometry.size.width * importSession.overallProgress, height: 2)
                    .animation(.linear(duration: 0.2), value: importSession.overallProgress)
            }
            .frame(height: 2),
            alignment: .bottom
        )
    }
    
    private var expandedView: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("importing spotify history")
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("\(importSession.successfulFiles) of \(importSession.totalFilesSelected) files completed")
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    isExpanded = false
                }) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // File progress list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(importSession.files.enumerated()), id: \.element.id) { index, file in
                        FileProgressRow(file: file, index: index + 1)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 200)
            
            // Overall stats
            HStack(spacing: 20) {
                ProgressStatView(
                    title: "tracks imported",
                    value: "\(importSession.totalTracksImported.formatted())",
                    color: .green
                )
                
                if importSession.totalTracksSkipped > 0 {
                    ProgressStatView(
                        title: "duplicates skipped",
                        value: "\(importSession.totalTracksSkipped.formatted())",
                        color: .orange
                    )
                }
                
                if importSession.failedFiles > 0 {
                    ProgressStatView(
                        title: "files failed",
                        value: "\(importSession.failedFiles)",
                        color: .red
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
    }
    
    private var statusTitle: String {
        if importSession.isCompleted {
            return "import complete!"
        } else if let currentFile = importSession.files.first(where: { $0.status == .reading || $0.status == .parsing || $0.status == .storing }) {
            return "importing \(currentFile.fileName)"
        } else {
            return "preparing import..."
        }
    }
    
    private var statusSubtitle: String? {
        if importSession.isCompleted {
            return "\(importSession.totalTracksImported.formatted()) tracks imported"
        } else if importSession.totalFilesSelected > 1 {
            return "\(importSession.successfulFiles + 1) of \(importSession.totalFilesSelected) files"
        }
        return nil
    }
}

struct FileProgressRow: View {
    let file: FileImportProgress
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .frame(width: 24)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.custom("Helvetica Neue", size: 13))
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if file.tracksImported > 0 {
                    Text("\(file.tracksImported) tracks")
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.secondary)
                } else if let error = file.errorMessage {
                    Text(error)
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Progress
            if file.status == .reading || file.status == .parsing || file.status == .storing {
                ProgressView(value: file.progress)
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                    .frame(width: 20)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch file.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        case .reading, .parsing, .storing:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}

struct ProgressStatView: View {
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
                .font(.custom("Helvetica Neue", size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Corner radius extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}