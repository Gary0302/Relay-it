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
                    
                    // Extracted Information section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Extracted Information", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(Color.themeText)
                            
                            Spacer()
                            
                            if !relatedEntities.isEmpty || (screenshot.rawText != nil && !screenshot.rawText!.isEmpty) {
                                Button(action: addToNote) {
                                    HStack(spacing: 4) {
                                        Image(systemName: addedToNote ? "checkmark" : "doc.badge.plus")
                                        Text(addedToNote ? "Added!" : "Add to Note")
                                    }
                                    .font(.callout.weight(.medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(addedToNote ? Color.themeSuccess : Color.themeAccent)
                                .disabled(addedToNote)
                            }
                        }
                        
                        if relatedEntities.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.themeTextTertiary)
                                Text("No analysis available yet. The AI may still be processing this screenshot.")
                                    .font(.callout)
                                    .foregroundStyle(Color.themeTextSecondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(relatedEntities) { entity in
                                AnalysisCard(entity: entity)
                            }
                        }
                    }
                    .padding()
                    .background(Color.themeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Raw text (collapsible, secondary)
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
                        Text("Raw Text")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.themeTextTertiary)
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
        if let entity = relatedEntities.first {
            let summary = entity.getString("summary") ?? ""
            let intent = entity.getString("user_intent")
            let title = entity.getString("title")
            viewModel.addAnalysisToNote(summary: summary, userIntent: intent, title: title)
        } else if let rawText = screenshot.rawText, !rawText.isEmpty {
            viewModel.appendToNote("## Screenshot \(screenshot.orderIndex + 1)\n\n\(rawText)")
        } else {
            return
        }
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
    
    private var displayAttributes: [(key: String, value: String)] {
        let skipKeys: Set<String> = ["title", "summary", "category", "user_intent", "is_comparison", "decision_point", "related_topics"]
        return entity.data
            .filter { !skipKeys.contains($0.key) }
            .compactMap { key, value -> (key: String, value: String)? in
                guard let str = value.value as? String, !str.isEmpty else { return nil }
                return (key: key.replacingOccurrences(of: "_", with: " ").capitalized, value: str)
            }
            .sorted { $0.key < $1.key }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category + Title row
            HStack(spacing: 8) {
                if let type = entity.entityType, !type.isEmpty {
                    Text(type.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.themeAccent.opacity(0.15))
                        .foregroundStyle(Color.themeAccent)
                        .clipShape(Capsule())
                }
                
                if let title = entity.getString("title"), !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.themeText)
                }
            }
            
            // Summary
            if let summary = entity.getString("summary"), !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Color.themeTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // User Intent
            if let intent = entity.getString("user_intent"), !intent.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "target")
                        .font(.caption2)
                        .foregroundStyle(Color.themeAccent)
                        .padding(.top, 2)
                    Text(intent)
                        .font(.caption.italic())
                        .foregroundStyle(Color.themeText)
                }
            }
            
            // Additional extracted attributes
            if !displayAttributes.isEmpty {
                Divider()
                    .background(Color.themeDivider)
                
                ForEach(displayAttributes, id: \.key) { attr in
                    HStack(alignment: .top, spacing: 8) {
                        Text(attr.key)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.themeTextTertiary)
                            .frame(width: 80, alignment: .trailing)
                        
                        Text(attr.value)
                            .font(.caption)
                            .foregroundStyle(Color.themeText)
                            .textSelection(.enabled)
                        
                        Spacer()
                    }
                }
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

