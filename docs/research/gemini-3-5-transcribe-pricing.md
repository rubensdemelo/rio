# Google Gemini 3.5 Transcribe: pricing and meeting-transcription findings

Research date: 2026-08-27. Scope: Google first-party sources only. Prices below are USD and may change; the linked pricing pages are authoritative for current billing.

## What Google announced

Google’s 2026-08-26 announcement introduces **Gemini 3.5 Transcribe**, a speech-to-text model intended for precise, formatted transcription. It exposes two separate model/API paths:

- **Live transcription:** `gemini-3.5-transcribe-live` through the Gemini Live API over a bidirectional WebSocket, for continuous low-latency speech-to-text.
- **File transcription:** `gemini-3.5-transcribe` through the Interactions API, for recorded audio, meetings, and call logs, with speaker attribution and word-level timestamps.

Source: [Google announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-5-transcribe/).

## API availability

The announcement says the developer and enterprise offerings are in **public preview** through the Gemini API/Google AI Studio and Gemini Enterprise Agent Platform. The official guides expose the Live model through the bidirectional Live API and the file model through the beta Interactions API; the REST examples use `v1beta` endpoints.

Sources: [Google announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-5-transcribe/), [Gemini 3.5 Transcribe model page](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe).

## Published pricing

### Gemini API / Google AI for Developers

The Gemini Developer API pricing page lists the following Standard paid-tier rates per 1 million tokens:

| Model path | Audio input | Text output | Google’s estimated effective rate |
| --- | ---: | ---: | ---: |
| `gemini-3.5-transcribe-live` | $3.50/M audio tokens, estimated $0.005/min | $21.00/M text tokens, estimated $0.004/min | approximately **$0.009/audio minute** |
| `gemini-3.5-transcribe` | $2.00/M audio tokens, estimated $0.003/min | $12.00/M text tokens, estimated $0.002/min | approximately **$0.005/audio minute** |

Google says these per-minute estimates assume 25 audio tokens/second and 175 text tokens/minute. The tables show both models as free of charge on the free tier, but mark free-tier content as **used to improve Google products**; paid-tier content is marked as not used for that purpose. That data-use distinction is material for private meetings. Applicable free-tier quotas and terms still need project-level verification.

Source: [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing).

### Google Cloud Gemini Enterprise Agent Platform

The Agent Platform pricing page lists the Live path at the same **$3.50/M audio input + $21.00/M text output**, with an estimated **$0.009/audio minute**. For synchronous file processing, however, that page lists **$2.50/M audio input + $12.00/M text output**, while still showing an estimated **$0.005/audio minute**.

That is a material published difference from the Gemini Developer API page’s $2.00/M audio-input rate for `gemini-3.5-transcribe`. A deployment decision should therefore select the intended Google surface first and obtain a current project-specific quote/calculation instead of assuming the two prices are interchangeable.

The Agent Platform page says requests failing with a 400 or 500 error are not charged for tokens, while filtered responses are charged for input only. It also says sub-cent totals are rounded to one cent at the end of each billing cycle.

Source: [Agent Platform Generative AI pricing](https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing).

## Billing details that matter for a live meeting

- The Live API is a persistent WebSocket session and bills by tokens, not a guaranteed flat per-minute charge; `$0.009/min` is explicitly an estimate based on assumed token rates.
- Google’s model-specific Agent Platform table says only final committed tokens are billed for Transcribe Live. Separately, the general Live API billing guide says active-context tokens can be reprocessed and billed on later turns, and generated transcription text is charged at the text-output rate.
- Google does not explain on these pages exactly how the model-specific “final committed tokens” statement reconciles with the generic Live context-window rules. Cost modeling should therefore use the selected endpoint’s actual usage records and confirm behavior during preview rather than simply multiplying meeting minutes by `$0.009`.
- The general Live guidance recommends context-window compression to limit compounding costs, but the Transcribe model itself still has a separate 10-minute session limit.

Sources: [Live API billing guidance](https://ai.google.dev/gemini-api/docs/live-api/best-practices#pricing-and-billing), [Agent Platform pricing](https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing), [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing).

## Material limitations and caveats

- **Live duration:** Google lists a maximum of **10 minutes per Live transcription session**. A meeting product would therefore need reliable session rollover and continuity handling for longer meetings.
- **File duration:** Unary audio supports up to **1 hour per request**, but the limit is **30 minutes** when speaker diarization or word-level timestamps are enabled.
- **Feature split:** Live streaming does not support word-level timestamps or speaker diarization. File processing supports both; diarization is listed for up to eight speakers, with attribution for three or more speakers described as experimental.
- **Accuracy trade-off:** Google notes that enabling word-level timestamps may reduce overall transcription accuracy.
- **Smart transcription trade-off:** Smart mode removes fillers, cleans false starts, resolves spoken corrections, and formats output. It is incompatible with word-level timestamps and diarization; use verbatim mode for those features.
- **Input contract:** Live transcription expects raw 16-bit PCM audio at 16 kHz mono, sent in 100 ms chunks. Google’s client example exposes WebSocket close/error callbacks; a meeting client still needs local capture supervision plus reconnect/rollover logic.
- **Language/custom vocabulary:** Google documents automatic detection across 85+ languages and up to 1,000 custom-vocabulary phrases, while recommending up to about 100 terms for best results.
- **API documentation mismatch:** The announcement and Gemini API guide place file transcription on the Interactions API, while the Agent Platform pricing table describes it as synchronous/batch processing through `GenerateContent`. Endpoint capabilities and billing should be confirmed on the exact deployment surface.
- **Preview status:** The offering is in public preview, so quotas, model behavior, limits, and prices should be rechecked before production adoption.

Sources: [Gemini 3.5 Transcribe model limits](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe), [audio transcription guide](https://ai.google.dev/gemini-api/docs/transcribe), [Live transcription guide](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe), [Google announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-5-transcribe/).

## Bottom line for the meeting use case

Google’s Live model is listed at an estimated **$0.009 per audio minute** on both published surfaces, but it has a documented **10-minute session limit** and billing guidance that is not safely reducible to a universal flat per-minute price. The file model is listed at about **$0.005 per minute**, but it is not the real-time path and has tighter limits when timestamps or diarization are required. For private meetings, paid-tier data handling is also materially different from the free tier. A production evaluation should therefore include session-rollover reliability, preview-limit checks, privacy review, and cost measurement from actual usage telemetry.
