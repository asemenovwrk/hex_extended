# Hex Extended — Voice → Text + AI

A fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) with Gemini AI integration, Whisper prompt profiles, and model fixes.

> **Note:** Apple Silicon Macs only. Build from source (no pre-built binaries).

## What's Different from Original Hex

### Gemini AI Processing
- **Post-processing mode**: Whisper transcribes, then Gemini fixes technical terms, formatting, punctuation
- **Direct audio mode**: Skip Whisper entirely, send audio straight to Gemini
- Multiple named prompts (system instructions) with quick switching
- Configurable thinking budget and model selection

### Whisper Improvements
- **Initial prompt profiles**: Named terminology hints for Whisper (e.g., "Kubernetes, Docker, EC2...")
- **Model fixes for M1**: Both 626MB and full 1.5GB Whisper Large v3 work on M1 Max
- **WhisperKit bug fix**: Patched empty results when using prompt tokens ([upstream #372](https://github.com/argmaxinc/WhisperKit/issues/372))

### Other Changes
- Auto-updates (Sparkle) removed — this fork is maintained independently
- Error banner in Settings UI
- Gemini processing time indicator

## Build & Install

Requires Xcode 16+ on Apple Silicon Mac.

```bash
# Clone
git clone git@github.com:asemenovwrk/hex_extended.git
cd hex_extended

# Build
xcodebuild -scheme Hex -configuration Release -derivedDataPath build \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=""

# Install
APP="build/Build/Products/Release/Hex.app"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - --entitlements Hex/Hex.entitlements "$APP"
killall Hex 2>/dev/null
rm -rf /Applications/Hex.app
cp -R "$APP" /Applications/Hex.app
```

## Setup

1. Open Hex, grant microphone and accessibility permissions
2. Configure a global hotkey in Settings
3. For Gemini AI features: get an API key at [aistudio.google.com](https://aistudio.google.com/apikey), enable "AI Processing" in Settings

## Usage

1. **Press-and-hold** the hotkey to record, release to transcribe
2. **Double-tap** the hotkey to lock recording, tap again to stop

## Credits

Based on [Hex](https://github.com/kitlangton/Hex) by Kit Langton. Uses [WhisperKit](https://github.com/argmaxinc/WhisperKit), [FluidAudio](https://github.com/FluidInference/FluidAudio), and [TCA](https://github.com/pointfreeco/swift-composable-architecture).

## License

MIT License. See `LICENSE` for details.
