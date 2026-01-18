//
//  LoginView.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import SwiftUI

struct LoginView: View {
    @StateObject private var auth = AuthService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Background
            Color.themeBackground
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Login Card
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)

                        Text("Relay it!")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.themeText)

                        Text(isSignUp ? "Create your account" : "Welcome back")
                            .font(.subheadline)
                            .foregroundStyle(Color.themeTextSecondary)
                            .id(isSignUp ? "signup" : "signin")
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }

                    // Form Fields
                    VStack(spacing: 20) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.themeText)

                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(Color.themeText)
                                .padding(12)
                                .background(Color.themeInput)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.themeBorder, lineWidth: 1)
                                )
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.themeText)

                            SecureField("Enter your password", text: $password)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(Color.themeText)
                                .padding(12)
                                .background(Color.themeInput)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.themeBorder, lineWidth: 1)
                                )
                                .textContentType(isSignUp ? .newPassword : .password)
                        }

                        // Error Message
                        if let error = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(error)
                            }
                            .font(.caption)
                            .foregroundStyle(Color.themeError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Submit Button
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.body.weight(.semibold))
                                .id(isSignUp ? "btn-signup" : "btn-signin")
                                .transition(.scale.combined(with: .opacity))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(email.isEmpty || password.isEmpty ? Color.themeSecondary : Color.themeAccent)
                    )
                    .foregroundStyle(.white)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSignUp)

                    // Toggle Sign Up / Sign In
                    HStack(spacing: 4) {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundStyle(Color.themeTextSecondary)

                        Button(isSignUp ? "Sign In" : "Create Account") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isSignUp.toggle()
                                errorMessage = nil
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.themeAccent)
                        .fontWeight(.medium)
                    }
                    .font(.callout)
                }
                .padding(40)
                .frame(width: 380)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.themeCard)
                        .shadow(color: Color.themeText.opacity(0.08), radius: 20, y: 8)
                )

                Spacer()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isSignUp {
                    try await auth.signUp(email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
}
