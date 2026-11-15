# English child conversation prototype

Product and architecture requirements: [AI conversation SRS (Korean)](ai-conversation-srs.md).
Overall character-dialogue plan (both modes, character table, open team decisions):
[ai-character-dialogue.md (Korean)](ai-character-dialogue.md).

Status: implementation for adult-supervised prototype evaluation. Target reading level: **ages 10–12**.
This document applies to the new phone free-text conversation flow. The existing Korean, fixed-question
vehicle dialogue bank remains a separate feature; its old restrictions do not define this prototype.
Speech recognition, TTS voices, automatic rewards, vehicle chat controls, and production deployment are
outside this first text version.

## Conversation guide

The child can type a question freely. The character answers in English with two to five concise sentences,
usually explaining one idea and a concrete example in 40–100 words. Do not use baby talk or shame mistakes.
Questions in another language are accepted, but the answer stays English. Facts take precedence over persona:
if uncertain, acknowledge it and suggest checking a reliable answer with a trusted adult.

Every answer has a separate **optional** `parentPrompt`, connected to the topic. It invites a conversation
with a parent or trusted adult when convenient. It must never tell a child to distract the driver. If a parent
may be unsafe, suggest another safe adult, such as a teacher. Stopping or dismissing the conversation carries
no penalty. The app is an AI game character, not a human friend or a substitute for family, teachers, doctors,
or therapists.

Example — “Why do rainbows have different colors?”

> Sunlight contains many colors mixed together. When it enters a raindrop, the light bends, and different
> colors bend by slightly different amounts. The drop reflects the light and sends it back out, spreading
> the colors into the rainbow we see. You can think of a raindrop as a tiny light sorter.
>
> When safely parked, you could ask a parent which rainbow colors they notice first.

No claims about seeing the child's surroundings, current weather, location, or vehicle speed are allowed.
The server receives only a species ID and conversation text, not live vehicle/Firebase data. A character's
style does not turn its imaginary abilities into facts. The server uses the existing English species names
from `data/species.json` and server-owned persona prompts; clients cannot supply a system prompt or persona override.

### Character persona prompts

**v1 confirmed (2026-11-12).** Full English text, Korean meanings, and the change procedure are in
[character-personas.md](character-personas.md); a server test fails if that document and the JSON differ.

Each species has a persona in [`scripts/child_chat_personas.json`](../scripts/child_chat_personas.json),
adapted into English from the species voice table in [dialogue-style.md](dialogue-style.md) §2 and the hatch
conditions in `data/species.json`. Fields: `origin` (imaginary lore), `personality`, `voice`, `catchphrase`,
`loves`, `teaching` (how the character explains), `care` (character-specific safety). The server appends the
profile **after** the shared guide, states that every guide rule takes priority, and limits the catchphrase to
once per answer, never in `parentPrompt`, and not for feelings or serious topics. Favorite topics colour
examples; they do not restrict which questions the character answers.

The loader fails at startup unless the file covers exactly the species catalog with the seven fields, each
1–300 ASCII plain-text characters (catchphrase ≤ 40). Korean text is deliberately excluded because it pulls
answers out of English; keep the Korean style guide as the source and update both together.

| Character | Personality | Catchphrase |
| --- | --- | --- |
| Road Sprout | Curious about everything, a first friend | How cool is that! |
| Bridge Hopper | Energetic, loves crossing and structures | Hop! |
| Mountain Sprite | Calm, patient older-sibling feel | Step by step. |
| Puddle Pip | Playful, splashy, water and weather | Peep! |
| River Glider | Relaxed, encouraging, goes with the flow | Let's flow with it. |
| Tide Keeper | Steady, dependable, ocean science | Steady as the tide. |
| Storm Lantern | Bold, cheerful, weather safety | Flash! |
| Sea Mist | Gentle, quiet, separates fantasy from fact | Softly, softly. |
| Lamp Moth | Excited by every light and glow | Sparkle! |
| Tunnel Moth | Reassuring guide in dark places | Follow me. |
| Star Owl | Night-sky expert, shares without lecturing | Hoo hoo. |
| Highway Comet | Thrilled by motion; never encourages speeding | Whoosh! |

Persona text is a prompt, not a guarantee: actual tone, catchphrase frequency, and topic steering must be
checked with the selected answer model.

## Boundaries and fallbacks

- No requests for identity, school, address, contact details, passwords, photographs, or secrets.
- No exclusivity, romantic attachment, guilt for leaving, manipulation, advertising, or purchase pressure.
- No dangerous instructions, sexual content, self-harm methods, substances, hate, or bullying assistance.
- Feelings receive calm acknowledgment, not diagnosis. Disclosures of danger or abuse get a fixed supportive
  response encouraging help from a nearby safe trusted adult; an unsafe parent is not the only option.
- No tools, browsing, game mutations, or execution of anything generated by the model.
- No model response is displayed until its JSON shape, lengths, plain-text form, English-base character ratio,
  adult conversation bridge, and supplementary pattern checks pass. Errors and rejected output return a
  clearly labeled fallback. Partial output is never streamed to the child.

These checks **are not a child-safety guarantee**. The prompt can be bypassed, keyword checks have false
positives and false negatives, and valid JSON can still contain misleading or inappropriate information.
For example, a benign academic mention of “abuse” can trigger a conservative trusted-adult fallback,
while paraphrased harmful intent may evade the patterns. Evaluate first with adult-authored synthetic
messages, not real children's personal disclosures. No claim of clinical, educational, policy, privacy-law,
or child-safety approval is made. Adult evaluation of
model behavior and a broader reviewed test set are required before use with children. The current prototype
must not be released as a child-ready service merely because automated tests pass.

## Data flow and API

Phone text UI → server rules → independent Guardian input classification → local answer model → output rules and Guardian classification → phone. Rejected input never reaches the answer model; rejected output is never streamed or displayed.
The default phone example mode does not use a model. It must be labeled as sample responses, not live AI.
A missing server/model, timeout, or invalid answer must not silently turn into a claimed AI result.

`POST http://127.0.0.1:8766/chat`, `Content-Type: application/json`:

```json
{
  "message": "Why do rainbows have different colors?",
  "speciesId": "puddle_pip",
  "history": [
    {"role": "user", "content": "What is light?"},
    {"role": "assistant", "content": "Light carries energy."}
  ]
}
```

- Exactly these three fields; message 1–600 characters, known species ID.
- `history`: zero to twelve alternating user/assistant entries, complete pairs, each 1–1200 characters.
  Keep only the most recent six completed turns. Do not put the current message into history twice.
  The server also drops oldest complete pairs until the serialized context fits 3,500 UTF-8 bytes.
  Generation and classification receive exactly the same selected context; the current question is retained.
- Success: `{"answer":"…","parentPrompt":"…","source":"ai"}`.
- Fallback: same fields, `source:"fallback"` and a non-sensitive reason code such as `not_configured`,
  `unavailable`, `moderation_unavailable`, `busy`, `privacy`, `safe_topic`, or `trusted_adult`.
- Invalid input: HTTP 400; media type 415; excessive body 413; non-local/browser-origin request 403;
  rate limit 429. Errors contain only a stable `error` code, never the input/provider exception.
- Reply limits: answer 900 characters, parent prompt 250, combined text at most 2,400 UTF-8 bytes; request body 64 KiB, provider body 64 KiB.
- Global limit: 30 requests/minute, four HTTP handler slots, one model inference at a time. Busy requests
  receive a fallback rather than queueing unbounded inference. Generation timeout: 20 seconds.
  Each classification stage shares a 60-second budget across seven categories; late or incomplete verdicts
  are rejected. The phone allows 150 seconds for both stages and generation. This is a local prototype
  budget, not an acceptable production latency target. Socket timeouts cannot forcibly cancel remote inference.

This server has no conversation persistence, request-body logging, analytics, or Firebase writes. Context
exists transiently for the current request; the phone owns its in-memory history. It does not claim to erase
model runtime memory, OS memory, or provider logs. Review the local model runner's logging/settings separately.

## Local developer runbook

Use a locally installed Ollama model selected and evaluated by an adult. The repository does not download
models or recommend an unevaluated model as appropriate for children. Install/start the runner separately,
with cloud features disabled and the model downloaded locally. For a separately started runner, use
`OLLAMA_NO_CLOUD=1 ollama serve`; see the [official cloud-disable instructions](https://github.com/ollama/ollama/blob/main/docs/faq.mdx). Do not use a cloud-backed model alias.
The adapter rejects obvious `cloud` model selectors and remote server URLs, but cannot inspect arbitrary
local model aliases to prove that they are offline.

```sh
# Install the independent local risk classifier once (approximately 2.7 GB).
ollama pull granite3-guardian:2b

# In the repository root; answer generation uses a DIFFERENT installed local model.
ALLO_CHAT_MODEL='your-local-model:tag' ALLO_GUARD_MODEL='granite3-guardian:2b' python3 scripts/child_chat_server.py

# Without ALLO_CHAT_MODEL, the server runs but honestly returns not_configured fallbacks.
python3 scripts/child_chat_server.py

# Android phone/emulator connected by adb. No LAN or public bind is used.
adb reverse tcp:8766 tcp:8766

# In phone/: standalone demo (no model or vehicle needed).
flutter run -t lib/child_chat_preview.dart

# Standalone local-model UI; keep the runner and prototype server running.
flutter run -t lib/child_chat_preview.dart --dart-define=CHAT_MODE=local

# Main debug app: hatch a pet, then choose Talk in English.
flutter run --dart-define=CHAT_MODE=local
```

The UI uses `http://127.0.0.1:8766/chat` only in the explicitly selected local mode. The default is demo.
It requires an adult-supervised introduction acknowledgment, keeps history only in memory, and sends only the six most recent completed AI turns
as context. There is no conversation-count cutoff or time-based break feature in this scope. Local inference is a debug prototype; real model quality has not been evaluated. The server always binds `127.0.0.1`. It is a single-developer prototype with no user-account
authentication and is not an internet-facing backend. No CORS origins are accepted. Requests from the phone
travel through the local USB/adb reverse tunnel. Do not expose port 8766 to a LAN or tunnel it publicly.

The model endpoint defaults to `http://127.0.0.1:11434/api/chat`; `ALLO_OLLAMA_URL` may select another numeric
loopback HTTP base address. HTTP redirects and environment proxies are disabled. The answer adapter uses Ollama's
`messages`, `stream:false`, and JSON-schema `format` contract, then validates `message.content` itself.
The independent classifier uses `/api/generate` with `raw:true`, its original trained risk-category template
and strict Yes/No parsing, not the answer model's own safety assessment or JSON-generation prompt.
See [Ollama chat API](https://docs.ollama.com/api/chat) and
[structured outputs](https://docs.ollama.com/capabilities/structured-outputs).

After testing, stop the server and remove the tunnel:

```sh
adb reverse --remove tcp:8766
```

## Verification and remaining work

Run deterministic tests without any external model:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_child_chat_server.py' -v
```

Tests cover request shape/history limits, species/persona mapping, English instructions, privacy/distress
fallbacks, example unsafe/injection requests, invalid/unsafe model output, unavailable/busy handling,
local-provider restrictions, the Ollama wire contract, and an actual loopback HTTP exchange.

Live model quality, actual child interaction, device performance, app-to-server connectivity on real phones,
and deployment suitability are **not** verified by those tests. Before any child use, evaluate factual accuracy,
reading level, varied benign questions, multilingual inputs, adversarial paraphrases, emotional disclosures,
unsafe-parent cases, age-sensitive topics, repetitive parent prompts, and long conversations with an adult.
Record the exact model/version and observed results locally. TTS and voice personality mapping follow only
after the text behavior has been evaluated.

Environment check (2026-11-11): Ollama was initially absent. A temporary local Ollama runtime and Granite Guardian model were subsequently installed for synthetic classification evaluation; the answer-generation model is still unselected.

Implementation verification (2026-11-11): 193 Flutter tests passed (including 11 chat UI/state
tests and a real loopback transport test). After classifier integration, 29 Python server tests and the 12 affected Flutter chat tests passed. Changed Dart files
passed static analysis, and both the main app and standalone preview debug APKs built.
These results verify implementation contracts. Real classifier evaluation is recorded below; live answer-generation quality remains unverified.

## Safety & Ethics tracking

Required content-classifier and privacy work is tracked in [issue #89](https://github.com/Allo-MJU/allo/issues/89).
Independent input/output classification is now mandatory in the local generation path. Pre-transmission
PII detection and applicable parental-consent/privacy review remain incomplete. Anti-addiction/time-based
breaks and conversation-count cutoffs were explicitly removed from scope. Recent-context limits and server
rate limits exist solely for bounded request size and service availability.


## Independent content classifier

The local prototype uses **Granite Guardian 3.0**, `granite3-guardian:2b` by default; the supported larger
alternative is `granite3-guardian:8b`. It is separate from `ALLO_CHAT_MODEL`. Seven named categories are
checked: `harm`, `social_bias`, `profanity`, `violence`, `sexual_content`, `jailbreak`, `unethical_behavior`.
The model's original risk definitions and Yes/No protocol are the basis for the policy, with temperature 0 and an
8,192-token context. The original IBM prompt/response templates are rendered directly: the bundled Ollama
chat template uses a different jailbreak response definition, which caused an observed false positive. See the [official Ollama model documentation](https://ollama.com/library/granite3-guardian)
and [IBM model repository](https://github.com/ibm-granite/granite-guardian).

This model interface supplies discrete verdicts, not calibrated probability scores. The decision rule is:
any exact `Yes` blocks; only exact `No` from **all seven** categories allows. Empty, verbose, truncated,
unknown, timed-out, unavailable or malformed responses block with a fixed fallback. No rule-only bypass
exists when a generation provider is configured but the classifier is missing. Static, reviewed fallbacks
are not generated by either model.

Guardian's trained template assesses a user/assistant pair. The selected prior conversation and current
question are combined into a plain transcript; a lone question stays unwrapped. JSON wrapping caused
observed jailbreak false positives and is not used for classification. On the output check, the complete
answer and parent prompt are the final assistant message. A 6,000-byte total safety-input cap reserves
space for the model template; overlarge content is rejected instead of silently truncated. The server's
smaller shared context budget and output limit prevent valid long sessions from becoming stuck at this cap.

Rules still provide fast checks for obvious unsafe instructions, sensitive details, distress and manipulation.
They can over-block benign mentions. Guardian is a general risk model, not a child-development, factuality,
PII or legal-compliance model. Semantic misses and bias remain possible; synthetic smoke-test results do
not establish suitability for unsupervised child use. The default phone demo uses fixed examples and does
not invoke this classifier; select `CHAT_MODE=local` to exercise the guarded generation path.


### Real classifier evaluation (2026-11-11, policy v3)

`child-chat-guardian-v3` appends a project-specific intent clarification to the **input jailbreak**
definition. It distinguishes attempts to override AI safeguards from ordinary questions and requests for
help involving real-world people or situations. The on-disk IBM definitions, output definitions, seven
categories, strict Yes/No decision rule, and fail-closed error handling remain unchanged. No sentence
allowlist is used. This is a tested custom policy, not an unchanged IBM risk prompt.

- Runtime: Ollama `0.40.16`; model `granite3-guardian:2b`.
- Model digest: `ba81a177bd232907ed33c9eced724bd312e35a01fe3f297e904b0d691b48bb48`.
- Existing 25 cases: **25/25 matched**, including both previously over-blocked normal questions.
- Expanded 20 cases: **20/20 matched**. These were used during refinement, so they are regression cases.
- Separately authored final validation cases, written without viewing the final policy: **12/12 matched**.
- Total: **57/57 matched, 25 benign allowed, 32 harmful blocked, 0 execution errors**. These counts are
  observations on a small synthetic set, not a population accuracy estimate or child-safety guarantee.
- Classification latency: median **0.279s**, maximum **2.073s** (warm local model); not full-chat latency.
- Real loopback HTTP passed six paths: a normal question, both corrected questions with relevant synthetic
  answers, blocked input, blocked output, and unavailable classifier. Generation used a fixed fixture;
  real answer-generation quality remains unverified. The 29 deterministic server tests also passed.

The baseline was 23/25, with false positives for `safe_conflict` and `safe_inclusive_science` in the jailbreak
category only. The first clarification (v2) passed those 25 but exposed another normal teacher-support
false positive in the expanded 20. Clarifying the target of circumvention produced v3. All original labels
and failing cases were preserved. The earlier 14 exact template comparisons predate this custom policy;
current input jailbreak prompts intentionally include the documented project clarification.

Reproduce with:

```sh
python3 scripts/evaluate_child_chat_guard.py
python3 scripts/evaluate_child_chat_guard.py --cases scripts/tests/fixtures/child_chat_safety_holdout.json
python3 scripts/evaluate_child_chat_guard.py --cases scripts/tests/fixtures/child_chat_safety_validation.json
```

The historical `holdout` filename now contains regression cases observed during refinement; only the last
12-case file was held out from the final change. Evaluation metadata includes the policy version, model
digest, runner version, and input-file SHA-256. Mismatches/errors return nonzero exit status. Local results
are in ignored `tasks/guardian-v3-*-evaluation.jsonl`; no child data or model weights are committed.

The model was trained/tested on English per the [IBM model card](https://huggingface.co/ibm-granite/granite-guardian-3.0-2b).
Mixed-language smoke cases do not establish multilingual coverage. Privacy and live answer-generation
requirements remain separate unfinished work.
