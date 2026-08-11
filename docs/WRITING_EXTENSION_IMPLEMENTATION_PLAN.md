# Rio Writing Extension Implementation Plan

## Objective

Deliver one end-to-end Grammarly-like writing action without requiring users
to enable macOS Services:

> Select text in Safari → choose Rio Proofread → Rio opens a validated preview
> → accept only if the selection is unchanged.

MacOS Services remain an optional compatibility fallback, not the primary UX.

## Scope and non-goals

### In scope for the first vertical slice

- Safari Web Extension for arbitrary HTTPS pages, including Slack web.
- A small inline action surface with Proofread and Concise.
- Bounded selected text (maximum 8,000 UTF-8 bytes).
- A revision hash and origin metadata on every request.
- A signed native messaging host named `com.rio.app`.
- An authenticated app-group bridge between the extension host and the running
  Rio app.
- Rio preview, accept, dismiss, stale-selection rejection, cancellation, and
  no-content logging.
- Native app keeps the OpenAI credential and style profile; the extension and
  host never receive either.

### Explicitly out of scope for this slice

- Slack desktop integration. It is an Electron/native-editor problem and needs
  a separate Accessibility or supported-plugin decision.
- Chrome and Edge distribution. Reuse the JavaScript after the Safari path is
  proven, then add browser-specific native-host manifests and installers.
- Automatic typing inspection, password fields, incognito/private windows, or
  background page capture.
- Automatic replacement without an explicit Rio preview acceptance.
- New model providers, accounts, sync, telemetry, or draft history.

## Architecture

```text
Safari page selection
        │
        v
Safari Web Extension content script
        │  bounded request + revision hash
        v
Safari extension native handler
        │  app-group request/response broker
        v
Rio native bridge (main app)
        │
        v
WritingProofreading / OpenAIWritingAdapter
        │
        v
WritingAssistantShell preview
        │
        ├── Accept: replace only when revision still matches
        └── Dismiss/Undo: clear ephemeral proposal
```

The browser-facing interface is the existing `BrowserWritingRequest` and
`BrowserWritingResponse` seam. Keep the extension protocol versioned and
Codable. Reject malformed versions, empty IDs, unknown commands, oversized
text, invalid origins, and stale revisions before any model call.

## Work packages

### W1 — Freeze the interface and remove misleading claims

- Review `Rio/BrowserWritingProtocol.swift` for the final wire fields and
  response states.
- Make the native bridge accept only the request seam; it must not expose
  Keychain, OpenAI, or style-profile objects to callers.
- Keep current Services code as fallback, but label it as such in UI/docs.
- Add protocol tests for malformed JSON, size limits, unknown versions,
  duplicate request IDs, and stale revisions.

### W2 — Generate and integrate a real Safari target

- Run `xcrun safari-web-extension-packager` from `BrowserExtension/` into a
  dedicated `RioSafariExtension` app-extension target.
- Add the generated target to the project and embed its `.appex` in `Rio.app`.
- Set the Safari web-extension bundle identifier and signing team explicitly.
- Add the extension's `NSExtension` metadata and copy the manifest/resources.
- Add a release/dev build check that the built app contains
  `Contents/PlugIns/*.appex` and the expected manifest.

### W3 — Implement the native messaging host

- Add a dedicated `RioNativeMessagingHost` executable target; do not point the
  browser at `Rio.app/Contents/MacOS/Rio`.
- Implement Chrome/Safari native-message framing as length-prefixed UTF-8 JSON
  with a maximum frame size of 1 MiB.
- Validate request IDs, command, origin, revision, and selected-text bounds at
  the host boundary.
- Keep host stdout protocol-only; diagnostics go to content-free stderr.
- Add a host manifest/install script for development. Do not silently write
  browser host manifests outside the repository.

### W4 — Add the authenticated app-group bridge

- Add a narrowly scoped app-group entitlement shared by Rio, the Safari
  extension, and the host/helper as required by the chosen signing model.
- Use an authenticated Unix-domain socket or equivalent broker. Generate a
  per-launch capability token; never use an unauthenticated localhost port.
- Define request, response, timeout, cancellation, and Rio-restarted states.
- Store only in-flight request envelopes in memory or a short-lived broker
  location; delete them on completion, cancellation, timeout, or shutdown.
- Do not write selected text, proposals, or API credentials to logs.

### W5 — Wire Rio to the existing writing coordinator

- On a valid browser request, create a `WritingTextSnapshot` with the supplied
  revision and origin metadata kept separate from user-visible text.
- Reuse `WritingProofreading` for local checks and `OpenAIWritingAdapter` for
  explicit cloud commands.
- Present the existing `WritingAssistantShell` preview.
- Return a proposal response to the extension without applying it.
- Accept only after a second revision check against the active page selection.
- Return explicit errors for missing Rio, missing API key, cancellation,
  timeout, stale selection, and malformed model output.

### W6 — Make the page interaction real

- Keep the inline action surface visually small and keyboard accessible.
- Support contenteditable fields and textareas first.
- Detect password/secure fields and fail closed.
- Hide the action surface when the selection is empty, oversized, changed, or
  outside an editable/selected context.
- Do not auto-capture surrounding page text.
- Add an explicit “Rio is not running” and “Selection changed” state.

### W7 — Verification and handoff

- Add a deterministic protocol/host test harness that sends a framed request
  and asserts a framed response.
- Add a Safari manual test matrix: plain page, Slack web, textarea,
  contenteditable, empty selection, stale selection, Rio stopped/restarted,
  missing API key, network failure, password field, private window, and
  extension disabled.
- Build Debug and Release with signing; inspect the final `.app` for the
  `.appex`, host resource, entitlements, and manifest.
- Run `make final` and the extension lint target.
- Do not mark the milestone complete until the Safari selection-to-preview
  workflow is demonstrated on a signed build.

## Acceptance criteria

The implementer is done only when all of these are true:

1. No System Settings or Services checkbox is required for Safari.
2. Selecting text exposes Rio's inline action surface in Safari.
3. Proofread opens Rio with the exact bounded selection and no credential leak.
4. A stale or changed selection is rejected instead of overwritten.
5. Accept applies only the validated proposal; dismiss leaves the source intact.
6. Rio stopped, bridge unavailable, missing key, timeout, and network failure
   have clear recoverable states.
7. The extension does not persist drafts or log selected text.
8. Slack desktop is explicitly reported as unsupported until its own adapter is
   implemented.

## Rollback rule

If W2–W5 cannot produce the Safari selection-to-preview path, remove the unused
browser scaffold from the product build and retain only the tested writing core
and optional Services fallback. Do not add more UI or model code to compensate
for a missing transport.
