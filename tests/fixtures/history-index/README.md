# History index oracle fixtures

Synthetic records only; no user paths, prompts, responses or account data.

`codex-counters.jsonl` fixes cumulative growth, duplicate observations and epoch reset. Expected nonzero deltas: total 100, 45, 15, 15; input 80, 40, 10, 10; cached 50, 20, 2, 2; output 20, 5, 5, 5. These expectations reflect main db40798 semantics, not an independently invented normalization rule.

Existing token, timezone, model inference and leadership self-tests remain mandatory oracles. Incremental parsing must be compared at every complete-line restart boundary.
