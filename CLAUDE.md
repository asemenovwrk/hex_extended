# Hex – Dev Notes for Agents

This file provides guidance for coding agents working in this repo.

## Fork Changes (Our Modifications)

This is a fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) with the following additions:

### Bug Fixes

- **WhisperKit model compatibility (M1)**: Original `models.json` referenced `openai_whisper-large-v3-v20240930` (1.5GB) which was not in WhisperKit's supported list for M1 chips. Added `openai_whisper-large-v3-v20240930_626MB` as a curated option. Also patched `ModelDownloadFeature.swift` to check curated models via filesystem directly, bypassing WhisperKit's device filter — this allows the full 1.5GB model to work on M1 Max (32GB).
- **WhisperKit promptTokens fix**: Patched `TextDecoder.swift` in WhisperKit (local checkout) to guard `sampleResult.completed` with `!isPrefill` — fixes [WhisperKit #372](https://github.com/argmaxinc/WhisperKit/issues/372) where prompt tokens caused empty transcription results.

### New Features

#### Whisper Initial Prompts (`TranscriptionPrompt`)
- Named prompts with terminology hints for Whisper's `initialPrompt` feature
- Multiple prompts with quick switching via picker in Settings
- Passed as `promptTokens` to WhisperKit's `DecodingOptions`
- Files: `TranscriptionPrompt.swift`, `TranscriptionPromptSectionView.swift`, `TranscriptionPromptsManagementView.swift`

#### AI Post-Processing (`GeminiClient`)
- Optional post-processing of transcribed text through Google Gemini or OpenAI API
- Two providers auto-detected by model ID:
  - **Google**: Gemini 2.5 Flash/Lite/Pro, Gemini 3 Flash, Gemini 3.1 Flash Lite, Gemma 4 26B/31B
  - **OpenAI**: GPT-5.4 Nano, GPT-5.4 Mini (text post-processing only, no audio)
- Two modes:
  - **Whisper + AI**: Whisper transcribes, AI post-processes text
  - **Direct Audio** (Google models only): Audio sent directly to Gemini, skipping Whisper entirely
- Separate API keys for Google and OpenAI (`activeAIApiKey` computed helper selects by model)
- Multiple named prompts (system instructions) with quick switching
- Configurable thinking budget (Off/Low/Medium/High) — maps to Gemini `thinkingBudget` or OpenAI `reasoning_effort`
- 1 automatic retry on failure, then error shown in UI
- Token usage stats (input+output) displayed alongside processing time
- Green progress indicator during AI post-processing (distinct from blue Whisper indicator)
- ESC cancels both transcription and post-processing
- Files: `GeminiClient.swift`, `GeminiSectionView.swift`

#### UI Improvements
- Error banner at bottom of Settings window (red, dismissable)
- AI processing stats in bottom bar: model name, duration, token count
- Green capsule indicator for post-processing phase

### Removed

- **Sparkle auto-updates**: Disabled and removed from UI. This fork is maintained independently; the original Sparkle feed would overwrite our build with the upstream binary.

### Build & Install (This Fork)

```bash
# 1. Build (ad-hoc signing, no developer certificate needed)
xcodebuild -scheme Hex -configuration Release -derivedDataPath build \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=""

# 2. Copy the app icon (Xcode 16 .icon format doesn't export via CLI)
cp AppIcon.icns build/Build/Products/Release/Hex.app/Contents/Resources/AppIcon.icns

# 3. Sign with sandbox entitlements (required for mic access, network, etc.)
codesign --force --deep --sign - \
  --entitlements Hex/Hex.entitlements \
  build/Build/Products/Release/Hex.app

# 4. Install (close Hex first)
killall Hex 2>/dev/null
rm -rf /Applications/Hex.app
cp -R build/Build/Products/Release/Hex.app /Applications/Hex.app
```

**Important notes:**
- Step 2 is required because `AppIcon.icon` (Xcode 16 format) is not processed correctly by command-line builds. `AppIcon.icns` is extracted from the official release and committed to the repo root.
- After first install, macOS may ask to grant microphone access again (ad-hoc signature changes the app identity for TCC).
- The WhisperKit patch in `build/SourcePackages/checkouts/WhisperKit/Sources/WhisperKit/Core/TextDecoder.swift` lives in the SPM checkout and needs to be reapplied after `xcodebuild` resolves packages fresh (e.g., after deleting `build/`). The patch: change `sampleResult.completed` to `(!isPrefill && sampleResult.completed)` at ~line 858.

### Settings Fields Added to HexSettings

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `transcriptionPrompts` | `[TranscriptionPrompt]` | `[]` | Whisper initial prompt profiles |
| `selectedTranscriptionPromptID` | `UUID?` | `nil` | Active Whisper prompt |
| `geminiApiKey` | `String?` | `nil` | Google API key (Gemini/Gemma) |
| `openaiApiKey` | `String?` | `nil` | OpenAI API key (GPT models) |
| `geminiModel` | `String` | `"gemini-2.5-flash"` | Selected AI model (any provider) |
| `geminiPostProcessingEnabled` | `Bool` | `false` | Master toggle |
| `geminiPrompts` | `[TranscriptionPrompt]` | `[]` | AI prompt profiles |
| `selectedGeminiPromptID` | `UUID?` | `nil` | Active AI prompt |
| `geminiDirectAudioMode` | `Bool` | `false` | Skip Whisper, send audio to AI (Google only) |
| `geminiThinkingBudget` | `Int` | `0` | Thinking budget (0=off, maps to reasoning_effort for OpenAI) |

---

## Project Overview

Hex is a macOS menu bar application for on‑device voice‑to‑text. It supports Whisper (Core ML via WhisperKit) and Parakeet TDT v3 (Core ML via FluidAudio). Users activate transcription with hotkeys; text can be auto‑pasted into the active app.

## Build & Development Commands

```bash
# Build the app
xcodebuild -scheme Hex -configuration Release

# Run tests (must be run from HexCore directory for unit tests)
cd HexCore && swift test

# Or run all tests via Xcode
xcodebuild test -scheme Hex

# Open in Xcode (recommended for development)
open Hex.xcodeproj
```

## Architecture

The app uses **The Composable Architecture (TCA)** for state management. Key architectural components:

### Features (TCA Reducers)
- `AppFeature`: Root feature coordinating the app lifecycle
- `TranscriptionFeature`: Core recording and transcription logic
- `SettingsFeature`: User preferences and configuration
- `HistoryFeature`: Transcription history management

### Dependency Clients
- `TranscriptionClient`: WhisperKit integration for ML transcription
- `RecordingClient`: AVAudioRecorder wrapper for audio capture
- `PasteboardClient`: Clipboard operations
- `KeyEventMonitorClient`: Global hotkey monitoring via Sauce framework

### Key Dependencies
- **WhisperKit**: Core ML transcription (tracking main branch)
- **FluidAudio (Parakeet)**: Core ML ASR (multilingual) default model
- **Sauce**: Keyboard event monitoring
- **Sparkle**: Auto-updates (feed: https://hex-updates.s3.amazonaws.com/appcast.xml)
- **Swift Composable Architecture**: State management
- **Inject** Hot Reloading for SwiftUI

## Important Implementation Details

1. **Hotkey Recording Modes**: The app supports both press-and-hold and double-tap recording modes, implemented in `HotKeyProcessor.swift`. See `docs/hotkey-semantics.md` for detailed behavior specifications including:
   - **Modifier-only hotkeys** (e.g., Option) use a **0.3s threshold** to prevent accidental triggers from OS shortcuts
   - **Regular hotkeys** (e.g., Cmd+A) use user's `minimumKeyTime` setting (default 0.2s)
   - Mouse clicks and extra modifiers are discarded within threshold, ignored after
   - Only ESC cancels recordings after the threshold

2. **Model Management**: Models are managed by `ModelDownloadFeature`. Curated defaults live in `Hex/Resources/Data/models.json`. The Settings UI shows a compact opinionated list (Parakeet + three Whisper sizes). No dropdowns.

3. **Sound Effects**: Audio feedback is provided via `SoundEffect.swift` using files in `Resources/Audio/`

4. **Window Management**: Uses an `InvisibleWindow` for the transcription indicator overlay

5. **Permissions**: Requires audio input and automation entitlements (see `Hex.entitlements`)

6. **Logging**: All diagnostics should use the unified logging helper `HexLog` (`HexCore/Sources/HexCore/Logging.swift`). Pick an existing category (e.g., `.transcription`, `.recording`, `.settings`) or add a new case so Console predicates stay consistent. Avoid `print` and prefer privacy annotations (`, privacy: .private`) for anything potentially sensitive like transcript text or file paths.

## Models (2025‑11)

- Default: Parakeet TDT v3 (multilingual) via FluidAudio
- Additional curated: Whisper Small (Tiny), Whisper Medium (Base), Whisper Large v3
- Note: Distil‑Whisper is English‑only and not shown by default

### Storage Locations

- WhisperKit models
  - `~/Library/Application Support/com.kitlangton.Hex/models/argmaxinc/whisperkit-coreml/<model>`
- Parakeet (FluidAudio)
  - We set `XDG_CACHE_HOME` on launch so Parakeet caches under the app container:
  - `~/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml`
  - Legacy `~/.cache/fluidaudio/Models/…` is not visible to the sandbox; re‑download or import.

### Progress + Availability

- WhisperKit: native progress
- Parakeet: best‑effort progress by polling the model directory size during download
- Availability detection scans both `Application Support/FluidAudio/Models` and our app cache path

## Building & Running

- macOS 14+, Xcode 15+

### Packages

- WhisperKit: `https://github.com/argmaxinc/WhisperKit`
- FluidAudio: `https://github.com/FluidInference/FluidAudio.git` (link `FluidAudio` to Hex target)

### Entitlements (Sandbox)

- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true` (HF downloads)
- `com.apple.security.files.user-selected.read-write = true` (optional import)
- `com.apple.security.automation.apple-events = true` (media control)

### Cache root (Parakeet)

Set at app launch and logged:

```
XDG_CACHE_HOME = ~/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/cache
```

FluidAudio models reside under `Application Support/FluidAudio/Models`.

## UI

- Settings → Transcription Model shows a compact list with radio selection, accuracy/speed dots, size on right, and trailing menu / download‑check icon.
- Context menu offers Show in Finder / Delete.

## Troubleshooting

- Repeated mic prompts during debug: ensure Debug signing uses "Apple Development" so TCC sticks
- Sandbox network errors (‑1003): add `com.apple.security.network.client = true` (already set)
- Parakeet not detected: ensure it resides under the container path above; downloading from Hex places it correctly.

## Changelog Workflow Expectations

1. **Always add a changeset:** Any feature, UX change, or bug fix that ships to users must come with a `.changeset/*.md` fragment. The summary should mention the user-facing impact plus the GitHub issue/PR number (for example, "Improve Fn hotkey stability (#89)").
2. **Use non-interactive changeset creation:** AI agents should use the non-interactive script:
   ```bash
   bun run changeset:add-ai patch "Your summary here"
   bun run changeset:add-ai minor "Add new feature"
   bun run changeset:add-ai major "Breaking change"
   ```
3. **Only create changesets, don't process them:** Agents should only create changeset fragments. The release tool is responsible for running `changeset version` to collect changesets into `CHANGELOG.md` and syncing to `Hex/Resources/changelog.md`.
4. **Reference GitHub issues:** When a change addresses a filed issue, link it in code comments and the changeset entry (`(#123)`) so release notes and Sparkle updates point users back to the discussion. If the work should close an issue, include "Fixes #123" (or "Closes #123") in the commit or PR description so GitHub auto-closes it once merged.

## Git Commit Messages

- Use a concise, descriptive subject line that captures the user-facing impact (roughly 50–70 characters).
- Follow up with as much context as needed in the body. Include the rationale, notable tradeoffs, relevant logs, or reproduction steps—future debugging benefits from having the full story directly in git history.
- Reference any related GitHub issues in the body if the change tracks ongoing work.

## Releasing a New Version

Releases are automated via a local CLI tool that handles building, signing, notarizing, and uploading.

### Prerequisites

1. **AWS credentials** must be set (for S3 uploads):
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   ```

2. **Notarization credentials** stored in keychain (one-time setup):
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD"
   ```

3. **Dependencies installed** at project root and in tools:
   ```bash
   bun install                # project root (for changesets)
   cd tools && bun install    # tools dependencies
   ```

### Release Steps

1. **Ensure all changes are committed** - the release tool requires a clean working tree

2. **Ensure changesets exist** - any user-facing change should have a `.changeset/*.md` file:
   ```bash
   bun run changeset:add-ai patch "Fix microphone selection"
   ```

3. **Run the release command** from project root:
   ```bash
   bun run tools/src/cli.ts release
   ```

### What the Release Tool Does

1. Checks for clean working tree
2. Finds pending changesets and applies them (bumps version in `package.json`)
3. Syncs changelog to `Hex/Resources/changelog.md`
4. Updates `Info.plist` and `project.pbxproj` with new version
5. Increments build number
6. Cleans DerivedData and archives with xcodebuild
7. Exports and signs with Developer ID
8. Notarizes app with Apple
9. Creates and signs DMG
10. Notarizes DMG
11. Generates Sparkle appcast
12. Uploads to S3 (versioned DMG + `hex-latest.dmg` + appcast.xml)
13. Commits version changes, creates git tag, pushes
14. Creates GitHub release with DMG and ZIP attachments

### If No Changesets Exist

The tool will prompt you to either:
- Stop and create a changeset (recommended)
- Continue with manual version bump (useful for re-running failed releases)

### Artifacts

Each release produces:
- `Hex-{version}.dmg` - Signed, notarized DMG
- `Hex-{version}.zip` - For Homebrew cask
- `hex-latest.dmg` - Always points to latest
- `appcast.xml` - Sparkle update feed

### Troubleshooting

- **"Working tree is not clean"**: Commit or stash all changes before releasing
- **Notarization fails**: Check Apple ID credentials and app-specific password
- **S3 upload fails**: Verify AWS credentials and bucket permissions
- **Build fails**: Ensure Xcode 16+ and valid code signing certificates
