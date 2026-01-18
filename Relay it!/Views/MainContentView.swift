//
//  MainContentView.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

/// Main content view with split panels
struct MainContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var auth = AuthService.shared
    
    @State private var isSidebarVisible = true
    @State private var selectedScreenshotId: UUID?
    @State private var showingScreenshotDetail = false
    
    private let sidebarWidth: CGFloat = 320
    
    var body: some View {
        Group {
            if auth.isLoading {
                LoadingView()
            } else if !auth.isAuthenticated {
                LoginView()
            } else {
                authenticatedContent
            }
        }
        .alert(item: $appState.error) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.errorDescription ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .toast(isShowing: $appState.showCaptureSuccess, message: "Capture successful!")
    }
    
    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            // Top toolbar with logout
            HStack(spacing: 12) {
                // App icon and title
                HStack(spacing: 8) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)

                    Text("Relay it!")
                        .font(.title2.bold())
                        .foregroundStyle(Color.themeText)
                }

                Spacer()
                
                // Sidebar toggle
                Button(action: { withAnimation { isSidebarVisible.toggle() } }) {
                    Image(systemName: "sidebar.right")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSidebarVisible ? Color.themeAccent : Color.themeTextSecondary)
                .help("Toggle Screenshots Sidebar")

                Divider()
                    .frame(height: 20)

                // User account name
                if let user = auth.currentUser {
                    Text(accountName(from: user.email))
                        .font(.callout)
                        .foregroundStyle(Color.themeTextSecondary)
                }

                // Logout button
                Button("Logout") {
                    Task {
                        try? await auth.signOut()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(Color.themeAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.themeSurface)
            
            Divider()
            
            // Session tabs
            SessionTabBar(appState: appState)
            
            Divider()
            
            // Main content
            if let sessionId = appState.currentSessionId {
                SessionContentView(
                    appState: appState,
                    sessionId: sessionId,
                    isSidebarVisible: $isSidebarVisible,
                    selectedScreenshotId: $selectedScreenshotId,
                    showingScreenshotDetail: $showingScreenshotDetail,
                    sidebarWidth: sidebarWidth
                )
                .id(sessionId)  // Force rebuild when session changes
            } else {
                NoSessionView(appState: appState)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await appState.loadSessions()
        }
    }

    /// Extract account name from email (part before @)
    private func accountName(from email: String?) -> String {
        guard let email = email,
              let atIndex = email.firstIndex(of: "@") else {
            return "Account"
        }
        let name = String(email[..<atIndex])
        return name.capitalized
    }
}

struct SessionContentView: View {
    @ObservedObject var appState: AppState
    let sessionId: UUID
    @Binding var isSidebarVisible: Bool
    @Binding var selectedScreenshotId: UUID?
    @Binding var showingScreenshotDetail: Bool
    let sidebarWidth: CGFloat
    
    @StateObject private var viewModel: SessionViewModel
    
    init(
        appState: AppState,
        sessionId: UUID,
        isSidebarVisible: Binding<Bool>,
        selectedScreenshotId: Binding<UUID?>,
        showingScreenshotDetail: Binding<Bool>,
        sidebarWidth: CGFloat
    ) {
        self.appState = appState
        self.sessionId = sessionId
        self._isSidebarVisible = isSidebarVisible
        self._selectedScreenshotId = selectedScreenshotId
        self._showingScreenshotDetail = showingScreenshotDetail
        self.sidebarWidth = sidebarWidth
        self._viewModel = StateObject(wrappedValue: SessionViewModel(sessionId: sessionId))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Content Area (Summary + Chat)
            SummaryPanel(
                appState: appState,
                viewModel: viewModel,
                selectedScreenshotId: $selectedScreenshotId
            )
            .frame(maxWidth: .infinity) // Take remaining space
            
            // Right Sidebar - Timeline
            if isSidebarVisible {
                Divider()
                    .background(Color.themeDivider)
                
                TimelinePanel(
                    appState: appState,
                    viewModel: viewModel,
                    selectedScreenshotId: $selectedScreenshotId
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .trailing))
            }
        }
        .task {
            await viewModel.loadData()
        }
        .onChange(of: selectedScreenshotId) { oldValue, newValue in
            if newValue != nil {
                showingScreenshotDetail = true
            }
        }
        .sheet(isPresented: $showingScreenshotDetail) {
            if let screenshotId = selectedScreenshotId,
               let screenshot = viewModel.screenshot(for: screenshotId) {
                ScreenshotDetailModal(
                    screenshot: screenshot,
                    viewModel: viewModel,
                    isPresented: $showingScreenshotDetail
                )
            }
        }
    }
}



struct NoSessionView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(Color.themeSecondary)

            Text("No Session Selected")
                .font(.title2)
                .foregroundStyle(Color.themeTextSecondary)

            Text("Create a new session to get started")
                .foregroundStyle(Color.themeTextTertiary)

            Button("Create Session") {
                Task {
                    await appState.createSession(name: "New Session")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.themeAccent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.themeBackground)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.themeAccent)

            Text("Loading...")
                .foregroundStyle(Color.themeTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.themeBackground)
    }
}

#Preview {
    MainContentView()
}
