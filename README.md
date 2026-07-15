# GitStage

A native SwiftUI Git client for macOS 26+. Sign in with GitHub, open local repositories, review diffs, stage, commit, switch branches, and push.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+
- Git (Xcode Command Line Tools or Homebrew)
- A [GitHub OAuth App](https://github.com/settings/developers) client ID

## Build and run

1. Open `GitStage/GitStage.xcodeproj` in Xcode.
2. Complete the one-time OAuth setup below.
3. Run the **GitStage** scheme.

The app uses the **App Sandbox** (required for Mac App Store distribution). Repository folders must be chosen through the open panel so macOS grants access.

## One-time OAuth setup

GitStage uses the GitHub **OAuth device flow**. You need a local secrets file that is **not** committed to git.

Create `GitStage/GitStage/Auth/GitHubAuthSecrets.swift` with:

```swift
import Foundation

enum GitHubAuthSecrets {
    static let clientID = "YOUR_GITHUB_OAUTH_CLIENT_ID"
}
```

Replace `YOUR_GITHUB_OAUTH_CLIENT_ID` with the client ID from your GitHub OAuth App.

Register an OAuth App at https://github.com/settings/developers (no client secret is needed for device flow).

### If you fork this repo

1. Fork and clone the repository.
2. Create `GitHubAuthSecrets.swift` as shown above with **your** OAuth App client ID.
3. In Xcode, set **Signing & Capabilities** to your Apple Developer team and update the bundle identifier if needed (`com.divinewton.GitStage` is the default).
4. Build and run.

The client ID is public in desktop apps — never embed a client **secret**.