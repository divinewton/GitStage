//
//  ExternalEditorDiscovery.swift
//  GitOrigin
//
//  Finds installed editors/IDEs and opens a repository folder in the chosen app.
//

import AppKit
import Foundation

struct ExternalEditor: Identifiable, Equatable {
    let id: String
    let name: String
    let applicationURL: URL
}

enum ExternalEditorDiscovery {
    private static let knownEditors: [(name: String, bundleID: String)] = [
        ("Antigravity IDE", "com.google.antigravity-ide"),
        ("Codex", "com.openai.codex"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Devin", "com.codeium.windsurf"),
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Visual Studio Code - Insiders", "com.microsoft.VSCodeInsiders"),
        ("Windsurf", "com.codeium.windsurf"),
        ("Xcode", "com.apple.dt.Xcode"),
        ("Zed", "dev.zed.Zed"),
        ("Zed Preview", "dev.zed.Zed-Preview"),
        ("IntelliJ IDEA", "com.jetbrains.intellij"),
        ("IntelliJ IDEA CE", "com.jetbrains.intellij.ce"),
        ("WebStorm", "com.jetbrains.webstorm"),
        ("PyCharm", "com.jetbrains.pycharm"),
        ("PyCharm CE", "com.jetbrains.pycharm.ce"),
        ("PhpStorm", "com.jetbrains.phpstorm"),
        ("GoLand", "com.jetbrains.goland"),
        ("RubyMine", "com.jetbrains.rubymine"),
        ("CLion", "com.jetbrains.clion"),
        ("Rider", "com.jetbrains.rider"),
        ("RustRover", "com.jetbrains.rustrover"),
        ("DataGrip", "com.jetbrains.datagrip"),
        ("DataSpell", "com.jetbrains.dataspell"),
        ("Aqua", "com.jetbrains.aqua"),
        ("Fleet", "com.jetbrains.fleet"),
        ("Android Studio", "com.google.android.studio"),
        ("Nova", "com.panic.Nova"),
        ("Sublime Text", "com.sublimetext.4"),
        ("Sublime Text", "com.sublimetext.3"),
        ("BBEdit", "com.barebones.bbedit"),
        ("TextMate", "com.macromates.TextMate"),
        ("Neovide", "com.neovide.neovide"),
        ("MacVim", "org.vim.MacVim"),
        ("Terminal", "com.apple.Terminal"),
    ]

    private static let wellKnownApplicationNames: [(name: String, appName: String)] = [
        ("Antigravity IDE", "Antigravity IDE.app"),
        ("Codex", "Codex.app"),
        ("Devin", "Devin.app"),
        ("Windsurf", "Windsurf.app"),
    ]

    static func availableEditors() -> [ExternalEditor] {
        var editors = installedEditors()
        if let custom = CustomEditorSettings.customEditor(),
           !editors.contains(where: { $0.applicationURL == custom.applicationURL }) {
            editors.append(custom)
        }
        return editors.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func installedEditors() -> [ExternalEditor] {
        var editors: [ExternalEditor] = []
        var seenPaths = Set<String>()

        func append(_ editor: ExternalEditor?) {
            guard let editor else { return }
            let path = editor.applicationURL.path
            guard seenPaths.insert(path).inserted else { return }
            editors.append(editor)
        }

        let workspace = NSWorkspace.shared
        var seenBundleIDs = Set<String>()

        for candidate in knownEditors {
            guard !seenBundleIDs.contains(candidate.bundleID),
                  let url = workspace.urlForApplication(withBundleIdentifier: candidate.bundleID) else {
                continue
            }
            seenBundleIDs.insert(candidate.bundleID)
            append(editor(for: url, preferredName: candidate.name))
        }

        for candidate in wellKnownApplicationNames {
            for root in applicationSearchRoots() {
                let url = root.appendingPathComponent(candidate.appName, isDirectory: true)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                append(editor(for: url, preferredName: candidate.name))
            }
        }

        return editors.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor
    @discardableResult
    static func chooseCustomEditor() -> ExternalEditor? {
        CustomEditorSettings.promptForCustomEditor()
    }

    static func editor(for applicationURL: URL, preferredName: String? = nil) -> ExternalEditor? {
        let standardized = applicationURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else { return nil }

        let bundle = Bundle(url: standardized)
        let bundleID = bundle?.bundleIdentifier ?? standardized.path
        let name = preferredName
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? standardized.deletingPathExtension().lastPathComponent

        return ExternalEditor(id: bundleID, name: name, applicationURL: standardized)
    }

    static func open(_ folderURL: URL, with editor: ExternalEditor) {
        openFiles([folderURL], with: editor)
    }

    static func openFile(_ fileURL: URL, with editor: ExternalEditor) {
        openFiles([fileURL], with: editor)
    }

    private static func applicationSearchRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    private static func openFiles(_ urls: [URL], with editor: ExternalEditor) {
        guard let url = urls.first else { return }

        if editor.id == "com.apple.Terminal" {
            openInTerminal(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        Task {
            _ = try? await NSWorkspace.shared.open(
                urls,
                withApplicationAt: editor.applicationURL,
                configuration: configuration
            )
        }
    }

    private static func openInTerminal(_ url: URL) {
        let directoryURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let path = shellEscapedPath(directoryURL.path)
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(path)'"
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private static func shellEscapedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
