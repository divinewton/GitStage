Project Specification: GitOrigin (macOS)

GitOrigin is a premium, lightweight, and blazing-fast Git desktop client built natively in SwiftUI for macOS. It aims to provide the perfect "Mac-first" alternative to resource-heavy Electron clients like GitHub Desktop.

**Document status:** Living outline. Phases include acceptance criteria so AI agents (and humans) can verify work before moving on.

---

## 1. Core Vision & Principles

**Mac-First Aesthetics:** Follows macOS Human Interface Guidelines (HIG) with natural vibrancy, proper split views, system-native typography, and native keyboard shortcuts. **Requires macOS 26 (Tahoe) or later** — the UI uses Liquid Glass exclusively; no legacy material fallbacks.

**Platform minimum:** `MACOSX_DEPLOYMENT_TARGET = 26.0`. Do not add `#available` guards or fallback styling for earlier macOS versions.

**Pure Native Performance:** Written entirely in Swift and SwiftUI. No web-views, no Electron wrapper, minimal memory footprint.

**Pragmatic Implementation:** Uses Apple's `Process` API to execute the system Git CLI, parsing stdout into structured Swift models. Avoid libgit2 for MVP — CLI Git is battle-tested, matches terminal behavior, and keeps scope small.

**Testability First:** Parsers and command wrappers are pure Swift with fixture-based unit tests. UI phases depend on tested backend code, not the reverse.

---

## 2. Architecture & Components

```
┌────────────────────────────────────────┐
│             User Interface             │  SwiftUI / NavigationSplitView
└───────────────────┬────────────────────┘
                    │ @Bindable / observation
┌───────────────────▼────────────────────┐
│         RepositoryStore                │  @Observable @MainActor state
└───────────────────┬────────────────────┘
                    │ async calls
┌───────────────────▼────────────────────┐
│            GitExecutor                 │  actor — all Process I/O off MainActor
└───────────────────┬────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
 GitStatusParser           GitDiffParser        pure structs, no I/O
```

### A. GitExecutor (`actor`)

Bridge between the app and `/usr/bin/git` (or Xcode CLT / Homebrew Git on `PATH`).

**Concurrency:** Implement as a Swift `actor`, not a class with detached tasks. The Xcode project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; an actor keeps subprocess work off the UI thread without boilerplate.

**Process invocation:** Set `executableURL` to the resolved Git binary and pass arguments via `Process.arguments`. **Do not shell-escape paths** — argument arrays handle spaces safely. Only use `/bin/sh -c` if unavoidable (it is not here).

**Working directory:** Set `currentDirectoryURL` to the repo root for every command.

**Git discovery:** Resolve the real Git binary by probing known paths (Command Line Tools, Xcode, Homebrew). **Never call `xcrun`** — it is blocked inside App Sandbox, and `/usr/bin/git` is a shim that delegates to `xcrun`.

**App Sandbox:** Disabled for GitOrigin. Sandboxed apps may only execute `/usr/bin/*`, where `git` is a shim that invokes `xcrun` (also blocked). A CLI-based Git client needs direct access to the Command Line Tools `git` binary.

**Error handling:** Non-zero exit codes plus stderr become typed `GitError` cases (e.g. `.notARepository`, `.mergeConflict`, `.authenticationFailed`, `.commandFailed(message:)`).

**Cancellation:** Long-running commands (`diff`, `fetch`) should respect `Task.checkCancellation()` so switching files or repos does not pile up work.

### B. RepositoryStore (`@Observable`, `@MainActor`)

Single source of truth for the open workspace. (Renamed from `RepositoryManager` to avoid confusion with `FileManager` and to signal store semantics.)

| Property | Type | Notes |
|----------|------|-------|
| `repoURL` | `URL?` | Root of the open repository |
| `repoBookmark` | `Data?` | Security-scoped bookmark for sandbox persistence |
| `changedFiles` | `[ChangedFile]` | Parsed from porcelain status |
| `currentBranch` | `String?` | From `git branch --show-current` |
| `selectedFile` | `ChangedFile?` | Stable selection via filepath id |
| `currentDiff` | `[DiffLine]` | Loaded lazily when selection changes |
| `isLoadingStatus` | `Bool` | Status refresh in flight |
| `isLoadingDiff` | `Bool` | Diff load in flight |
| `isCommitting` | `Bool` | Commit in flight |
| `lastError` | `GitError?` | User-presentable error surface |

**Refresh strategy:** On repo open, call `refreshStatus()` (status + branch in parallel). Load diff only for `selectedFile`. Debounced FSEvents watcher (~300 ms) triggers refresh; CMD+R forces immediate refresh.

### C. Data Models

Use **stable identifiers** so list selection survives refreshes.

```swift
enum FileStatus { case modified, added, deleted, untracked, renamed }

enum StagingState { case unstaged, staged, partiallyStaged }

struct ChangedFile: Identifiable, Hashable {
    var id: String { filepath }          // stable — not UUID()
    let filepath: String
    let status: FileStatus
    let stagingState: StagingState       // derived from porcelain XY columns
}

struct DiffLine: Identifiable, Hashable {
    let id: Int                          // line index within parsed diff
    let text: String
    let type: LineType                   // .addition, .deletion, .header, .context
}
```

**Porcelain parsing:** Use `git status --porcelain` (v1). Map the two status columns (index vs work tree) to `stagingState`. Example: ` M` → modified/unstaged, `M ` → modified/staged, `MM` → partiallyStaged.

### D. Recommended File Layout

```
GitOrigin/
├── App/
│   └── GitOriginApp.swift
├── Git/
│   ├── GitExecutor.swift
│   ├── GitError.swift
│   ├── GitStatusParser.swift
│   ├── GitDiffParser.swift
│   └── Models/ …
├── Store/
│   └── RepositoryStore.swift
├── Views/
│   ├── ContentView.swift
│   ├── SidebarView.swift
│   ├── CommitBoxView.swift
│   ├── ChangedFilesListView.swift
│   └── DiffView.swift
└── Utilities/
    ├── RepoAccessManager.swift        // bookmarks + security scope
    └── GitRepoWatcher.swift           // FSEvents debounce
```

### E. File Access & Bookmarks

GitOrigin runs **without App Sandbox** so it can execute the real Git binary from Command Line Tools or Homebrew. Repo access still uses standard macOS patterns:

1. Open repos via `NSOpenPanel` (directory, `canChooseDirectories = true`).
2. Create and persist a **security-scoped bookmark** (`RepoAccessManager`) for reopening repos across launches.
3. Store recent repo bookmarks in `UserDefaults`.

`ENABLE_USER_SELECTED_FILES = readwrite` remains set for future sandbox re-enablement if Git is bundled in-app.

---

## 3. UI & Layout Blueprint

Three-column `NavigationSplitView` (sidebar → content list → detail):

| Column | Role |
|--------|------|
| **1 — Sidebar** | Repo picker, current branch, changed-files list with status badges (M, A, D, ?), sticky **Commit Box** at bottom |
| **2 — Content** | Mode switcher: Changes / History / Branches (History & Branches are post-MVP placeholders initially) |
| **3 — Detail** | Unified diff for selected file; monospaced body font; green/red semantic highlights |

**Commit Box:** Summary field (required), optional description, primary button labeled `Commit to [branch]`.

**Empty states:** `ContentUnavailableView` when no repo is open or no changes exist.

**Diff performance:** Use `LazyVStack` inside `ScrollView`; parse and render incrementally. Cancel in-flight diff tasks when selection changes. For very large diffs (>5k lines), consider truncating with a "Show full diff" affordance in a later polish pass.

**Liquid Glass (required):** All chrome surfaces use Liquid Glass APIs — no `.regularMaterial` or manual vibrancy fallbacks.

| Surface | API |
|---------|-----|
| Sidebar / panels | `.glassEffect(.regular, in: RoundedRectangle(...))` inside `GlassEffectContainer` |
| Commit box / toolbars | `.glassEffect(.regular.tint(...))` or `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` |
| Grouped glass controls | Wrap siblings in `GlassEffectContainer(spacing:)`; use `glassEffectID(_:in:)` for morph transitions |
| Window chrome | Rely on system `NavigationSplitView` / toolbar glass; do not override with opaque backgrounds |

Reference: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

---

## 4. Phased Roadmap

Each phase lists **depends on**, **deliverables**, and **acceptance criteria**. Do not start a phase until its dependencies pass.

### Phase 0: Project Baseline ✓ (mostly complete)

**Deliverables:** macOS App target, deployment **macOS 26.0+** only, sandbox configured, Xcode 26+ toolchain.

**Acceptance criteria:**
- [ ] App builds and launches from Xcode
- [ ] Entitlements updated to user-selected **readwrite** before Phase 4

---

### Phase 1: Git Engine + Repo Access

**Depends on:** Phase 0

**Deliverables:**
- `GitExecutor` actor with `run(_ args: [String], in directory: URL) async throws -> GitCommandResult`
- Commands: `status --porcelain`, `branch --show-current`, `rev-parse --is-inside-work-tree`
- `GitStatusParser` + unit tests using checked-in fixture strings
- `RepoAccessManager`: open panel, bookmark create/resolve, access lifecycle
- `RepositoryStore` skeleton with `openRepo()`, `refreshStatus()`, error publishing

**Acceptance criteria:**
- [x] Unit tests pass for parser fixtures (renames, untracked, staged/unstaged)
- [x] Opening a valid repo populates `currentBranch` and `changedFiles` (debug UI in `ContentView`)
- [x] Opening a non-repo shows a clear error
- [x] Paths with spaces work (argument array, no shell)

**Efficiency note:** Building parsers + tests before UI avoids rework in Phase 2.

---

### Phase 2: Shell UI — Sidebar & Repo Chrome

**Depends on:** Phase 1

**Deliverables:**
- `NavigationSplitView` scaffold replacing placeholder `ContentView`
- Sidebar: open repo button, branch label, `ChangedFilesListView` with badges
- Column 2 placeholder ("Changes" selected)
- Column 3 placeholder ("Select a file")
- Empty states wired to `repoURL == nil` and `changedFiles.isEmpty`

**Acceptance criteria:**
- [ ] User can open a repo and see accurate file list with staging badges
- [ ] Selecting a file updates `selectedFile` (detail still placeholder)
- [ ] Layout matches three-column blueprint (fix prior "two-column" wording)

---

### Phase 3: Native Diff View

**Depends on:** Phase 2

**Deliverables:**
- `GitExecutor`: `diff --no-color` for unstaged, `diff --cached --no-color` for staged (pick based on `selectedFile.stagingState`)
- `GitDiffParser` + unit tests (unified diff fixtures)
- `DiffView` with lazy scrolling and semantic colors
- `RepositoryStore.loadDiff(for:)` with task cancellation

**Acceptance criteria:**
- [ ] Selecting a changed file shows correct colored diff
- [ ] Switching files quickly does not flash stale diffs
- [ ] Scrolling a multi-hundred-line diff remains responsive on ProMotion displays

---

### Phase 4: Staging & Commit

**Depends on:** Phase 3

**Deliverables:**
- Per-file stage/unstage actions (`git add -- path`, `git restore --staged -- path`)
- Optional "Stage All" / "Unstage All"
- `CommitBoxView` with validation (non-empty summary)
- Commit: `git commit -m "summary"` or `-m "summary" -m "body"` when description present
- Auto `refreshStatus()` after stage/unstage/commit
- Shortcuts: CMD+Enter (commit when commit box focused), CMD+Shift+S (stage selected), CMD+R (refresh)

**Acceptance criteria:**
- [ ] User can stage individual files, see badges update, view staged diff
- [ ] Commit succeeds with summary-only and summary+description
- [ ] After commit, changed list clears appropriately and branch label remains correct
- [ ] Failed commits show stderr message in UI

**Efficiency note:** Stage/unstage **before** commit matches real Git workflow and avoids a simplistic `git add .` that hides UX gaps.

---

### Phase 5: History & Branches (Post-MVP)

**Depends on:** Phase 4

**Deliverables:**
- `git log --oneline -n 50`, branch list, checkout (with dirty-tree warning)
- Column 2 mode switcher fully wired

---

### Phase 6: Remotes & Sync (Post-MVP)

**Depends on:** Phase 5

**Deliverables:**
- Fetch/pull/push, ahead/behind counts, progress UI (`isSyncing`)
- Credential helper relies on system Git / Keychain — no custom auth UI initially

---

## 5. macOS Integration & Polish

| Shortcut | Action |
|----------|--------|
| CMD+O | Open repository |
| CMD+R | Refresh status |
| CMD+Enter | Commit (when commit box focused) |
| CMD+Shift+S | Stage selected file(s) |

**Dark Mode:** Use semantic colors (`Color(nsColor: .textBackgroundColor)`, `.labelColor`, `.systemGreen`/`.systemRed` with opacity) — no hard-coded sRGB.

**Liquid Glass:** Use `.glassEffect()`, `GlassEffectContainer`, and `.buttonStyle(.glass)` throughout — this project does not support pre-Tahoe macOS.

**Accessibility:** Diff rows should be readable with Increase Contrast enabled; do not rely on color alone — optional `+`/`-` gutter markers.

---

## 6. Testing Strategy

| Layer | Approach |
|-------|----------|
| Parsers | XCTest fixtures from real `git` output samples in `GitOriginTests/Fixtures/` |
| GitExecutor | Integration tests marked optional (require Git on CI runner) |
| UI | SwiftUI Previews with mock `RepositoryStore` states; XCUITest deferred |

Run tests each phase before proceeding. Parser tests are the highest ROI.

---

## 7. Explicit Non-Goals (MVP)

- Embedded libgit2 / SwiftGit2
- Custom merge conflict editor
- GitHub API integration (PRs, issues)
- Multiple repos in one window (single-repo focus first)
- `git rebase -i` or visual history graph

---

## 8. Agent Guidelines

**You may:**
- Implement features as specified above
- Propose changes to this document when a better approach reduces risk or rework

**When implementing:**
1. Read this spec and inspect the Xcode target settings (sandbox, deployment target) first
2. Complete acceptance criteria for the current phase before starting the next
3. Prefer extending existing types over parallel implementations
4. Keep diffs minimal and phase-scoped

**Known spec revisions (from initial review):**
- Renamed `RepositoryManager` → `RepositoryStore`; `GitExecutor` is an `actor`
- Removed shell-escaping requirement (use `Process.arguments`)
- Added sandbox/bookmark phase gate and readwrite entitlement
- Added stable model IDs and explicit staging state
- Split monolithic Phase 1 into engine-first + UI phases with test gates
- Added staging granularity before commit; deferred History/Remotes to Phases 5–6
- Aligned roadmap wording with three-column UI (fixed Phase 2 inconsistency)
