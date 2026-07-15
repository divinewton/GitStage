//
//  SettingsView.swift
//  GitStage
//
//  App preferences: GitHub account, default clone location, and Git toolchain info.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var auth: GitHubAuthService
    @Bindable var store: RepositoryStore

    @State private var cloneLocationDisplay = CloneLocationSettings.displayPath

    var body: some View {
        Form {
            Section {
                if let session = auth.session {
                    LabeledContent("Signed in as") {
                        Text(session.login)
                    }

                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                    }
                } else {
                    Text("You are not signed in to GitHub.")
                        .foregroundStyle(.secondary)

                    Button("Sign In to GitHub…") {
                        Task { await auth.signIn() }
                    }
                    .disabled(auth.isSigningIn)
                }
            } header: {
                Text("GitHub Account")
            }

            Section {
                LabeledContent("Default clone location") {
                    Text(cloneLocationDisplay)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                        .frame(maxWidth: 260, alignment: .trailing)
                }

                Button("Change Clone Location…") {
                    Task {
                        await store.configureDefaultCloneLocationFromPanel()
                        refreshCloneLocationDisplay()
                    }
                }
            } header: {
                Text("Repositories")
            } footer: {
                Text("New clones are stored in a GitStage folder inside the location you choose.")
            }

            Section {
                if let customEditorName = CustomEditorSettings.displayName {
                    LabeledContent("Custom editor") {
                        Text(customEditorName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button("Change Custom Editor…") {
                        _ = CustomEditorSettings.promptForCustomEditor()
                    }

                    Button("Remove Custom Editor", role: .destructive) {
                        CustomEditorSettings.clearCustomEditor()
                    }
                } else {
                    Text("No custom editor configured.")
                        .foregroundStyle(.secondary)

                    Button("Choose Custom Editor…") {
                        _ = CustomEditorSettings.promptForCustomEditor()
                    }
                }
            } header: {
                Text("External Editors")
            } footer: {
                Text("GitStage detects common editors automatically. Choose a custom app if yours is not listed in Open In menus.")
            }

            Section {
                LabeledContent("Git executable") {
                    Text(gitExecutableDisplay)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(maxWidth: 260, alignment: .trailing)
                }

                if !GitInstallSupport.isGitAvailable {
                    Button("Install Command Line Tools") {
                        GitInstallSupport.installCommandLineTools()
                    }
                    Button("Download Git…") {
                        GitInstallSupport.openGitDownloadPage()
                    }
                }
            } header: {
                Text("Git")
            } footer: {
                Text("GitStage uses the first Git binary it finds from Xcode, Command Line Tools, or Homebrew.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
        .navigationTitle("Settings")
        .onAppear(perform: refreshCloneLocationDisplay)
    }

    private var gitExecutableDisplay: String {
        GitLocator.locateGitExecutable()?.path ?? "Not found"
    }

    private func refreshCloneLocationDisplay() {
        cloneLocationDisplay = CloneLocationSettings.displayPath
    }
}

#Preview {
    SettingsView(auth: .previewSignedIn, store: RepositoryStore(auth: .previewSignedIn))
}
