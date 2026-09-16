# Rio GA release implementation handoff

Status: **repository remediation implemented; external GA evidence and release approval remain open**.

Prepared 2026-09-16 from the audit of `main` at `1efc99e`. See the
[dated audit](GA_AUDIT_2026-09-16.md) for triggers, source references, evidence,
and qualifications. Line references describe that revision and may move.

The receiving team should reproduce the findings against its checkout, implement
the fixes below, and record acceptance evidence. This handoff does not authorize
publishing a release, capturing real meetings, or expanding the product scope.
Follow repository `AGENTS.md`, `PRODUCT.md`, and `ARCHITECTURE.md`; use synthetic
meeting text and generated audio for validation. Keep audio off disk and preserve
the no-live-transcript and bounded-history product boundaries.

## Decisions needed before dependent implementation

- [x] **D1 — Retention while Rio is closed.** Rio prunes every minute while
  running and before presentation on the next launch after a closed-app expiry.
  This enforcement model, corrupt-history behavior, and failed-expiry state are
  recorded in `PRODUCT.md` and `ARCHITECTURE.md`; an ordinary file cannot delete
  itself while Rio is not running.
- [x] **D2 — Stop and pause semantics.** Rio uses immediate cancellation and an
  explicitly incomplete saved prefix; save failure remains retryable and blocks
  replacement or ordinary termination.
- [ ] **D3 — Model acceptance and consent.** Resolve the open decisions in the
  [evaluation pack](evaluation/incident-copilot-mvp/README.md), including consent,
  supported evaluation domains, acceptance thresholds, and model/build baseline.
  Separate implemented card behavior from deferred retrieval capabilities; do not
  add a retrieval system just to satisfy a broader conceptual rubric.

## Work packages and acceptance criteria

The boxes below reflect the current repository state. P1 items block GA; P2
items require a fix or an explicit, documented disposition before signoff. A
risk is not a reproduced failure unless the audit identifies a concrete reproduction.

### GA-01 — Disable unnecessary provider and local network storage (P1)

Primary ownership: `Rio/OpenAIInsightAdapter.swift` and its tests.

- [x] Set `store: false` on every insight Responses request and assert the actual
  serialized request body in tests.
- [x] Configure production transport to avoid disk caching of meeting-derived
  responses; add a focused configuration/cache regression check. Shared caching
  is a hardening gap, not a proven current provider leak.
- [x] Update privacy/product documentation to distinguish local retention,
  Responses application-state storage, and provider abuse-monitoring/cache
  policies. Do not claim `store: false` guarantees zero provider retention.

Acceptance: requests explicitly disable response storage, production transport
does not use a disk response cache, and the published privacy description matches
the implementation and the supported account configuration.

### GA-02 — Enforce expiry, bound total history, and handle failed saves (P1)

Primary ownership: `Rio/MeetingHistoryStore.swift`, history tests, and the history
recording interface. Coordinate UI/lifecycle changes with GA-03 and GA-04.

- [x] Prune on an appropriate schedule while running and on wake/access; ensure
  opening Recent Meetings cannot reveal expired entries. Resolve D1.
- [x] Handle load/decode and expiry-write failures explicitly. Hiding records
  must not be represented as successful deletion from disk.
- [x] Add aggregate meeting-count and byte bounds with deterministic eviction,
  preserving existing per-meeting bounds and retention.
- [x] Propagate record-save errors instead of swallowing them. Preserve a bounded
  retryable in-memory record and display a concise save-failure state.
- [x] Test clock advancement without another meeting, failed prune/save/retry,
  corrupt history, aggregate overflow, and successful deletion after failure.

Acceptance: an open idle app expires records on time; failed persistence is
visible and retryable; restart never exposes unsaved data as if it had been saved;
all in-memory and on-disk history limits are explicit and tested. Closed-app
retention behavior conforms to the approved D1 decision.

### GA-03 — Preserve truthful transcript and insight continuity (P1)

Primary ownership: `Rio/SessionOrchestration.swift`,
`Rio/OpenAITranscriptionAdapter.swift`, context batching in
`Rio/CoreContracts.swift`, and related tests.

- [x] Implement D2 for partial, queued, and in-flight transcription on stop/pause.
  Never label a transcript complete when a captured interval was discarded.
- [x] Ensure a pause during generation does not permanently consume the pending
  insight batch. Acknowledge successful application or retain a bounded retry.
- [x] Preserve session isolation, ordering, cancellation, and idempotent cleanup;
  do not expose a new pause control as part of this fix without a product decision.
- [x] Test stopping before the first batch completes, stopping during upload,
  stopping with backlog, pausing mid-batch/mid-generation, resuming, and restarting
  while stale asynchronous results finish. Cover 30/60/90-second cadence bounds
  with deterministic generated audio and injected delays.

Acceptance: every saved completeness flag is truthful; no silently discarded
interval or insight batch is reported as processed; stop remains bounded and
temporary data is cleared according to the chosen policy.

### GA-04 — Route ordinary app termination through stop/save (P1)

Primary ownership: `Rio/RioApp.swift`, `Rio/ApplicationShell.swift`, and
`Rio/CompositionRoot.swift`. Depends on GA-02/GA-03 lifecycle/save contracts.

- [x] Use the application termination lifecycle to await bounded stop/save before
  completing an ordinary quit, including Command-Q/menu quit.
- [x] Define and test save failure during quit without losing the retryable
  meeting or claiming success. Do not rely on a forced-kill cleanup guarantee.
- [x] Test quit preparation together with the lifecycle's listening, processing,
  paused, interrupted, stopped, repeated-stop, cancellation, and no-double-save paths;
  repeated quit requests are coalesced.

Acceptance: an ordinary quit preserves finalized meeting content according to D2,
releases capture, and does not terminate while an unhandled save failure remains.

### GA-05 — Sign and verify the actual distributed package (P1)

Primary ownership: `.github/workflows/release.yml`, `scripts/package-dmg.sh`,
`scripts/verify-release.sh`, and distribution documentation.

- [x] Sign the DMG with Developer ID Application before notarization and stapling.
- [x] Assess the DMG using `spctl --assess --type open --context
  context:primary-signature --verbose=4`, not only the archive app.
- [x] Mount the packaged image read-only and verify its actual app payload:
  signature, hardened runtime, entitlements, architectures, version, minimum OS,
  notarization, and expected drag-install contents. Always detach on failure.
- [x] Enforce the documented release-from-main policy if mandatory; do not treat
  a syntactically valid tag as proof of provenance.
- [ ] Validate a candidate from the actual intended release commit. Keep publishing
  and tag creation subject to the user's explicit release instruction.
- [x] Correct the stale roadmap statement that notarization credentials have never
  been configured, while preserving outstanding hardware/evaluation gates.

Acceptance: the exact candidate DMG passes signature and notarization checks and
a quarantined clean-machine install. The older v1.0.2 inner app already passed
notarization; the observed failure concerns its unsigned outer image.

### GA-06 — Ground owner attribution in the actual action (P2)

Primary ownership: insight translation/validation in `OpenAIInsightAdapter.swift`
and `CoreContracts.swift`, plus related tests/evaluations. Schedule after GA-01
and GA-03 to avoid overlapping file ownership.

- [x] Replace mere name-occurrence validation with evidence tied to the action,
  or conservatively omit unsupported attribution under an approved design.
- [x] Cover owner claims inside displayed card text as well as `explicitOwner`.
- [x] Test absent names, unrelated mentioned names, negated assignments, partial
  names, wrong grammatical subjects, displayed attribution, and supported assignments.
- [ ] Include adversarial live-model evaluations; metadata validation alone cannot
  establish semantic correctness of free text.

Acceptance: the synthetic owner cases cannot render an unsupported assignment;
model evaluation records any failures and does not average critical failures away.

### GA-07 — Restore the configured Default after profile deletion (P2)

Primary ownership: `Rio/CoreDomain.swift` and relevant profile tests.

- [x] Selecting then deleting a custom profile must select the configured
  `defaultProfile`, not the static factory fallback.
- [x] Verify edited Default guidance, cadence, and vocabulary in the next session
  and after restart.

### GA-08 — Remove blocking work from capture callbacks (P2)

Primary ownership: `Rio/SystemAudioCapture.swift` and capture tests.

- [x] Remove the callback's blocking sequence lock and assess bounded preallocated
  storage for audio copies, preserving correct ownership/lifetime and ordering.
- [x] Verify overload, stop/start, callback teardown, and pressure behavior.
- [ ] Measure callback timing and dropped/overloaded audio under a hardware soak.

Acceptance: callback work satisfies the documented nonblocking contract; queue
bounds and explicit overload failure remain intact. The audit found a contract
violation, not a reproduced hardware dropout.

## Suggested delegation and integration order

1. A coordinator owns D1–D3, requirements, and integration. Independent teams can
   initially own network privacy (GA-01), history (GA-02), distribution (GA-05),
   profiles (GA-07), and capture (GA-08).
2. One lifecycle owner handles GA-03 after agreeing the history-recording contract
   with GA-02. That owner coordinates the shell/termination work in GA-04.
3. Schedule GA-06 after GA-01 and GA-03, or transfer explicit ownership of its
   shared files. Never assign concurrent writes to `CoreContracts.swift` or
   `OpenAIInsightAdapter.swift` across these packages.
4. An independent reviewer verifies fixes and missing-path tests, then a release
   validation owner collects the evidence below. Do not mark roadmap work complete
   solely because code or deterministic tests exist.

## GA acceptance evidence

- [x] Run relevant regression tests and `make final` after every implementation
  change, as required by `AGENTS.md`. The remediation passes 174 tests, the
  warnings-as-errors build, development-signature verification, the built-app
  Keychain round trip, and the launch smoke check.
- [ ] Build the universal Release target with compiler warnings treated as errors;
  verify both architectures and the actual signed candidate's Keychain path.
- [ ] Exercise live system-audio grant/denial/revocation, actual capture through
  transcription/cards, stop/restart, device changes, sleep/wake, offline service,
  invalid keys, overload, and stop during each pipeline stage using synthetic audio.
- [ ] Record a one-hour hardware soak: hardware/OS/build/cadence, memory trajectory,
  queue bounds, latency, continuity, recovery, and post-stop resource cleanup.
- [ ] Inspect persistence/logging for content leaks and prove history expiry and
  deletion behavior, including failure cases. Store only non-content evidence.
- [ ] Run the six-scenario evaluation pack with the agreed baseline and repeated
  trials specified by its procedure. Record latency, unsupported claims, owner
  errors, and per-scenario scores. Fixture validation is not model evaluation.
- [ ] Verify keyboard/VoiceOver access and clean-machine onboarding/install of
  the quarantined, signed/notarized DMG.
- [ ] Record the exact release commit, artifact SHA-256, test/build results,
  hardware results, evaluation results, and any accepted residual risks. Keep
  durable, content-free results in the repository; do not rely on `/tmp` logs.
- [ ] Resolve every P1 and explicitly dispose of every P2; obtain GA signoff before
  creating/publishing a release under an explicit release instruction.

## Starting evidence and limits

Current repository-only evidence also includes shell syntax checks for both
release helpers, parsed workflow YAML, a clean `git diff --check`, and successful
validation of all six synthetic evaluation fixtures. This is not a live-model
evaluation, a signed GA candidate, a clean-machine install, or hardware-soak
evidence.

At audit revision `1efc99e`, all 139 tests, a universal unsigned Release build,
the signed Debug synthetic Keychain verifier, shell syntax checks, and validation
of the six synthetic fixtures passed. Those results do not certify later changes,
live model quality, hardware reliability, or a current signed release artifact.

The inspected [v1.0.2 release](https://github.com/rubensdemelo/rio/releases/tag/v1.0.2)
was built from `6312b10`, three commits before the audit. Its DMG SHA-256 was
`d32e15eb61580cc492822a191dca459275d2e44ad81b3895d65fc0bf81c0bc0e`.
The inner app was universal, Developer ID signed, hardened, and notarized; the
outer DMG failed explicit signature assessment. Treat these as historical audit
observations and rerun checks on the candidate the team intends to ship.
