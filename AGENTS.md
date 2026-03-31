# AI Agent Handoff

This repository contains a macOS menu bar app for lightweight GitLab issue tracking and issue creation.

## Product Summary

- The app runs as a menu bar-only app.
- It shows currently assigned open GitLab issues for the authenticated user.
- Clicking an issue starts local time tracking.
- Every 20 minutes, the app books 20 minutes to the GitLab issue and asks whether tracking should continue.
- The app can create a new issue in a selected GitLab project.
- After creating an issue, the create section collapses and the assigned issue list refreshes.

## Important Current Decisions

- Issue status handling was intentionally removed.
- There is no status dropdown in the UI.
- The app does not post GitLab `/status` quick actions.
- A GitLab group setting still exists and is used to scope the create-issue project picker.
- The group is selected from cached project namespaces in Settings.

## Main User Flows

### Authentication

- Settings collect:
  - GitLab base URL
  - OAuth application ID
  - optional GitLab group
- OAuth uses a localhost callback server with PKCE.
- Tokens are stored locally in Keychain.
- Base URL, OAuth client ID, and group selection sync via iCloud key-value storage.

### Assigned Issues

- Assigned issues are fetched from GitLab REST.
- Recently tracked issues are pinned first.
- Remaining issues are ordered by GitLab `updated_at` descending.
- The issue list hides scroll indicators.

### Time Tracking

- Starting an issue creates an active local tracking session.
- Tracking state persists across app restarts.
- If the app restarts during a session, the session is restored.
- On each 20-minute checkpoint:
  - 20 minutes are added to the GitLab issue
  - a notification asks whether to continue
- Stopping before the next checkpoint books the elapsed minutes.

### Project Selection and Issue Creation

- Projects are fetched from GitLab and cached locally.
- The project selector is a searchable overlay list in the menu bar window.
- Recent projects are shown first.
- If a GitLab group is selected in Settings, only projects within that group are shown in the create flow.
- Creating an issue can optionally assign it to the current user.
- `Cmd+Enter` creates the issue.

## Key Files

- `My GitLab Timetracking/My_GitLab_TimetrackingApp.swift`
  - app entry point
  - menu bar app setup
- `My GitLab Timetracking/MenuBarViews.swift`
  - menu bar UI
  - issue list
  - create issue UI
  - searchable project selector
- `My GitLab Timetracking/TrackingManager.swift`
  - assigned issue refresh
  - issue ordering
  - session lifecycle
  - time booking
- `My GitLab Timetracking/ProjectManager.swift`
  - project loading and caching
  - selected project state
  - issue creation
- `My GitLab Timetracking/GitLabAPI.swift`
  - GitLab REST requests
- `My GitLab Timetracking/GitLabAuthManager.swift`
  - OAuth flow
  - token refresh
  - current user loading
- `My GitLab Timetracking/AppSettings.swift`
  - user defaults
  - iCloud sync
  - selected group / recent items
- `My GitLab Timetracking/SettingsView.swift`
  - settings UI
- `My GitLab Timetracking/SessionStore.swift`
  - persisted active tracking session
- `My GitLab Timetracking/ProjectCacheStore.swift`
  - cached GitLab projects
- `My GitLab Timetracking/NotificationCoordinator.swift`
  - checkpoint notifications
- `My GitLab Timetracking/OAuthCallbackServer.swift`
  - local OAuth callback listener

## Build Command

Use this from the repository root:

```sh
xcodebuild -project 'My GitLab Timetracking.xcodeproj' -scheme 'My GitLab Timetracking' -derivedDataPath /tmp/MyGitLabTimetrackingDerivedData CODE_SIGNING_ALLOWED=NO build
```

## Expected Working Style

- Keep commits small and focused.
- Do not reintroduce issue status handling unless explicitly requested.
- Prefer preserving the current menu bar UX instead of replacing it with a standard macOS window flow.
- Be careful with existing user changes in the worktree.

## Useful Notes for Future Agents

- GitLab project data includes both display names and `path_with_namespace`.
- Group scoping should use `path_with_namespace`, not the display name.
- The app currently uses REST for projects, issues, and time booking.
- OAuth redirect URI is defined in `GitLabAuthManager`.
- If a future change touches project selection, re-test keyboard navigation in the project search field.
