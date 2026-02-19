//
//  SessionSidebar.swift
//  Relay it!
//
//  ChatGPT-style left sidebar with session list, new chat button, and user account
//

import SwiftUI

struct SessionSidebar: View {
    @ObservedObject var appState: AppState
    @ObservedObject var auth: AuthService
    let onCollapse: () -> Void
    
    @State private var editingSessionId: UUID?
    @State private var editingName = ""
    @State private var isHoveringNewChat = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: New Session + Collapse
            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        await appState.createSession(name: "New Session")
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                        Text("New Session")
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHoveringNewChat ? Color.themeSurfaceHover : Color.clear)
                    )
                    .foregroundStyle(Color.themeText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringNewChat = $0 }
                
                Button(action: onCollapse) {
                    Image(systemName: "sidebar.left")
                        .font(.body)
                        .foregroundStyle(Color.themeTextSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse sidebar")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.themeDivider)
            
            // Session list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(sortedSessions) { session in
                        SessionSidebarRow(
                            session: session,
                            isSelected: session.id == appState.currentSessionId,
                            isEditing: editingSessionId == session.id,
                            editingName: $editingName,
                            onSelect: {
                                appState.currentSessionId = session.id
                            },
                            onDelete: {
                                Task {
                                    await appState.deleteSession(session.id)
                                }
                            },
                            onStartEdit: {
                                editingSessionId = session.id
                                editingName = session.name
                            },
                            onEndEdit: {
                                if !editingName.isEmpty && editingName != session.name {
                                    Task {
                                        await appState.renameSession(session.id, name: editingName)
                                    }
                                }
                                editingSessionId = nil
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            
            Divider()
                .background(Color.themeDivider)
            
            // Bottom: User account
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.themeTextSecondary)
                
                if let user = auth.currentUser {
                    Text(accountName(from: user.email))
                        .font(.callout)
                        .foregroundStyle(Color.themeText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    Task { try? await auth.signOut() }
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.callout)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Logout")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.themeSurface)
    }
    
    private var sortedSessions: [Session] {
        appState.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    private func accountName(from email: String?) -> String {
        guard let email = email,
              let atIndex = email.firstIndex(of: "@") else {
            return "Account"
        }
        return String(email[..<atIndex]).capitalized
    }
}

struct SessionSidebarRow: View {
    let session: Session
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onStartEdit: () -> Void
    let onEndEdit: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.themeAccent : Color.themeTextTertiary)
                .frame(width: 16)
            
            if isEditing {
                TextField("Session name", text: $editingName, onCommit: onEndEdit)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.themeText)
            } else {
                Text(session.name)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.themeText : Color.themeTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            if isHovering && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(Color.themeTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.themeAccent.opacity(0.12) : (isHovering ? Color.themeSurfaceHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Rename") { onStartEdit() }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    SessionSidebar(
        appState: AppState.shared,
        auth: AuthService.shared,
        onCollapse: {}
    )
    .frame(width: 260, height: 600)
}
