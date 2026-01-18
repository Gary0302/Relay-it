//
//  TimelinePanel.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

/// Right panel showing screenshot timeline
struct TimelinePanel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: SessionViewModel
    @Binding var selectedScreenshotId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Screenshots")
                    .font(.headline)
                    .foregroundStyle(Color.themeText)

                Spacer()

                Text("\(viewModel.screenshots.count)")
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.themeSecondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding()
            .background(Color.themeSurface)

            Divider()
                .background(Color.themeDivider)
            
            if viewModel.screenshots.isEmpty {
                TimelineEmptyView()
            } else {
                // Screenshot list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.screenshots) { screenshot in
                            ScreenshotRow(
                                screenshot: screenshot,
                                isSelected: selectedScreenshotId == screenshot.id,
                                onTap: {
                                    selectedScreenshotId = screenshot.id
                                }
                            )
                        }
                    }
                    .padding()
                }
                
                Divider()
                    .background(Color.themeDivider)
                
                // Summarize button at bottom
                Button(action: {
                    Task {
                        await summarizeToNote()
                    }
                }) {
                    HStack(spacing: 10) {
                        if appState.isSummarizing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.body)
                        }
                        Text(appState.isSummarizing ? "Summarizing..." : "Summarize All")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.themeAccent)
                .controlSize(.large)
                .disabled(viewModel.screenshots.isEmpty || appState.isSummarizing)
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .background(Color.themeBackground)
    }
    
    /// Summarize all screenshots and add to note
    private func summarizeToNote() async {
        await appState.summarizeAndAddToNote(viewModel: viewModel)
    }
}

struct TimelineEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.themeSecondary)

            Text("No screenshots yet")
                .font(.headline)
                .foregroundStyle(Color.themeTextSecondary)

            VStack(spacing: 4) {
                Text("Press")
                    .foregroundStyle(Color.themeTextTertiary)

                Text("⌘⇧E")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(Color.themeText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.themeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("to capture")
                    .foregroundStyle(Color.themeTextTertiary)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.themeBackground)
    }
}

struct ScreenshotRow: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail - add cache-busting param to prevent stale images
            let imageURL = URL(string: "\(screenshot.imageUrl)?v=\(screenshot.id.uuidString)")
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 80, height: 60)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(Color.themeTextSecondary)
                        .frame(width: 80, height: 60)
                @unknown default:
                    EmptyView()
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTime(screenshot.createdAt))
                    .font(.callout.bold())
                    .foregroundStyle(Color.themeText)

                if let text = screenshot.rawText, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Source button
            Button(action: onTap) {
                Image(systemName: "arrow.up.right.circle")
                    .font(.title3)
                    .foregroundStyle(Color.themeAccent)
            }
            .buttonStyle(.plain)
            .help("View details")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.themeSelected : Color.themeCard)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    TimelinePanel(
        appState: AppState.shared,
        viewModel: SessionViewModel(sessionId: UUID()),
        selectedScreenshotId: .constant(nil)
    )
    .frame(width: 320, height: 600)
}
