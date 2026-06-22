---
"hex-app": patch
---

Extend the AI post-processing debug-save option to also dump the exact prompt sent to the LLM. When "Save sent screenshot + prompt to disk (debug)" is on, Hex now writes `last-sent-prompt.txt` (provider, model, params, and the full system + user content after `{{transcription}}` substitution) next to `last-sent.jpg`. Only the most recent call is kept (overwritten each time), and "Show in Finder" reveals both files.
