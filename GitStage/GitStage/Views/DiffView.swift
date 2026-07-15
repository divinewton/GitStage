//
//  DiffView.swift
//  GitStage
//
//  Renders parsed diff hunks with line numbers and hunk headers.
//

import SwiftUI

struct DiffView: View {
    let hunks: [DiffHunk]
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading diff…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hunks.isEmpty {
                ContentUnavailableView(
                    "No Diff",
                    systemImage: "doc.text",
                    description: Text("This file has no diff output to display.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(hunks) { hunk in
                            DiffHunkView(hunk: hunk)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }
}

private struct DiffHunkView: View {
    let hunk: DiffHunk

    private var lineNumberWidth: CGFloat {
        let maxLine = hunk.lines.reduce(0) { partial, line in
            max(partial, line.oldLineNumber ?? 0, line.newLineNumber ?? 0)
        }
        let digits = max(2, String(maxLine).count)
        return CGFloat(digits * 9 + 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .separatorColor).opacity(0.22))

            ForEach(hunk.lines) { line in
                DiffLineRow(line: line, lineNumberWidth: lineNumberWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 12)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let lineNumberWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            lineNumberText(line.oldLineNumber)
            lineNumberText(line.newLineNumber)

            Text(gutterSymbol)
                .frame(width: 18, alignment: .center)
                .foregroundStyle(gutterColor)

            HStack(spacing: 4) {
                Text(line.text.isEmpty ? " " : line.text)

                if line.noNewlineAtEnd {
                    NoNewlineMarker()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private func lineNumberText(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: lineNumberWidth, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var gutterSymbol: String {
        switch line.type {
        case .addition: "+"
        case .deletion: "-"
        case .context: " "
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .addition:
            Color(nsColor: .systemGreen).opacity(0.16)
        case .deletion:
            Color(nsColor: .systemRed).opacity(0.16)
        case .context:
            Color.clear
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .addition: Color(nsColor: .systemGreen)
        case .deletion: Color(nsColor: .systemRed)
        case .context: Color.secondary.opacity(0.6)
        }
    }
}

private struct NoNewlineMarker: View {
    private let markerColor = Color(nsColor: .systemRed)

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "nosign")
                .font(.caption2.weight(.semibold))

            Image(systemName: "arrow.turn.down.left")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(markerColor)
        .help("No newline at end of file")
    }
}

#Preview {
    DiffView(
        hunks: RepositoryStore.previewWithChanges.currentDiff,
        isLoading: false
    )
    .frame(width: 640, height: 320)
}
