//
//  SessionTabBar.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

struct SessionTabBar: View {
    @ObservedObject var appState: AppState
    
    @State private var isCreatingSession = false
    @State private var newSessionName = ""
    @State private var editingSessionId: UUID?
    @State private var editingName = ""
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(appState.sessions) { session in
                    SessionTab(
                        session: session,
                        isSelected: session.id == appState.currentSessionId,
                        isEditing: editingSessionId == session.id,
                        editingName: $editingName,
                        onSelect: {
                            appState.currentSessionId = session.id
                        },
                        onClose: {
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
                
                // New session button
                if isCreatingSession {
                    NewSessionInput(
                        name: $newSessionName,
                        onCreate: {
                            if !newSessionName.isEmpty {
                                Task {
                                    await appState.createSession(name: newSessionName)
                                    newSessionName = ""
                                    isCreatingSession = false
                                }
                            }
                        },
                        onCancel: {
                            newSessionName = ""
                            isCreatingSession = false
                        }
                    )
                } else {
                    Button(action: { isCreatingSession = true }) {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .foregroundStyle(Color.themeTextSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.themeSurfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.themeSurface)
    }
}

struct SessionTab: View {
    let session: Session
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let onSelect: () -> Void
    let onClose: () -> Void
    let onStartEdit: () -> Void
    let onEndEdit: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("Session name", text: $editingName, onCommit: onEndEdit)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.themeText)
                    .frame(minWidth: 80)
            } else {
                Text(session.name)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.themeText : Color.themeTextSecondary)
                    .lineLimit(1)
            }

            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.themeAccent.opacity(0.15) : (isHovering ? Color.themeSurfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.themeAccent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle()) // Ensure entire area is tappable
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Rename") {
                onStartEdit()
            }
            
            Button(role: .destructive, action: onClose) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct NewSessionInput: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            TextField("New session", text: $name, onCommit: onCreate)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.themeText)
                .frame(width: 120)
                .focused($isFocused)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Color.themeTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.themeSurfaceHover)
        )
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    SessionTabBar(appState: AppState.shared)
}
