---
"hex-app": minor
---

Add Qwen3-ASR as a third on-device transcription engine (MLX), alongside WhisperKit and Parakeet. Qwen3-ASR is multilingual and especially strong on mixed-language technical speech (e.g. Russian dictation peppered with English IT terms). Three curated tiers appear in the transcription model picker — Low (0.6B, ~0.96GB, fastest), Medium (1.7B 8-bit, ~1.8GB), and High (1.7B bf16, ~3.8GB, max quality). The active transcription prompt is fed into Qwen3-ASR's context-biasing input, so your terminology vocabulary keeps technical terms in their proper form. Runs fully in-process on Apple Silicon (GPU/Metal); models download on demand from Hugging Face. Building the app now requires the Xcode Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`).
