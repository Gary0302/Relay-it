import SwiftUI

/// A dedicated view for displaying AI-generated summaries in a clean, readable format
struct AISummaryCard: View {
    let entity: ExtractedInfo
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onFieldTap: ((String, String) -> Void)?
    
    @State private var isExpanded = true
    
    // Extract data from entity
    private var title: String {
        if let title = entity.data["suggested_title"]?.value as? String, !title.isEmpty {
            return title
        }
        return "AI Summary"
    }
    
    private var summary: String {
        if let summary = entity.data["condensed_summary"]?.value as? String {
            return summary
        }
        return entity.data["summary"]?.value as? String ?? ""
    }
    
    private var keywords: [String] {
        // Try to extract keywords from data
        if let keywordsStr = entity.data["keywords"]?.value as? String {
            return keywordsStr.components(separatedBy: ", ")
        }
        return []
    }
    
    private var highlights: [(String, String)] {
        entity.dataKeys.filter { $0.hasPrefix("highlight") }
            .sorted()
            .compactMap { key -> (String, String)? in
                guard let value = entity.data[key]?.value as? String else { return nil }
                return (key, value)
            }
    }
    
    private var recommendations: [(String, String)] {
        entity.dataKeys.filter { $0.hasPrefix("recommendation") }
            .sorted()
            .compactMap { key -> (String, String)? in
                guard let value = entity.data[key]?.value as? String else { return nil }
                return (key, value)
            }
    }
    
    private var suggestedQueries: [String] {
        if let queriesStr = entity.data["suggested_queries"]?.value as? String {
            return queriesStr.components(separatedBy: ", ")
        }
        return []
    }
    
    private var itemCount: String {
        entity.data["item_count"]?.value as? String ?? ""
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection
            
            if isExpanded {
                Divider()
                    .background(Color.themeDivider)
                
                // Summary section
                if !summary.isEmpty {
                    summarySection
                }
                
                // Keywords section
                if !keywords.isEmpty {
                    keywordsSection
                }
                
                // Highlights section
                if !highlights.isEmpty {
                    highlightsSection
                }
                
                // Recommendations section
                if !recommendations.isEmpty {
                    recommendationsSection
                }
                
                // Suggested Queries section
                if !suggestedQueries.isEmpty {
                    suggestedQueriesSection
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
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            // Checkbox
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.themeAccent : Color.themeTextSecondary)
            }
            .buttonStyle(.plain)
            
            // AI badge
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("AI Summary")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.themeAccent.opacity(0.2))
            .foregroundStyle(Color.themeAccent)
            .clipShape(Capsule())
            
            Spacer()
            
            // Item count if available
            if !itemCount.isEmpty {
                Text("\(itemCount) items")
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary)
            }
            
            // Expand/collapse
            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Title & Summary
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.themeText)
            
            // Summary text
            Text(summary)
                .font(.callout)
                .foregroundStyle(Color.themeTextSecondary)
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Keywords
    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keywords", systemImage: "tag")
                .font(.caption.bold())
                .foregroundStyle(Color.themeTextSecondary)
            
            FlowLayout(spacing: 6) {
                ForEach(keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.themeAccent.opacity(0.1))
                        .foregroundStyle(Color.themeAccent)
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Highlights
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Highlights", systemImage: "sparkle")
                .font(.caption.bold())
                .foregroundStyle(Color.themeTextSecondary)
            
            ForEach(highlights, id: \.0) { key, value in
                ClickableRow(
                    icon: "circle.fill",
                    text: value,
                    onTap: { onFieldTap?(key, value) }
                )
            }
        }
    }
    
    // MARK: - Recommendations
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recommendations", systemImage: "lightbulb")
                .font(.caption.bold())
                .foregroundStyle(Color.themeTextSecondary)
            
            ForEach(recommendations, id: \.0) { key, value in
                ClickableRow(
                    icon: "arrow.right.circle",
                    text: value,
                    onTap: { onFieldTap?(key, value) }
                )
            }
        }
    }
    
    // MARK: - Suggested Queries
    private var suggestedQueriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ask about", systemImage: "bubble.left.and.bubble.right")
                .font(.caption.bold())
                .foregroundStyle(Color.themeTextSecondary)
            
            ForEach(suggestedQueries, id: \.self) { query in
                Button(action: { onFieldTap?("suggested_query", query) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                        Text(query)
                            .font(.callout)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.themeAccent.opacity(0.08))
                    .foregroundStyle(Color.themeAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Helper Views

struct ClickableRow: View {
    let icon: String
    let text: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 6))
                    .foregroundStyle(Color.themeAccent)
                    .frame(width: 12, height: 16)
                
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Color.themeText)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption2)
                    .foregroundStyle(Color.themeAccent.opacity(0.6))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.themeAccent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

#Preview {
    VStack {
        AISummaryCard(
            entity: ExtractedInfo(
                id: UUID(),
                sessionId: UUID(),
                screenshotIds: [],
                entityType: "ai-summary",
                data: [
                    "suggested_title": AnyCodable("Hackathon Debugging & UI Refinement"),
                    "condensed_summary": AnyCodable("This session captures debugging and UI refinement during a hackathon project."),
                    "keywords": AnyCodable("SwiftUI, Debugging, UI, Hackathon"),
                    "highlight_1": AnyCodable("UI Styling: Refining button appearance"),
                    "highlight_2": AnyCodable("Deployment: Successfully deploying via Vercel"),
                    "recommendation_1": AnyCodable("Prioritize consistent UI theming"),
                    "recommendation_2": AnyCodable("Document code changes with clear commit messages"),
                    "item_count": AnyCodable("7")
                ]
            ),
            isSelected: false,
            onToggleSelect: {},
            onFieldTap: nil
        )
    }
    .padding()
    .background(Color.themeBackground)
}
