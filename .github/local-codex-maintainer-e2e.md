# Local Codex Maintainer E2E

This temporary fixture validates a personal local review bot outside the codexU product:

- label-triggered pull-request discovery;
- diff review with the signed-in local Codex account;
- a persisted Codex thread and local approval gate;
- one idempotent GitHub comment after approval.

It does not change codexU production behavior.
