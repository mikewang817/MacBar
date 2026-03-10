fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac about

```sh
[bundle exec] fastlane mac about
```

Show the lanes used for Mac App Store release management

### mac verify_env

```sh
[bundle exec] fastlane mac verify_env
```

Verify App Store Connect API key and match environment wiring

### mac bump_version

```sh
[bundle exec] fastlane mac bump_version
```

Update Info.plist and AppVersion.swift fallback values

### mac sync_signing

```sh
[bundle exec] fastlane mac sync_signing
```

Sync Mac App Store certificates and profiles via match

### mac build_app_store

```sh
[bundle exec] fastlane mac build_app_store
```

Archive and package the Mac App Store upload build

### mac upload_app_store

```sh
[bundle exec] fastlane mac upload_app_store
```

Upload the packaged macOS build to App Store Connect

### mac release_app_store

```sh
[bundle exec] fastlane mac release_app_store
```

Sync signing, build the pkg, and upload it to App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
