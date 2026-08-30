## Why

LIBTRACK-132: `library_tracking`'s Owners tab shows duplicate rows for the same team (e.g. `:bizops`, `bizops`, `:bizops:`) because the upload payload produced by this gem contains owner names in whatever shape each parser happens to extract — colons leak in from Ruby symbol syntax, quotes leak in from Gemfile regex captures, and the `:attention_needed` symbol serializes inconsistently with other sources. While the server is being hardened in parallel to canonicalize on write, fixing the source means future uploads are clean regardless of which gem version is talking to which server, and operators reading the payload logs see canonical names instead of raw parser output.

## What Changes

- Introduce a single canonicalization helper, `LibraryVersionAnalysis::Ownership.canonicalize` (class-level), that returns the canonical form of any owner name.
  - Canonical form: stringify, strip surrounding whitespace, strip surrounding `"` and `'` characters, strip leading and trailing `:` characters, strip whitespace again, downcase. An empty result becomes `unknown`.
- Apply the helper at the single seam where upload payloads are assembled: `LibraryVersionAnalysis::CheckVersionStatus#server_data`, immediately before each `libraries.push({...})` call. This ensures every parser path (Gemfile, gemspec, pnpm, npm, special-case YAML, transitive ownership, `:attention_needed` placeholder) goes through one normalization point.
- No changes to parser internals. The in-memory `Versionline.owner` field continues to carry whatever the parser produced; only the outbound payload is normalized.
- Out of scope: this change does not touch any `library_tracking` server code, does not migrate or rewrite any existing data, and does not address the `frontend_foundations` naming variants (those will be handled manually per ticket guidance).

## Capabilities

### New Capabilities

- `owner-name-canonicalization`: canonical owner name handling for outbound upload payloads.

### Modified Capabilities

None. There are no existing `openspec/specs/` entries in this repository.

## Impact

- Code: `lib/library_version_analysis/ownership.rb` (new class method), `lib/library_version_analysis/check_version_status.rb` (single call site in `#server_data`).
- Tests: add unit specs for the helper; extend existing `check_version_analysis_spec.rb` (or add a focused spec) to confirm the payload is canonical for representative inputs.
- Consumers: `library_tracking`'s `/api/libraries/upload` endpoint will receive canonical names. Behaviour is unchanged because the server is being updated to normalize on write anyway — this change just means the server's normalization is a no-op for payloads from current versions of the gem.
- Logs: the `[upload]` log lines emitted by `log_server_payload` will show canonical names, making operator review easier.
- Risk: very low. The transformation is idempotent and deterministic; downstream code paths that store owner names see the same or stricter spelling, never a new variation.
