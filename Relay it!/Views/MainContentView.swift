//
//  MainContentView.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

/// Main content view with sidebar + center note editor
struct MainContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var auth = AuthService.shared
    
    @State private var isSidebarVisible = true
    @State private var isScreenshotPanelVisible = false
    @State private var selectedScreenshotId: UUID?
    @State private var showingScreenshotDetail = false
    
    private let sidebarWidth: CGFloat = 260
    private let screenshotPanelWidth: CGFloat = 300
    
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
        HStack(spacing: 0) {
            // Left sidebar (sessions)
            if isSidebarVisible {
                SessionSidebar(
                    appState: appState,
                    auth: auth,
                    onCollapse: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSidebarVisible = false
                        }
                    }
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))
                
                Divider()
                    .background(Color.themeDivider)
            }
            
            // Center: main note area
            VStack(spacing: 0) {
                // Top header bar
                sessionHeader
                
                Divider()
                    .background(Color.themeDivider)
                
                // Session content
                if let sessionId = appState.currentSessionId {
                    SessionContentView(
                        appState: appState,
                        sessionId: sessionId,
                        isScreenshotPanelVisible: $isScreenshotPanelVisible,
                        selectedScreenshotId: $selectedScreenshotId,
                        showingScreenshotDetail: $showingScreenshotDetail,
                        screenshotPanelWidth: screenshotPanelWidth
                    )
                    .id(sessionId)
                } else {
                    NoSessionView(appState: appState)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await appState.loadSessions()
        }
    }
    
    private var sessionHeader: some View {
        HStack(spacing: 12) {
            // Sidebar toggle (show when sidebar is hidden)
            if !isSidebarVisible {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarVisible = true
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.body)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Show sidebar")
            }
            
            // App logo + session name
            HStack(spacing: 8) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                
                if let session = appState.currentSession {
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(Color.themeText)
                        .lineLimit(1)
                } else {
                    Text("Relay it!")
                        .font(.headline)
                        .foregroundStyle(Color.themeText)
                }
            }
            
            Spacer()
            
            // Screenshot panel toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isScreenshotPanelVisible.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack")
                        .font(.callout)
                    if let sessionId = appState.currentSessionId {
                        ScreenshotCountBadge(appState: appState, sessionId: sessionId)
                    }
                }
                .foregroundStyle(isScreenshotPanelVisible ? Color.themeAccent : Color.themeTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Toggle screenshots panel")
            
            // Capture button
            Button(action: {
                Task { await appState.captureScreenshot() }
            }) {
                Image(systemName: "camera.fill")
                    .font(.callout)
                    .foregroundStyle(Color.themeAccent)
            }
            .buttonStyle(.plain)
            .help("Capture screenshot (Cmd+Shift+E)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.themeSurface)
    }
}

/// Displays screenshot count; needs session context to observe the viewModel
struct ScreenshotCountBadge: View {
    @ObservedObject var appState: AppState
    let sessionId: UUID
    
    var body: some View {
        // Badge will be updated via the SessionContentView's viewModel
        // For now show a simple indicator
        EmptyView()
    }
}

struct SessionContentView: View {
    @ObservedObject var appState: AppState
    let sessionId: UUID
    @Binding var isScreenshotPanelVisible: Bool
    @Binding var selectedScreenshotId: UUID?
    @Binding var showingScreenshotDetail: Bool
    let screenshotPanelWidth: CGFloat
    
    @StateObject private var viewModel: SessionViewModel
    
    init(
        appState: AppState,
        sessionId: UUID,
        isScreenshotPanelVisible: Binding<Bool>,
        selectedScreenshotId: Binding<UUID?>,
        showingScreenshotDetail: Binding<Bool>,
        screenshotPanelWidth: CGFloat
    ) {
        self.appState = appState
        self.sessionId = sessionId
        self._isScreenshotPanelVisible = isScreenshotPanelVisible
        self._selectedScreenshotId = selectedScreenshotId
        self._showingScreenshotDetail = showingScreenshotDetail
        self.screenshotPanelWidth = screenshotPanelWidth
        self._viewModel = StateObject(wrappedValue: SessionViewModel(sessionId: sessionId))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Main note panel (full height)
            ChatPanel(
                appState: appState,
                viewModel: viewModel,
                selectedScreenshotId: $selectedScreenshotId
            )
            .frame(maxWidth: .infinity)
            
            // Right: Screenshots panel (toggleable)
            if isScreenshotPanelVisible {
                Divider()
                    .background(Color.themeDivider)
                
                TimelinePanel(
                    appState: appState,
                    viewModel: viewModel,
                    selectedScreenshotId: $selectedScreenshotId
                )
                .frame(width: screenshotPanelWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
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
        .alert(isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Alert(
                title: Text("Session Error"),
                message: Text(viewModel.error ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct NoSessionView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(Color.themeSecondary)

            Text("Welcome to Relay it!")
                .font(.title2.bold())
                .foregroundStyle(Color.themeText)

            Text("Start a new chat to begin capturing and analyzing")
                .foregroundStyle(Color.themeTextSecondary)

            Button(action: {
                Task {
                    await appState.createSession(name: "New Session")
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New Session")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
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
