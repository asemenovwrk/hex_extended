---
"hex-app": minor
---

Add a `{{transcription}}` placeholder for AI post-processing prompts. When a prompt contains the token, the transcribed text is injected inline at that position and the whole prompt is sent as a single user message (no separate system instruction) — models tend to follow this format more reliably than an instruction plus a separate text block. Prompts without the token keep the previous behavior (prompt as system instruction, transcription sent separately), so existing prompts are unaffected. Works for Gemini, OpenAI, and local (LM Studio / OpenAI-compatible) providers. The prompt editor now documents how to use the placeholder.
