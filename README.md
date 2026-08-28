# Rio

> Stay in the meeting. Bring back the signal.

Rio is a small macOS meeting assistant for people who want to stay engaged in
the conversation instead of operating a recorder or taking continuous notes.
It listens to meeting audio and turns the important moments into concise,
useful insight cards.

Rio lives quietly in the menu bar. Start listening when the meeting begins,
keep your attention on the room, and review the signal when you need it.

## What Rio captures

- Important points and takeaways
- Decisions
- Action items
- Open questions
- Risks, blockers, and unresolved topics

Cards update as the conversation changes, so the stream stays focused instead
of becoming a wall of duplicates. Rio never invents an owner for an action
item, and it does not expose a live transcript.

## Get Rio

The latest notarized release is available here:

[Download Rio for macOS](https://github.com/rubensdemelo/rio/releases/latest)

You need:

- macOS 26 or later
- System Audio Recording permission
- An OpenAI API key

Install the DMG, drag Rio to Applications, launch it, then open **Provider**
from the menu bar and add your API key. The key is stored in your Mac’s login
Keychain; it is never bundled with Rio.

## A calm privacy boundary

Rio is designed around temporary meeting context:

- Audio is processed live and is not intentionally saved.
- Temporary speech-to-text context is discarded continuously.
- Finalized transcript segments and insight cards stay local for up to two days.
- The API key stays in the macOS Keychain.

Read the full [privacy and data lifecycle](docs/PRIVACY.md).

## The product boundary

Rio is an insight stream, not a recorder, note-taking app, transcript editor,
or meeting archive. The first release intentionally leaves out live transcript
display, speaker labels, audio playback, exports, accounts, integrations, and
cloud synchronization.

## Project map

- [Product vision](IDEA.md)
- [Product definition](docs/PRODUCT.md)
- [Privacy and data lifecycle](docs/PRIVACY.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Development guide](docs/DEVELOPMENT.md)
- [GitHub DMG distribution](docs/DISTRIBUTION.md)
- [Roadmap](docs/ROADMAP.md)
- [Writing extension plan](docs/WRITING_EXTENSION_IMPLEMENTATION_PLAN.md)

## Status

Rio is a focused technical preview for macOS 26+. The automated product and
release checks pass; direct hardware acceptance of meeting capture remains
part of the ongoing roadmap.
