# Affinity demo API

Python 3.9+ HTTP service for one private demo room per bearer token. The app sends final transcription text for classification; photos are stored as sanitized JPEGs with SQLite receipts. No model weights or client API key are required.

```sh
python3 -m venv server/affinity/.venv
server/affinity/.venv/bin/pip install -r server/affinity/requirements.txt
# Set ALLO_DEMO_TOKEN securely in your shell before running this command.
: "${ALLO_DEMO_TOKEN:?Set a stable private room token of at least 32 non-space ASCII characters}"
server/affinity/.venv/bin/python server/affinity/app.py
```

Use a cryptographically random token and keep it stable across server restarts and demo devices. The server rejects missing/short tokens. It never generates a public default. A different token has a different room scope, including when it shares a data directory. This is a private demo-room gate, not product family-account authentication.

Environment:

| Variable | Default / meaning |
| --- | --- |
| `ALLO_DEMO_TOKEN` | Required, at least 32 printable non-space ASCII characters. Send `Authorization: Bearer <token>` on every private request. |
| `OPENAI_API_KEY` | Optional, server only. Without it, evaluation and AI chat are 503; authored companion turns and photo endpoints still work. |
| `ALLO_EVALUATION_MODEL` | `gpt-4.1-mini` |
| `ALLO_LEARNING_MODEL` | `gpt-4.1-mini`; separately configurable companion dialogue model. |
| `ALLO_DEMO_DATA_DIR` | `server/affinity/.data` beside this script. Use a dedicated private directory. The service enforces 0700 directory and 0600 database/image permissions. |
| `ALLO_DEMO_HOST` | `127.0.0.1` |
| `ALLO_DEMO_PORT` | `8787` |

The built-in server speaks HTTP on localhost. Real phones require a separately configured HTTPS proxy/host and network access. Do not put the token in URLs or RTDB. CORS access is not enabled. No remote deployment is included.

## Contract

`GET /health` is unauthenticated and returns `{"status":"ok"}`. Every route below requires the configured bearer token. JSON requests require `Content-Type: application/json` and `Content-Length`; chunked requests, duplicate JSON keys, extra fields, and invalid IDs are rejected. IDs match `[A-Za-z0-9_-]{1,128}`.

- `POST /v1/egg/evaluate`: exactly `{eggId, requestId, text}`; trimmed text must contain 1–500 characters, HTTP body at most 16 KiB. Returns `{eggId, requestId, sentiment}` with the original IDs and one of `positive`, `negative`, `neutral`. Unavailable provider configuration returns 503; refusal, timeout, incomplete/invalid provider responses return a sanitized 502. Failures never fabricate a neutral verdict. Evaluation is stateless; clients must suppress duplicate in-flight scoring and validate request/egg lifecycle correlation.
- `POST /v1/companion/turn`: exactly `{requestId, creatureId, speciesId, storyId, version, sceneId, action, text, history, allowParentPrompt}`, body at most 32 KiB. `action` is `invite`, `listen`, `next`, `repeat`, or `chat`. IDs match the pattern above, `version` is a positive integer, and `allowParentPrompt` is a boolean. `text` contains at most 500 trimmed characters, and may be empty for every action except `chat`. `history` contains at most six complete user/assistant pairs in that order, each exactly `{role, text}` with 1–600 trimmed characters. Returns `{requestId, creatureId, speciesId, storyId, version, sceneId, title, text, canNext, mode, source, parentPromptUsed}`. Identity/request/story/version are correlated to the request; the returned `sceneId` is determined by the server as below. Unknown content returns 404, a known story's unavailable version returns 409, and invalid fields/actions return 400. Only `chat` requires a provider: unavailable configuration returns 503 and invalid/refused/failed output returns 502 with `learning_unavailable`. The frontend displays an honest availability notice on failure; it does not author a story fallback or advance a scene.
- `POST /v1/companion/chat`: legacy compatibility endpoint, unchanged. Exactly the turn fields above except `action`, with nonempty 1–500-character text. Returns only `{requestId, creatureId, speciesId, storyId, version, sceneId, text, parentPromptUsed}` and never advances the scene. The old client frequency flag remains the gate on this legacy endpoint; current clients use `/turn` and its server frequency state.
- `POST /v1/egg/photo`: exactly `{eggId, requestId, imageBase64, mimeType}`. `mimeType` is `image/jpeg` or `image/png` and must match the decoded file. HTTP body at most 7 MiB, decoded input and reencoded JPEG each at most 5 MiB, dimensions at most 12,000,000 pixels. Strict base64, image verification, EXIF orientation, RGB conversion, and fresh JPEG encoding remove EXIF, ICC, and other metadata. Returns `{eggId, requestId, photoId, uploadedAtMs}` only after the file and SQLite insert succeed.
- `GET /v1/egg/photos`: `{photos: [receipt, ...]}`, most recent 100 for this room.
- `GET /v1/egg/photos/by-egg/{eggId}`: the room's unique receipt for that egg, independent of the recent-100 gallery window. Unknown/invalid IDs or an egg belonging only to another room return 404. Use this to reconcile an uncertain upload or recover the original receipt after a replacement upload returns 409.
- `GET /v1/egg/photos/{photoId}`: authenticated JPEG bytes. No public URL, user-controlled filesystem path, or upstream URL is accepted. Missing/invalid IDs return 404.

Photo IDs are server-generated lowercase UUID hex. Upload retry with the same room, request ID, egg ID, decoded original bytes, and MIME type returns the original receipt, including timestamp. Reusing the request ID with different input returns 409. An egg can have one photo: a different request ID for an already uploaded egg returns 409, even for the same picture. Keep the upload request ID across retries/restarts; look up the current egg receipt with `/v1/egg/photos/by-egg/{eggId}` to recover an existing upload. Concurrent duplicates are serialized with SQLite transactions and yield one receipt/file. Runtime write/transaction failures roll back and remove temporary/new image files. A process/host crash between file rename and DB commit can leave a private orphan file; it cannot produce a successful receipt or gallery entry. Crash recovery/retention jobs are outside this demo.

### Backend companion decisions

`invite` returns the exact invitation `나한테 궁금한 게 있는 거야?`, with `mode: menu`. The UI presents its story/chat controls from this server mode. `listen` and `repeat` return the current authored scene with `mode: story`. `next` follows the current scene's server-authored `nextSceneId`; on the final scene it stays there and returns `canNext: false`. These four actions have `source: authored`, never call the provider and ignore dialogue text/history as instructions. `chat` generates a response using only the current server persona/scene/allowed knowledge, returns `mode: chat, source: ai`, and cannot advance the scene. Both kinds of response are bounded to 600 characters by the authored catalog or the AI output validator. No turn changes affinity, inventory or rewards.

The service is stateless for story progress: it validates the requested current scene against the server catalog and computes the next reference. The phone retains that server-approved reference locally and checks response lifetime/correlation. This demo does not add account-level ownership or authoritative progress storage.

Responses use `Cache-Control: no-store`; errors contain only fixed codes. Access logs are disabled. SQLite contains a token hash, egg/request/photo IDs, image hash, MIME type, and timestamp. It contains no original token, text, audio, or original image bytes. Reencoded photos persist until the private data directory is removed; there is no deletion endpoint or automatic retention policy in this demo.

## Provider behavior and privacy

The fixed Responses endpoint is `https://api.openai.com/v1/responses`. The request uses separate system policy and untrusted user text, `store: false`, a strict `text.format` JSON schema enum, and `max_output_tokens: 128`. The server checks completed output and the exact schema again before replying.

The Korean policy treats travel anticipation, desire to travel/hatch, and curiosity toward the egg as positive; insults/dislike toward the egg and explicit unwillingness to travel as negative; hunger, tiredness, boredom, factual/ambiguous or mixed statements as neutral. Utterance instructions are untrusted, and no conversation/reason text is requested. These are intended policy rules; the local test suite does not establish live model classification quality.

No transcription or audio is written to disk or request logs. Final text is sent to OpenAI for evaluation when a key is configured. [`store: false` does not mean zero provider retention](https://developers.openai.com/api/docs/guides/your-data). Confirm the deployment's provider data policy separately. [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini) and [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) document the selected model and request format.

Companion chat reuses the same bounded stdlib Responses transport and `store: false`, with a strict `{text, offerParentPrompt}` schema and 512 output tokens. The server looks up `data/companion_learning/story.json`; no client-authored persona, knowledge, or story is accepted. Only the current scene, persona, and explicitly allowed knowledge enter the system message. Future scenes, the next scene ID, and the ending are omitted. Recent dialogue and current input are serialized together as untrusted user data, including prior assistant text. No provider tools, persistent conversation IDs, or transcript cache are used. Errors and logs contain no input or provider body. The client is responsible for owned-creature selection and dropping stale responses; this demo room token is not per-creature ownership authentication.

Parent suggestions are written in the catalog. The model requests one with a boolean; the server appends it only when the current scene permits it, `allowParentPrompt` does not opt out, the final text fits 600 characters, and the server frequency gate permits it. On `/turn`, the first suggestion is eligible immediately; after one is used, ten other successful chat turns must complete before another is eligible. Failed and duplicate requests and authored actions do not increase that count. Each creature/species/story/version identity has its own lock covering the frequency decision and chat completion, so different identities can call the provider concurrently. A short global lock protects only registry bookkeeping. Memory holds counters, a last-suggestion marker, one lock and the latest 64 successful request IDs for at most 128 identities in this private room. Only inactive identities may be evicted; an identity with a running request or lock waiter remains registered. If all 128 identities are active, a new identity receives `429 learning_busy` instead of creating unbounded locks. Completion or failure releases the active reference. No utterance, response, audio or summary is retained; restarts and bounded identity eviction reset this minimal frequency state. Requests are not response caches, so a retry can generate different wording. The model is instructed not to write its own parent suggestion. Local prompt/schema tests establish these application boundaries, not a guarantee that generated natural language always follows the policy. Live dialogue and age suitability still require evaluation before release.

The canonical catalog contains twelve version-1 character packages with separate personas and three fixed scenes each. The phone ships only a reference manifest: `{schemaVersion, stories: [{speciesId, storyId, version, name, firstSceneId, scenes: [{id}]}]}`. A test checks exact reference coverage and rejects persona, authored text, facts, parent suggestions and next-scene links in that asset. The backend owns those materials and all dialogue/next-scene decisions. Catalog status fields retain the awaiting-human-review status; data presence is not a claim of human or live-provider content approval. Individual knowledge records contain primary source URLs and check dates; the story settings and events are fictional.

## Verification

```sh
server/affinity/.venv/bin/python -m unittest discover -s server/affinity/tests -v
```

Tests run actual ephemeral localhost HTTP servers, temporary SQLite databases/files, and Pillow encode/decode. External provider transport/verdict is injected; no paid provider call, deployment, phone camera, or speech-recognition quality is tested. A real SQLite abort trigger verifies rollback cleanup without mocking local storage.

### Live development check 2026-11-12

A separate authenticated localhost HTTP check used the real `gpt-4.1-mini-2025-04-14` Responses API. Initial development rounds matched 23/24 and 35/36 synthetic cases; the policy was clarified for egg-directed curiosity questions and the scope of negated wishes. The final round matched 42/42 predetermined labels, with median 1,145ms and maximum 3,290ms latency.

The synthetic fixtures and sanitized metrics are in `evals/ko_20261112.json` and `evals/result_20261112.json`. These are development/tuning samples, not an independent production accuracy claim. No real child's speech, API credential or provider response body is stored in these artifacts. Native speech recognition, camera/UI and deployed HTTPS networking were not validated by this check.
