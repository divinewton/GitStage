# GitStage → GitHub Desktop Parity Roadmap

Living implementation plan for closing the gap between GitStage and GitHub Desktop. Update checkboxes as work ships.

**Last reviewed:** July 2026  
**Codebase baseline:** ~61 Swift files, single `GitStage` target, no XCTest target yet, `RepositoryStore` ~1,200 lines.

---

## How to use this document

1. Work top-to-bottom within each stage; do not skip foundation items.
2. Follow the existing rhythm: **Git layer → parsers/models → RepositoryStore → views → menus**.
3. Mark items `[x]` when shipped and merged; add notes inline if scope changes.
4. Timelines assume **part-time work** (~10–15 hrs/week). Full-time solo dev can compress by ~40%.

---

## Realistic expectations

GitStage already covers the daily happy path (stage → diff → commit → branch → sync). What remains is not one feature — it is **years of GitHub Desktop polish** compressed into sensible increments.

| Reality check | Adjustment |
|---------------|------------|
| Original 15–20 week total estimate assumed uninterrupted focus | Plan for **6–9 months part-time** to reach Stage 5; Stage 6 is ongoing |
| Partial line staging is "Stage 2" but hardest item in the whole roadmap | Treat as its own mini-project; do not block Stage 3 on it |
| Interactive rebase drag-and-drop | **Deferred** — high effort, low daily use; CLI-equivalent menu actions are enough for v1 |
| In-app 3-way merge editor | **Out of scope** — GitHub Desktop also sends you to an external editor |
| Windows port | **Out of scope** — macOS + App Sandbox is an intentional constraint |
| No test target today | Add tests early; they pay off before conflict parsing and patch-based staging |

---

## Current parity baseline

| Area | Status |
|------|--------|
| GitHub OAuth (device flow) | ✅ |
| Add / clone / create repo | ✅ |
| Repo sidebar catalog + search | ✅ |
| Changes: file-level stage/unstage, discard | ✅ |
| Unified diff viewer | ✅ |
| Commit (summary, body, co-authors) | ✅ |
| Branches: list, create, checkout, ahead/behind | ✅ |
| Fetch / pull / push (smart sync button) | ✅ |
| History list (50 commits, hash + subject) | ⚠️ Partial |
| PR list + open/create URL in browser | ⚠️ Partial |
| Open in Finder / editor | ✅ |
| Settings: account, clone path, editor, Git path | ⚠️ Basic |
| FSEvents auto-refresh | ✅ |
| Publish branch (`push -u`) | ⚠️ Backend only, no distinct UX |
| `mutateRepository()` scaffold | ⚠️ Exists, never wired |

---

## Architecture constraints (read before building)

These affect every stage. Resolve in **Foundation** before feature work.

### Detail column is working-tree only

`DiffDetailView` today only loads diffs for `selectedFile`. History commits, stashes, and PR previews all need a shared abstraction:

```
DiffDetailContext: workingTree | commit | stash | pullRequest
```

Without this refactor, Stage 1.1 and 1.2 will fight the existing UI.

### `mutateRepository` needs full refresh

Located in `RepositoryStore.swift` (~line 1094). Currently only calls `refreshStatus()`. Merge, stash, delete branch, and reset all need `refreshBranches()` + `refreshHistory()` too.

### `BranchSwitcherMenu` is a flat `Menu`

Fine for checkout; insufficient for delete, merge, and rebase actions. Plan a `BranchListSheet` or similar for destructive/power operations with context menus and confirmation dialogs.

### App Sandbox

All git operations use `git -C <path>` and security-scoped bookmarks via `RepoAccessManager`. New commands must follow the same pattern — no `currentDirectoryURL` on the repo.

### Sign-in gate

`RootView` requires GitHub sign-in before any repo UI. Local-only git identity settings (Stage 2.6) still matter because commits use `auth.commitAuthor` today (hardcoded noreply).

---

## Foundation (≈1 week part-time)

Do this once before Stage 1 feature work.

- [ ] **F1. XCTest target** — Add `GitStageTests` to `GitStage.xcodeproj`
  - [ ] `GitStatusParserTests` (fixture strings)
  - [ ] `GitDiffParserTests`
  - [ ] `GitLogParserTests`
  - [ ] `GitBranchParserTests`
  - *Estimate: 1–2 days*

- [ ] **F2. `DiffDetailContext`** — Unify detail column for working tree, commits, stashes
  - Touch: `RepositoryStore.swift`, `DiffDetailView.swift`, `WorkspaceColumnView.swift`
  - *Estimate: 1–2 days*

- [ ] **F3. Upgrade `mutateRepository`** — Configurable post-mutation refresh (status, branches, history)
  - *Estimate: 0.5 day*

- [ ] **F4. Flow sheet registry** — Extend `RepositoryFlowModifiers` for merge/delete/stash dialogs
  - Avoid scattering `.sheet` / `.alert` across views
  - *Estimate: 0.5 day*

**Foundation exit criteria:** Parser tests run in CI/Xcode; selecting a history row can theoretically reuse the detail column plumbing (even before `git show` exists).

---

## Stage 1 — Complete the core workflow

**Goal:** Real team work without Terminal for basic Git operations.  
**Estimate:** 3–4 weeks part-time (2 weeks full-time).  
**Depends on:** Foundation complete.

### Exit criteria

A developer can merge a feature branch, stash WIP before switching, inspect any commit's diff, and delete merged branches — all in-app.

---

### 1.1 History you can actually use

*Highest impact item in the entire roadmap.*

- [ ] `GitExecutor.log(branch:limit:)` — rich format (`%H`, `%an`, `%ad`, `%s`)
- [ ] `GitExecutor.show(sha:)` — `git show <sha> --patch`
- [ ] Extend `GitCommitEntry` or add `GitCommitDetail` (author, date, body)
- [ ] `GitShowParser` — metadata + delegate patch body to `GitDiffParser`
- [ ] `RepositoryStore`: `selectedCommit`, `selectCommit(_:)`, `loadCommitDiff()`
- [ ] `HistoryListView`: selectable rows, author + relative date
- [ ] `DiffDetailView`: commit header (author, date, message body) + `DiffView`
- [ ] Persist `historyBranchName` per repo (UserDefaults or catalog item metadata)
- [ ] Tests: `GitLogParserTests` (rich format), `GitShowParserTests`
- [ ] Menu: ensure "View History" per branch lands on correct commit list

*Estimate: 4–5 days part-time*

---

### 1.2 Stash

- [ ] `GitExecutor`: `stash push`, `stash list`, `stash show`, `stash apply`, `stash drop`
- [ ] Model: `GitStashEntry`
- [ ] `RepositoryStore`: `stashes`, `hasStash`, `stashAll()`, `restoreStash()`, `discardStash()`, `refreshStashes()`
- [ ] UI: "Stashed Changes" segment (second picker under Changes/History, matching GitHub Desktop)
- [ ] Stash diff in detail column via `DiffDetailContext.stash`
- [ ] Upgrade dirty-checkout dialog (`RepositoryFlowModifiers`) → **Commit / Stash / Bring changes**
- [ ] Tests: stash list parser fixture

*Estimate: 4–5 days part-time*

---

### 1.3 Merge into current branch

- [ ] `GitExecutor.merge(branch:)`
- [ ] `RepositoryStore.mergeBranch(named:)` via `mutateRepository`
- [ ] On `GitError.mergeConflict`: switch to Changes, show alert (full conflict UI is Stage 4)
- [ ] `MergeBranchSheet`: pick non-current local branch → confirm
- [ ] Entry point: `BranchSwitcherMenu` or `BranchListSheet`
- [ ] Post-merge refresh (branches, history, status)

*Estimate: 2–3 days part-time*

---

### 1.4 Delete branch

- [ ] `GitExecutor.deleteBranch(_:force:)`
- [ ] Guards: not current branch, no open PR, not default branch
- [ ] Confirmation dialog with PR warning
- [ ] Context menu on branch rows (likely needs `BranchListSheet` from F4)
- [ ] Menu shortcut: ⌘⇧D

*Estimate: 2 days part-time*

---

### 1.5 Publish branch UX

*Backend already exists — `push()` uses `-u` when no upstream.*

- [ ] `RemoteSyncToolbarItem`: show "Publish Branch" when `upstreamStatus` has no upstream
- [ ] `BranchSwitcherMenu`: same CTA when branch is local-only
- [ ] Optional: hint in `RepositoryShortcutsView` when clean + unpublished

*Estimate: 0.5–1 day*

---

## Stage 2 — Diff & commit polish

**Goal:** Review and commit ergonomics comparable to GitHub Desktop.  
**Estimate:** 5–7 weeks part-time.  
**Depends on:** Stage 1 complete (especially history diffs + `DiffDetailContext`).

### Exit criteria

Split diff and amend work; users can recover from local mistakes; changes list has filter and bulk actions. Partial line staging is optional for exit — see note below.

---

### 2.1 Richer diff viewer

- [ ] Split (side-by-side) mode toggle in `DiffView`
- [ ] Hide whitespace (`git diff -w`) toggle
- [ ] Expand hunk / whole file (`-U<n>` with increasing context)
- [ ] Settings → Appearance: tab size, default diff mode
- [ ] Binary / image preview (detect binary diff output; `NSImage` for images)

*Estimate: 1–1.5 weeks part-time*

---

### 2.2 Partial commits (line-level staging) ⚠️ Stretch goal

*Hardest feature in the roadmap. Budget 2–3 weeks part-time. OK to ship Stage 2 without this and return later.*

- [ ] Design: patch-based `git apply --cached` (recommended over scripting `git add -p`)
- [ ] `DiffSelection` model — selected lines per file
- [ ] `DiffView` — click/drag line selection, visual excluded-line state
- [ ] `GitExecutor.applyCached(patch:)` + `applyReverse` for unstage
- [ ] Update `ChangedFile.stagingState` after partial ops
- [ ] Context menu: discard added lines, stage/unstage hunk
- [ ] Tests: patch generation from `DiffHunk` fixtures

*Estimate: 2–3 weeks part-time*

---

### 2.3 Amend last commit

- [ ] Checkbox in `CommitBoxView`: "Amend last commit"
- [ ] `GitExecutor.commit(amend:)` → `git commit --amend`
- [ ] Disable or warn when commit is already pushed (`ahead == 0` on upstream)

*Estimate: 1 day — good quick win, can pull forward after Stage 1*

---

### 2.4 Undo / reset / revert

- [ ] `GitExecutor`: `reset --soft HEAD~1`, `reset --mixed <sha>`, `revert <sha>`
- [ ] History row context menu: Undo last commit, Reset to here, Revert
- [ ] Guards: warn on pushed commits; destructive confirmation

*Estimate: 3–4 days part-time*

---

### 2.5 Changes list UX

- [ ] Search/filter field above `ChangedFilesListView`
- [ ] Multi-select (`Set<ChangedFile.ID>`) + bulk stage/unstage/discard
- [ ] Keyboard: Space toggles stage (`RepositoryCommandShortcuts`)

*Estimate: 2–3 days part-time*

---

### 2.6 Git identity & warnings

- [ ] Settings → Git tab: `user.name`, `user.email`
- [ ] `GitExecutor.configGet` / `configSet`
- [ ] Populate email picker from GitHub verified emails API
- [ ] Pre-commit warning: config email ∉ verified emails
- [ ] Protected/default branch warning before push to `main`

*Estimate: 3–4 days part-time*

---

## Stage 3 — Branch operations & tags

**Goal:** Power-user branch lifecycle.  
**Estimate:** 4–5 weeks part-time.  
**Depends on:** Stage 1; Stage 2.3–2.4 helpful but not blocking.

### Exit criteria

Rebase pull, squash merge, cherry-pick, and tags work in-app. Interactive rebase drag-and-drop is **not** required.

---

### 3.1 Pull with rebase

- [ ] `GitExecutor.pull(rebase:)` + respect `pull.rebase` config
- [ ] Settings: "Default to rebase when pulling"
- [ ] On conflict → Stage 4 UI (can land as alert + external editor until 4.x ships)

*Estimate: 2–3 days*

---

### 3.2 Squash merge (local)

- [ ] `git merge --squash <branch>` + commit prompt
- [ ] Separate action from regular merge in branch UI

*Estimate: 2 days*

---

### 3.3 Cherry-pick

- [ ] `GitExecutor.cherryPick(sha:)`
- [ ] History context menu → "Cherry-pick commit"
- [ ] Conflict surfacing (same as merge)

*Estimate: 2–3 days*

---

### 3.4 Branch from commit

- [ ] `git branch <name> <sha>` from history context menu
- [ ] Reuse `CreateBranchSheet` with pre-filled SHA

*Estimate: 1 day*

---

### 3.5 Tags

- [ ] `git tag`, `git push --tags` (or push with tags option)
- [ ] Create-tag sheet from history row
- [ ] Tag badge on history rows

*Estimate: 3–4 days*

---

### 3.6 Branch list hygiene

- [ ] `git fetch --prune` option (settings or always-on)
- [ ] `git branch -m` rename
- [ ] Improve `BranchSwitcherMenu` grouping: Local / Remote / (later) Pull Requests

*Estimate: 3–4 days*

---

### ~~3.7 Interactive rebase (drag-and-drop)~~ — DEFERRED

Squash/reorder commits via drag-and-drop in history. Equivalent value for v1:

- [ ] *(Future)* Menu-driven `git rebase -i` with a simple todo editor
- [ ] *(Future)* Drag-and-drop only for unpushed commits

*Not scheduled — revisit after Stage 4 if users ask.*

---

## Stage 4 — Merge conflicts & rebase

**Goal:** Messy cases are visible, actionable, recoverable.  
**Estimate:** 3–4 weeks part-time.  
**Depends on:** Stage 3.1 and 3.3 (conflicts from pull --rebase and cherry-pick).

### Exit criteria

Conflicted files are distinct in Changes; user can open in editor, mark resolved, abort or continue merge/rebase.

---

### 4.1 Conflict detection & file list

- [ ] `GitStatusParser`: unmerged states (`UU`, `AA`, `DU`, `UD`, …)
- [ ] `FileStatus.conflicted` + `ChangedFileBadge` styling
- [ ] Changes tab banner when conflicts exist
- [ ] Block `commit()` until conflicts resolved
- [ ] `RepositoryState` enum: `.idle`, `.merging`, `.rebasing`, `.cherryPicking`
- [ ] Tests: conflict status fixtures

*Estimate: 3–4 days*

---

### 4.2 Conflict resolution guidance (v1 = external editor)

*Matches GitHub Desktop — no in-app 3-way editor.*

- [ ] Context menu: Open in Editor, Mark as Resolved (`git add`)
- [ ] Abort merge (`git merge --abort`) / abort rebase (`git rebase --abort`)
- [ ] Commit button → "Continue Merge" / "Continue Rebase" when in progress

*Estimate: 3–4 days*

---

### 4.3 Rebase current branch onto another

- [ ] `GitExecutor.rebase(onto:)` + `rebase --continue`
- [ ] Branch menu → "Rebase current branch onto…"
- [ ] Conflict loop: resolve → mark resolved → continue (reuses 4.2)

*Estimate: 4–5 days*

---

## Stage 5 — GitHub integration depth

**Goal:** GitHub-aware desktop client, not just Git with a login button.  
**Estimate:** 4–6 weeks part-time.  
**Can start in parallel with Stage 3** once Stage 1.1 (`DiffDetailContext` + diff pipeline) is done.

### Exit criteria

PR checkout works; PR diff preview in-app; CI status visible on current branch.

---

### 5.1 Pull request workflow

- [ ] `GitHubOAuthClient.fetchCompare(base:head:)` → PR diff preview panel
- [ ] Checkout PR: `git fetch origin pull/<id>/head:pr-<id>` + checkout
- [ ] "Pull Requests" section in branch list
- [ ] *(Optional v1)* Create draft PR via API; browser fallback is fine

*Estimate: 1.5–2 weeks*

---

### 5.2 CI checks

- [ ] Checks / commit status API for current branch HEAD
- [ ] Toolbar badge (pass / fail / pending)
- [ ] Checks popover with details
- [ ] *(Defer)* Re-run failed checks, system notifications

*Estimate: 1 week for badge + popover; notifications +1 week*

---

### 5.3 Issues & repo creation polish

- [ ] Menu: Create Issue on GitHub
- [ ] `CreateRepositorySheet`: `.gitignore`, license, README templates

*Estimate: 3–5 days*

---

### 5.4 Fork workflow

- [ ] Detect read-only access via repo permissions API
- [ ] Offer fork + clone
- [ ] Optional `upstream` remote setup

*Estimate: 1 week*

---

## Stage 6 — Platform, polish & enterprise (ongoing)

No fixed end date. Prioritize by user feedback.

### High priority

- [ ] **Keychain storage** — `GitHubKeychain` currently uses UserDefaults
- [ ] **Appearance settings** — theme, diff colors
- [ ] **Onboarding** — first-run tips, suggested actions (Publish branch, Create PR)

### Medium priority

- [ ] Git hooks environment / bypass hooks option
- [ ] Proxy support
- [ ] Notification preferences
- [ ] Non-GitHub remote credentials
- [ ] Rulesets / branch protection API validation

### Lower priority / out of scope

- [ ] GitHub Enterprise Server (separate auth base URL)
- [ ] Submodule support
- [ ] Git LFS indicators
- [ ] Partial stash (selected files) — not in GitHub Desktop either
- [ ] Windows port
- [ ] Copilot-generated commit messages

---

## Dependency graph

```
Foundation (F1–F4)
    │
    ▼
Stage 1 ──────────────────────────────┐
    │                                 │
    ├─► Stage 2 (2.2 optional)        │
    │       │                         │
    │       ▼                         ├─► Stage 5 (parallel after 1.1)
    └─► Stage 3                       │
            │                         │
            ▼                         │
        Stage 4 ◄─────────────────────┘
            │
            ▼
        Stage 6 (ongoing)
```

**Critical path:** Foundation → 1.1 History diffs → 1.2 Stash → 1.3 Merge → Stage 4 Conflicts

---

## Recommended sprint plan (first 6 weeks part-time)

### Sprint A (weeks 1–2): Foundation + history

1. XCTest target + existing parser tests
2. `DiffDetailContext` refactor
3. Rich log + `git show` + selectable history + commit diff in detail column

**Demo:** Click any commit → see full diff and message.

### Sprint B (weeks 3–4): Stash + branch lifecycle

1. Stash commands + Stashed Changes UI
2. Three-way dirty-checkout dialog
3. `mutateRepository` full refresh

**Demo:** Dirty working tree → stash → switch branch → restore stash.

### Sprint C (weeks 5–6): Merge, delete, publish

1. Merge branch sheet
2. Delete branch with PR guard
3. Publish Branch UX + amend checkbox (pulled from 2.3)

**Demo:** Merge feature branch, delete it, publish a new branch — Stage 1 exit criteria met.

---

## Quick wins (high impact, low effort)

| Feature | Stage | Effort | Notes |
|---------|-------|--------|-------|
| History commit diffs | 1.1 | Medium | Biggest "feels complete" jump |
| Amend checkbox | 2.3 | Small | Can ship right after Stage 1 |
| Publish Branch label | 1.5 | Tiny | Backend already done |
| History metadata (author, date) | 1.1 | Small | Ships with commit diffs |

---

## Process checklist (per feature)

Use this for every item above:

1. [ ] `GitExecutor` method(s)
2. [ ] Parser / model (if applicable)
3. [ ] Parser test with fixture string
4. [ ] `RepositoryStore` state + action + error mapping
5. [ ] View or sheet (extend existing, not new screen unless needed)
6. [ ] `GitStageApp.swift` menu command / shortcut
7. [ ] Manual test in sandboxed repo
8. [ ] Update this ROADMAP checkbox

---

## Summary

| Stage | Theme | Part-time estimate | Must-have for parity feel |
|-------|-------|-------------------|---------------------------|
| Foundation | Tests, detail context, mutation refresh | ~1 week | Yes |
| 1 | Core workflow | 3–4 weeks | Yes |
| 2 | Diff & commits | 5–7 weeks | Split diff + amend; partial staging optional |
| 3 | Branches & tags | 4–5 weeks | Rebase pull, cherry-pick, tags |
| 4 | Conflicts & rebase | 3–4 weeks | Yes, after Stage 3 |
| 5 | GitHub depth | 4–6 weeks | PR checkout + checks badge |
| 6 | Polish | Ongoing | Keychain, appearance |

**Total to "feels like GitHub Desktop" for daily use:** Foundation + Stages 1–2 (minus 2.2) + Stage 5.1 ≈ **3–4 months part-time**.

**Total to full Git power-user parity:** Add Stages 3–4 + 2.2 ≈ **6–9 months part-time**.

---

## Revision log

| Date | Change |
|------|--------|
| 2026-07-14 | Initial roadmap from gap analysis; adjusted timelines for part-time solo dev; deferred interactive rebase drag-and-drop; marked 2.2 as stretch; grounded in actual GitStage codebase |
