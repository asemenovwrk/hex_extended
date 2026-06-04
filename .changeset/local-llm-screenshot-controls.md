---
"hex-app": minor
---

Add screenshot controls for the Local LLM provider. A "Screenshot Scale" slider (10–100% of the window's native resolution) lets you trade detail for speed on vision models, a "Sharpen text for legibility" toggle applies a light unsharp mask after downscaling so text stays readable at lower scale, and a "Save sent screenshot to disk (debug)" toggle (with a Show in Finder button) writes the exact image sent to the model for inspection. The stats line now shows the local model name instead of the cloud model id.
