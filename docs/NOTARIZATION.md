# Developer ID signing and notarization

The published **1.2.0 preview is currently ad-hoc signed, not notarized**. Adding
this workflow does not change that release or establish Apple approval. A paid
Apple Developer Program membership and its Developer ID Application certificate
are required to complete it. Apple lists US$99 per membership year, with regional
pricing. This project does not enroll an account, purchase membership, or collect
Apple Account passwords.

## One-time account setup

1. [Enroll in the Apple Developer Program](https://developer.apple.com/programs/enroll/)
   as an individual or organization. Complete identity verification, agreements
   and payment directly with Apple.
2. [Create a Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
   Generate the certificate request in Keychain Access and install Apple's issued
   certificate on the same Mac so its private key is present. An Apple Development,
   Apple Distribution or Developer ID Installer certificate does not sign this app.
3. Run `security find-identity -v -p codesigning` and select the Developer ID
   Application identity for the intended team. Keep the private key in Keychain.
4. Save notarization credentials interactively:

   ```sh
   xcrun notarytool store-credentials Mica
   ```

   Supply the Apple Account, team ID and an app-specific password at the secure
   prompts. An App Store Connect API key is another supported authentication
   method; see `xcrun notarytool store-credentials --help`. Do not put passwords,
   private keys or certificate exports into Git, issue reports or chat.

## Sign and submit

Build and test the universal app normally, then configure the two non-secret
selectors. Use the exact certificate name or its SHA-1 identifier:

```sh
./scripts/build.sh --universal
./scripts/test.sh
python3 -m unittest discover -s Tests/ReleaseTests
export MICA_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export MICA_NOTARY_PROFILE='Mica'
./scripts/notarize-release.py check
./scripts/notarize-release.py submit
```

The script copies the app into a private, ignored `.build/notarization/mica-*`
directory. It signs Swift libraries individually, then the outer app, with a
secure timestamp and hardened runtime. Mica currently needs no runtime exception
entitlements. The verifier checks both architectures, Apple's Developer ID
certificate requirement, matching teams, timestamps and the absence of debug or
unsafe runtime entitlements. New nested helpers/frameworks require a signing-order
review instead of receiving an automatic deep signature.

Submission uploads the signed ZIP to Apple and records a submission ID. It does
not claim acceptance or modify the installed app, local development bundle or
published GitHub release. Processing may take time, especially for a new team.
Keep the printed working directory for the next step.

## Finish and verify

Run the following with the actual working directory printed by `submit`:

```sh
./scripts/notarize-release.py finish .build/notarization/mica-EXAMPLE
```

While processing is pending, the script leaves the candidate staged and creates
no distribution archive. On rejection it downloads Apple's diagnostic log and
stops. It also stops if the signed executable or submitted ZIP changed.

Only an **Accepted** submission proceeds to ticket stapling, `stapler validate`,
Developer ID verification and Gatekeeper assessment. It creates a ZIP, extracts
that exact ZIP, and repeats notarization verification to check ticket preservation.
The final archive and SHA-256 checksum appear under `dist/notarized/` after all
checks pass. The stapled app remains in the working directory.

```sh
./scripts/verify-release.sh --distribution .build/notarization/mica-EXAMPLE/Mica.app
./scripts/verify-release.sh --notarized .build/notarization/mica-EXAMPLE/Mica.app
```

Before publication, smoke-test the Developer ID-signed app's meters, native
settings, device refresh and login registration. Verify a quarantined download on
another Mac, including offline ticket validation. Record the certificate team,
submission ID, accepted status and Gatekeeper results in `VALIDATION.md`, then
publish the verified archive and updated checksums. Do not replace a signed ZIP
with a later ad-hoc development build. macOS may still show its normal first-open
confirmation for an internet download; notarization addresses the unidentified
developer/unverified software block.

## Current evidence

The preflight was tested without a usable Developer ID signing identity. It stops
before changing the app or contacting the notary service. Release boundary tests
cover pending/rejected submissions, a changed candidate, malformed IDs and
development certificates. A separate ad-hoc hardened runtime build was verified on
an M1 MacBook Air: eight CPU cores, memory, network, disk, 47 temperature sensors and
a live battery reading were available. The five release-boundary tests pass, and
both ordinary and hardened ad-hoc signatures are rejected as Developer ID/notarized
distributions. These checks are not a substitute for a real Developer ID signature
or Apple's acceptance. Signing, submission and stapling with real account
credentials still need end-to-end validation after enrollment.

## Apple references

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Signing order and hardened runtime](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Enrollment and current fees](https://developer.apple.com/help/account/membership/program-enrollment)
