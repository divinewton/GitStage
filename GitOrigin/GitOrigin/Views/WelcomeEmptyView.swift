//
//  WelcomeEmptyView.swift
//  GitOrigin
//
//  Full-window welcome shown before any repository has been added.
//

import AppKit
import SwiftUI

struct WelcomeEmptyView: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 28) {
                appIcon
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)

                VStack(spacing: 10) {
                    Text("Welcome to GitOrigin")
                        .font(.largeTitle.weight(.semibold))

                    Text("Add a repository to review changes, commit, and sync with GitHub.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                RepositoryAddMenu(store: store) {
                    Text("Add Repository")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.72))
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
        } else {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 96, height: 96)
        }
    }
}
