---
"hex-app": patch
---

Fix the screenshot "quality/detail" setting having no effect. ScreenCaptureKit ignores reduced `SCStreamConfiguration` sizes for desktop-independent window filters and always returned the window's native resolution, so every AI-processing screenshot was sent at full size regardless of the selected preset (affecting Gemini, OpenAI, and local providers). The captured image is now downscaled client-side to the chosen cap, so the setting actually controls the sent resolution (and token cost).
