//
//  ScreenshotDetailModal.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

/// Modal showing screenshot details with AI analysis and "Add to Note" functionality
struct ScreenshotDetailModal: View {
    let screenshot: Screenshot
    @ObservedObject var viewModel: SessionViewModel
    @Binding var isPresented: Bool
    
    @State private var editedText: String = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var addedToNote = false
    
    // Get entities associated with this screenshot
    private var relatedEntities: [ExtractedInfo] {
        viewModel.entities.filter { entity in
            entity.screenshotIds.contains(screenshot.id)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Screenshot Details")
                    .font(.headline)
                    .foregroundStyle(Color.themeText)

                Spacer()

                Text(formatDate(screenshot.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary)

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.themeSurface)

            Divider()
                .background(Color.themeDivider)
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Image - cache-busting with screenshot ID
                    let imageURL = URL(string: "\(screenshot.imageUrl)?v=\(screenshot.id.uuidString)")
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 200)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.themeTextSecondary)
                                .frame(height: 200)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    
                    // AI Analysis Section
                    if !relatedEntities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("AI Analysis", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(Color.themeText)
                                
                                Spacer()
                                
                                // Add to Note button
                                Button(action: addToNote) {
                                    HStack(spacing: 4) {
                                        Image(systemName: addedToNote ? "checkmark" : "doc.badge.plus")
                                        Text(addedToNote ? "Added!" : "Add to Note")
                                    }
                                    .font(.callout.weight(.medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(addedToNote ? Color.green : Color.themeAccent)
                                .disabled(addedToNote)
                            }
                            
                            ForEach(relatedEntities) { entity in
                                AnalysisCard(entity: entity)
                            }
                        }
                        .padding()
                        .background(Color.themeSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Divider()
                    
                    // OCR Text (collapsed by default)
                    DisclosureGroup {
                        if isEditing {
                            TextEditor(text: $editedText)
                                .font(.body)
                                .foregroundStyle(Color.themeText)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(Color.themeInput)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            HStack {
                                Spacer()
                                Button("Cancel") {
                                    editedText = screenshot.rawText ?? ""
                                    isEditing = false
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Save") {
                                    saveText()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.themeAccent)
                                .disabled(isSaving)
                            }
                        } else {
                            Text(screenshot.rawText ?? "No text extracted")
                                .font(.caption)
                                .foregroundStyle(screenshot.rawText == nil ? Color.themeTextSecondary : Color.themeText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack {
                                Spacer()
                                Button(action: { isEditing = true }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.themeAccent)
                            }
                        }
                    } label: {
                        Text("Extracted Text (OCR)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.themeTextSecondary)
                    }
                    .padding()
                    .background(Color.themeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
        }
        .frame(
            width: min((NSScreen.main?.frame.width ?? 1440) * 0.35, 500),
            height: min((NSScreen.main?.frame.height ?? 900) * 0.6, 600)
        )
        .background(Color.themeBackground)
        .onAppear {
            editedText = screenshot.rawText ?? ""
        }
    }
    
    private func addToNote() {
        guard let entity = relatedEntities.first else { return }
        
        let summary = entity.getString("summary") ?? ""
        let intent = entity.getString("user_intent")
        let title = entity.getString("title")
        
        viewModel.addAnalysisToNote(summary: summary, userIntent: intent, title: title)
        addedToNote = true
    }
    
    private func saveText() {
        isSaving = true
        Task {
            await viewModel.updateScreenshotText(screenshot.id, text: editedText)
            isEditing = false
            isSaving = false
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Analysis Card (for displaying entity data in modal)

private struct AnalysisCard: View {
    let entity: ExtractedInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            if let title = entity.getString("title"), !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.themeText)
            }
            
            // Summary
            if let summary = entity.getString("summary"), !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary)
            }
            
            // User Intent
            if let intent = entity.getString("user_intent"), !intent.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "target")
                        .font(.caption2)
                        .foregroundStyle(Color.themeAccent)
                    Text(intent)
                        .font(.caption.italic())
                        .foregroundStyle(Color.themeText)
                }
            }
            
            // Category badge
            if let type = entity.entityType, !type.isEmpty {
                Text(type.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.themeAccent.opacity(0.2))
                    .foregroundStyle(Color.themeAccent)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ScreenshotDetailModal(
        screenshot: Screenshot(
            sessionId: UUID(),
            imageUrl: "https://example.com/image.png",
            orderIndex: 0,
            rawText: "Sample extracted text from the screenshot..."
        ),
        viewModel: SessionViewModel(sessionId: UUID()),
        isPresented: .constant(true)
    )
}

