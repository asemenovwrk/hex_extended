---
"hex-app": minor
---

Add a Local LLM provider for AI post-processing. You can now point Hex at any OpenAI-compatible local server (e.g. LM Studio or Ollama) by selecting "Local LLM" in the AI Processing model picker and entering a base URL (default `http://localhost:1234/v1`) and model name. A "Max output tokens" setting prevents reasoning models from spending the whole budget on thinking and returning empty content, and an optional API key is supported for secured servers. Screenshots (visual context) work for local vision models just like the cloud providers. The active provider is now stored explicitly rather than inferred from the model name.
