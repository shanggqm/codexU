# codexU Maintainer E2E fixture

This temporary file exercises the phase-one pull-request review loop:

1. discover a labeled pull request;
2. review its diff with the local Codex account;
3. stop at the human approval gate;
4. publish exactly one idempotent GitHub comment after approval.

The fixture contains no production behavior changes and can be removed after the test.
