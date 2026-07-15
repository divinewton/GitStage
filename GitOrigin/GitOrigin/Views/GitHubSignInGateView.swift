//
//  GitHubSignInGateView.swift
//  GitOrigin
//
//  Full-window sign-in UI using GitHub OAuth device flow.
//

import SwiftUI

struct GitHubSignInGateView: View {
    @Bindable var auth: GitHubAuthService
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                Text("Welcome to GitOrigin")
                    .font(.title.weight(.semibold))

                Text("Sign in with GitHub to open repositories and sync your work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            gateContent
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onChange(of: auth.lastError) { _, error in
            if let error {
                errorMessage = error.errorDescription ?? "Sign-in failed."
                showErrorAlert = true
            }
        }
        .alert("Sign-In Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                auth.clearLastError()
            }
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private var gateContent: some View {
        if let pending = auth.pendingDeviceAuthorization {
            VStack(spacing: 12) {
                Text("Enter this code on GitHub:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(pending.userCode)
                    .font(.largeTitle.monospaced().weight(.bold))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button("Open GitHub") {
                        auth.openDeviceVerificationInBrowser(pending)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Try Again") {
                        auth.cancelSignIn()
                        Task { await auth.signIn() }
                    }
                    .buttonStyle(.bordered)
                }

                if auth.isSigningIn {
                    ProgressView("Waiting for authorization…")
                        .controlSize(.regular)
                }
            }
        } else {
            Button {
                Task { await auth.signIn() }
            } label: {
                Label("Sign in with GitHub", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(auth.isSigningIn)

            if auth.isSigningIn {
                ProgressView("Starting sign-in…")
            }
        }
    }
}

#Preview {
    GitHubSignInGateView(auth: GitHubAuthService())
}
