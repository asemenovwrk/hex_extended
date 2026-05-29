---
"hex-app": patch
---

Rename the curated Whisper Large v3 models to "Whisper Large v3 Turbo" so the names match reality: both `openai_whisper-large-v3-v20240930` entries are the 4-layer distilled large-v3-turbo (the official OpenAI turbo release from 2024-09-30), not the full 32-layer model. Also corrects the displayed storage size (1.5GB → 1.6GB) and bumps the speed dots to reflect the turbo decoder.
