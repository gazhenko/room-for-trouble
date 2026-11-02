# Offline installers

End users receive a Mac `.dmg` and a Windows `-Setup.exe`. Both contain the entire
game and work offline. No agent, Godot editor, scripting runtime or package manager
is required on the player's computer. `START-HERE.txt` is included in both formats
and also generated as a separate download.

Mac: open the image, drag the app to Applications, then launch it there. The image
also contains a plain-language HTML guide. Existing ad-hoc signatures are verified
and preserved. This is not an Apple-notarized distribution.

Windows: Next → Install → Finish; installs for the current account in
`%LOCALAPPDATA%\Programs\GAME_ID`, adds desktop/Start shortcuts, and registers
removal in Settings → Apps. Requires Windows 10/11 on Intel/AMD x64. There is no
admin elevation. Finish offers an optional first launch. Updates unpack into a
unique sibling directory and replace the existing installation only after
extraction succeeds. Removal uses an explicit file inventory, never recursive
deletion of the install directory. Saves are outside that directory and are kept.
Close the game before updating or removing it.

## Build on a Mac

Install build tools once (developer machine only):

```sh
brew install makensis sevenzip
```

`tools/release.sh` stages the exported builds as release archives in
`build/release/VERSION` (with `SHA256SUMS.txt`), then runs the packager and the verifier
on them. The archives are checksum-verified before extraction; both have their files at the
archive root (`game.json`). To run the steps by hand:

```sh
python3 tools/installers/package.py v2.0.0 --release-dir build/release/v2.0.0 --output build/release/v2.0.0
python3 -m unittest discover -s tools/installers -v
(cd tools/installers && python3 verify.py v2.0.0 --release-dir ../../build/release/v2.0.0 --output ../../build/release/v2.0.0)
```

Outputs go to `build/installers/VERSION` unless `--output` is given. Windows-only
packaging (`--platform windows`) also runs on Linux with NSIS and Python 3.9+.
This copy is adapted from saltmoss-harbor for Godot exports (an executable plus its
`.pck`); keep shared behaviour in sync with the other game repositories.

`INSTALLER-SHA256SUMS.txt` covers the generated downloads. The manifest records
the exact source/archive hashes and the signing/runtime limitations.

## Release validation

- Verify every installer with `shasum -a 256 -c INSTALLER-SHA256SUMS.txt`.
- Mount each DMG read-only; compare its game files with the source ZIP, check
  the Applications shortcut and `codesign --verify --deep --strict`.
- Extract each EXE with `7zz` and compare every shipped game file with the ZIP.
- On Windows 10/11, manually exercise install, shortcut launch, update while
  closed/running, and removal with a saved game present. Archive extraction and
  successful NSIS compilation do not establish Windows runtime compatibility.
- On a Mac, try a browser-downloaded copy with quarantine intact and follow the
  documented first-launch steps. Local mounting does not establish Gatekeeper
  behavior on another Mac.

Certificates are not configured here. Removing first-launch trust prompts needs
Developer ID signing and Apple notarization for Mac, and Authenticode signing
for Windows; NSIS itself uses the user's normal privileges
([NSIS documentation](https://nsis.sourceforge.io/Reference/RequestExecutionLevel)).
The guide follows [Apple's normal approval flow](https://support.apple.com/102445).
Never ship scripts that disable system security settings.
