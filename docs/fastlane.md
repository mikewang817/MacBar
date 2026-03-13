# Fastlane Setup For MacBar

MacBar uses `fastlane` as the preferred path for App Store build upload, signing sync, and release automation.

## Install

From the repository root:

```bash
bundle install
```

The repository now pins Ruby `3.2.10` via `.ruby-version`, and the current lockfile pins `fastlane 2.230.0`.
Use `rbenv` (or another Ruby version manager) so `bundle exec fastlane ...` runs under Ruby `3.2.10` instead of the system Ruby.

## Local environment file

Copy the template and fill in your real values:

```bash
cp .env.fastlane.example .env.fastlane
```

`fastlane/Fastfile` automatically loads `.env.fastlane` from the repository root.

Before running lanes on a fresh machine:

```bash
eval "$(rbenv init - zsh)"
rbenv install -s 3.2.10
bundle install
```

## Required environment variables

### App Store Connect API key

```bash
export APP_STORE_CONNECT_KEY_ID="..."
export APP_STORE_CONNECT_ISSUER_ID="..."
export APP_STORE_CONNECT_KEY_FILE="/absolute/path/AuthKey_XXXX.p8"
```

### Match

```bash
export MATCH_GIT_URL="git@github.com:YOUR_ORG/YOUR_MATCH_REPO.git"
export MATCH_PASSWORD="..."
```

Optional:

```bash
export MATCH_GIT_BRANCH="main"
export MATCH_READONLY="1"
export FASTLANE_APPLE_ID="your-apple-id@example.com"
export FASTLANE_TEAM_ID="YOUR_TEAM_ID"
export FASTLANE_ITC_TEAM_ID="YOUR_APP_STORE_CONNECT_TEAM_ID"
```

## Lanes

### Show lanes

```bash
bundle exec fastlane mac about
```

### Verify local secrets and paths

```bash
bundle exec fastlane mac verify_env
```

### Sync Mac App Store signing

```bash
bundle exec fastlane mac sync_signing
```

### Bump version and build number

```bash
bundle exec fastlane mac bump_version version:1.0.1
```

Optional explicit build number:

```bash
bundle exec fastlane mac bump_version version:1.0.1 build:2
```

### Build Mac App Store pkg

```bash
bundle exec fastlane mac build_app_store
```

### Upload existing pkg to App Store Connect

```bash
bundle exec fastlane mac upload_app_store
```

### Full App Store pipeline

```bash
bundle exec fastlane mac release_app_store
```

## Notes

- `build_app_store` delegates to `scripts/archive_app_store.sh`, which already knows how to archive the app, resolve the App Store profile, and produce the upload-only `.pkg`.
- `sync_signing` expects a `match` repository to exist. Fastlane configuration is now the preferred place to manage Mac App Store certificates and provisioning profiles.
- `bump_version` updates:
  - `MacBar.xcodeproj`
  - `Sources/MacBar/Info.plist`
  - `Sources/MacBar/AppVersion.swift`
- To finish real match/API key integration on a new machine, the minimum sequence is:
  1. `cp .env.fastlane.example .env.fastlane`
  2. Fill in the App Store Connect API key values
  3. Fill in `MATCH_GIT_URL` and `MATCH_PASSWORD`
  4. Run `bundle exec fastlane mac verify_env`
  5. Run `bundle exec fastlane mac sync_signing`
