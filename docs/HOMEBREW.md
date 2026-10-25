# Install Mica with Homebrew

Mica has a project-maintained cask in [angad/homebrew-tap](https://github.com/angad/homebrew-tap).
It is a personal tap, separate from Homebrew's official `homebrew/cask` repository.

```sh
brew install --cask angad/tap/mica
```

This downloads the versioned universal app from Mica's GitHub release, checks its
SHA-256, and installs `Mica.app` to Applications. Apple Silicon and Intel binaries
are included; the cask requires macOS 12.3 or newer.

Homebrew 6+ treats this fully qualified install as explicit trust for this one
cask, rather than the entire tap. Review the [cask definition](https://github.com/angad/homebrew-tap/blob/main/Casks/mica.rb)
and [Homebrew's tap-trust documentation](https://docs.brew.sh/Tap-Trust).

## First launch

The 1.3.0 preview is ad-hoc signed and not notarized. Installing through Homebrew
does not change that status or remove quarantine. If macOS blocks opening the app,
read [Apple's first-open guidance](https://support.apple.com/en-us/102445) and use
Privacy & Security only if you trust the source. Code signing remains deferred.

Open Mica from Applications. Click its meters for details or right-click for
settings. Enable General → Open at login if you want it to start automatically.

For optional paired iPhone/iPad diagnostics, install the tools separately:

```sh
brew install libimobiledevice
```

## Existing manual installation

If Homebrew reports that Mica.app already exists, quit Mica and move that app to
Trash before installing. Its preferences and history are outside the app bundle.
If your existing app is byte-for-byte identical to the current download, Homebrew
also supports `brew install --cask --adopt angad/tap/mica`.

## Update or remove

```sh
brew update
brew upgrade --cask angad/tap/mica
brew uninstall --cask angad/tap/mica
```

Normal uninstall keeps preferences and battery history. To delete those too:

```sh
brew uninstall --cask --zap angad/tap/mica
```

The cask does not install optional iOS tools, enable login startup or change sleep
settings. If you enabled the persistent lid-sleep override, turn it off in Mica
before uninstalling; quitting alone does not undo that explicit system setting.

## Maintainers

The authoritative cask is in the tap repository. Update its version and SHA-256
after publishing the corresponding universal release. Keep the unsigned-preview
caveat until the released artifact has actually passed notarization and Gatekeeper.
Never add a quarantine-removal command to work around signing.

## Validation — 25 October 2026

- Ruby syntax and Homebrew style checks pass.
- The published ZIP's SHA-256 matches the cask; its signature verifies and it
  contains both arm64 and x86_64.
- Homebrew 7.0.10 on macOS 27.0.1 successfully installed Mica 1.2.0 into a temporary
  application directory and uninstalled that copy. The app retained its quarantine
  attribute. The existing installed Mica and its history were preserved, and
  test-only tap/trust state was removed afterwards.
- The online audit passes with the single `github_prerelease_version` exception:
  this personal tap intentionally distributes the clearly marked preview.
- [The disposable macOS CI install/uninstall test passes](https://github.com/angad/homebrew-tap/actions/runs/40236445518).

Installation verification is separate from Apple's notarization. The release is
still ad-hoc signed, and its first launch may require explicit macOS approval.
