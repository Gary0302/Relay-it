//
//  SummaryPanel.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

/// Left panel showing AI-generated summary with editable content
/// Left panel showing AI-generated summary with editable content
struct SummaryPanel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: SessionViewModel
    @Binding var selectedScreenshotId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.headline)
                    .foregroundStyle(Color.themeText)

                Spacer()

                if viewModel.isRegenerating || viewModel.isChatLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.themeAccent)
                }
            }
            .padding()
            .background(Color.themeSurface)
            
            Divider()
            
            // Main content: Note Editor
            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading...")
                    .tint(Color.themeAccent)
                Spacer()
            } else {
                NoteEditorView(
                    content: $viewModel.noteContent,
                    isSaving: viewModel.isNoteSaving
                )
            }
            
            Divider()
                .background(Color.themeDivider)

            // Chat input
            ChatInputView(
                message: $viewModel.chatInput,
                isLoading: viewModel.isChatLoading,
                selectedCount: viewModel.selectedEntityIds.count,
                onSend: {
                    Task {
                        await viewModel.sendChatMessage()
                    }
                }
            )
        }
        .background(Color.themeBackground)
    }
    
    // Generate a follow-up question based on the field
    private func generateFollowUpQuestion(key: String, value: String) -> String {
        let formattedKey = key.replacingOccurrences(of: "_", with: " ").capitalized
        
        if key.hasPrefix("recommendation") {
            return "Tell me more about: \(value)"
        } else if key.hasPrefix("highlight") {
            return "Can you explain this highlight: \(value)"
        } else if key == "suggested_title" {
            return "Why did you suggest the title '\(value)'?"
        } else {
            return "Tell me more about \(formattedKey): \(value)"
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color.themeSecondary)

            Text("No data yet")
                .font(.headline)
                .foregroundStyle(Color.themeTextSecondary)

            Text("Press ⌘⇧E to capture a screenshot")
                .font(.callout)
                .foregroundStyle(Color.themeTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.themeBackground)
    }
}

struct EntityCard: View {
    let entity: ExtractedInfo
    let isSelected: Bool
    let screenshots: [Screenshot]
    let onToggleSelect: () -> Void
    let onSourceTap: (UUID) -> Void
    let onFieldTap: ((String, String) -> Void)?
    
    @State private var showBreakdown = true  // Show all details by default
    
    // Extract key fields
    private var title: String {
        entity.data["title"]?.value as? String ?? 
        entity.data["name"]?.value as? String ?? 
        entity.entityType?.capitalized ?? "Item"
    }
    
    private var category: String {
        entity.data["category"]?.value as? String ?? 
        entity.entityType ?? "other"
    }
    
    private var summary: String {
        entity.data["summary"]?.value as? String ?? ""
    }
    
    // Show ALL fields (not filtering any out)
    private var allKeys: [String] {
        entity.dataKeys
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: checkbox + category tag + source links
            HStack {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.themeAccent : Color.themeTextSecondary)
                }
                .buttonStyle(.plain)
                
                // Category tag
                Text(category.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(categoryColor.opacity(0.15))
                    .foregroundStyle(categoryColor)
                    .clipShape(Capsule())
                
                Spacer()
                
                // Source screenshot thumbnails
                ForEach(screenshots.prefix(2)) { screenshot in
                    Button(action: { onSourceTap(screenshot.id) }) {
                        // Cache-busting with screenshot ID
                        let imageURL = URL(string: "\(screenshot.imageUrl)?v=\(screenshot.id.uuidString)")
                        AsyncImage(url: imageURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 32, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("View source")
                }
            }
            
            // Title - big and bold
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.themeText)
                .lineLimit(2)
            
            // Summary - brief description
            if !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Color.themeTextSecondary)
                    .lineLimit(showBreakdown ? nil : 2)
            }
            
            // User Intent - prominent display
            if let intent = entity.getString("user_intent"), !intent.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "target")
                        .foregroundStyle(Color.themeAccent)
                        .font(.caption)
                        .padding(.top, 2)
                    
                    Text(intent)
                        .font(.caption.italic())
                        .foregroundStyle(Color.themeText)
                }
                .padding(.top, 2)
            }
            
            // Breakdown button and details
            let displayKeys = allKeys.filter { 
                !["user_intent", "is_comparison", "decision_point", "related_topics"].contains($0) 
            }
            
            if !displayKeys.isEmpty {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showBreakdown.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(showBreakdown ? "Hide Details" : "Show Breakdown")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Color.themeAccent)
                }
                .buttonStyle(.plain)
                
                if showBreakdown {
                    Divider()
                        .background(Color.themeDivider)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Show specific context fields first if they exist
                        if let decision = entity.getString("decision_point") {
                            DetailRow(key: "Decision Point", value: decision)
                        }
                        
                        // Then show remaining keys
                        ForEach(displayKeys, id: \.self) { key in
                            DetailRow(key: formatKey(key), value: formatValue(entity.data[key]))
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.themeCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.themeAccent.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
    
    // Helper view for consistent rows
    private struct DetailRow: View {
        let key: String
        let value: String
        
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Text(key)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.themeTextSecondary)
                    .frame(width: 80, alignment: .trailing)
                
                Text(value)
                    .font(.callout)
                    .foregroundStyle(Color.themeText)
                    .textSelection(.enabled)
                
                Spacer()
            }
        }
    }
    
    private var categoryColor: Color {
        switch category.lowercased() {
        case "trip-planning": return .blue
        case "shopping": return .purple
        case "job-search": return .green
        case "research": return .indigo
        case "content-writing": return .orange
        case "productivity": return .cyan
        case "projects": return .pink
        case "general-planning": return .mint
        case "brainstorming": return .yellow
        case "study-guides": return .teal
        case "academic-research": return .brown
        default: return .gray
        }
    }
    
    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func formatValue(_ value: AnyCodable?) -> String {
        guard let value = value?.value else { return "—" }
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case let array as [Any]: return array.map { "\($0)" }.joined(separator: ", ")
        default: return "\(value)"
        }
    }
}

struct DataFieldRow: View {
    let key: String
    let value: AnyCodable?
    var isClickable: Bool = false
    var onTap: ((String, String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatKey(key))
                .font(.caption)
                .foregroundStyle(Color.themeTextSecondary)
                .frame(width: 80, alignment: .trailing)

            Text(formatValue(value))
                .font(.callout)
                .foregroundStyle(isClickable ? Color.themeAccent : Color.themeText)
                .textSelection(.enabled)
            
            if isClickable {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(Color.themeAccent.opacity(0.6))
            }

            Spacer()
        }
        .padding(.vertical, isClickable ? 4 : 0)
        .padding(.horizontal, isClickable ? 8 : 0)
        .background(
            isClickable ? Color.themeAccent.opacity(0.08) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            if isClickable, let onTap = onTap {
                onTap(key, formatValue(value))
            }
        }
    }
    
    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    private func formatValue(_ value: AnyCodable?) -> String {
        guard let value = value?.value else { return "—" }
        
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.map { "\($0)" }.joined(separator: ", ")
        default:
            return "\(value)"
        }
    }
}

#Preview {
    SummaryPanel(
        appState: AppState.shared,
        viewModel: SessionViewModel(sessionId: UUID()),
        selectedScreenshotId: .constant(nil)
    )
    .frame(width: 400, height: 600)
}
