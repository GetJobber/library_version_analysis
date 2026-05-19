## Context

This gem analyzes a repository's dependency tree and produces an upload payload that `library_tracking` ingests. Owner team names enter the in-memory data model from several parser paths:

| Source                                | Example value emitted    | Notes                                                                 |
| ------------------------------------- | ------------------------ | --------------------------------------------------------------------- |
| `gemfile.rb#add_ownership_from_gemfile` | `":bizops"`              | Regex `/\s*jgem\s*(\S*),\s*"(\S*)"/` captures the symbol verbatim     |
| `gemfile.rb` with quoted owner        | `"\"bizops\""`           | Same regex captures quotes when style is `jgem "bizops", "..."`       |
| `gemfile.rb#add_ownership_from_gemspecs` | `":bizops"`              | Explicitly prefixes `:` if missing; no trailing-colon defence         |
| `npm.rb`, `pnpm.rb`                   | varies by YAML / config  | Whatever the workspace ownership config contains                      |
| `configuration.rb` special-case map   | varies                   | Raw YAML values                                                       |
| `ownership.rb#add_attention_needed`   | `:attention_needed`      | Ruby symbol; serializes as `"attention_needed"` via `to_json`         |

Every one of these paths terminates at one place: `CheckVersionStatus#server_data`, which loops over `results` and calls `libraries.push({name: ..., owner: row.owner, ...})`. That is the single seam through which the value reaches the upload payload.

## Goals / Non-Goals

**Goals:**

- One canonicalization rule, defined once, applied at one place.
- Identical rule to the server-side `Owner.canonicalize_team` rule so both repos agree on canonical form even when versions skew.
- Idempotent and deterministic: `canonicalize(canonicalize(x)) == canonicalize(x)`.
- Preserve the in-memory `Versionline.owner` value so parsers, logging, and unit tests that inspect intermediate state are unaffected.

**Non-Goals:**

- Normalizing at the parser level. Multiple call sites means duplication and drift risk.
- Touching the Ruby symbol vs string distinction in the data model. `Versionline.owner` may continue to be a `Symbol` (`:attention_needed`, `:unspecified`) or a `String`. The canonicalizer accepts both.
- Changing what `Ownership#unknown_owner?` considers unknown. That predicate operates on in-memory parser state, not on outbound payload state.
- Handling `frontend_foundations` typo cleanup — explicitly deferred.

## Decisions

### Decision: Canonicalization rule (mirrors server)

```ruby
def self.canonicalize(name)
  s = name.to_s.strip
  s = s.gsub(/\A["']+|["']+\z/, "")
  s = s.gsub(/\A:+|:+\z/, "")
  s = s.strip
  s = s.downcase
  s.empty? ? "unknown" : s
end
```

This is byte-for-byte the same rule the server applies. Two repositories, one rule. If the rule ever needs to change, both repos update together — by convention captured in this design doc and in the server change's design doc.

Alternative considered: weaker stripping (only `:`). Rejected for the same reason as the server: the Gemfile regex captures quote characters too, so quote-wrapped names are a real source of variation.

### Decision: Apply at one seam — `#server_data`

The function `CheckVersionStatus#server_data` is where in-memory parser results become an outbound payload. Apply `Ownership.canonicalize` to `row.owner` when constructing the `libraries.push({...})` hash. The same value is also referenced from `vulns.push(...)` and `new_versions.push(...)` but those don't include the owner field, so a single edit covers the payload's owner surface.

Alternative considered: a `before_serialize` hook on `Versionline`. Rejected as overkill — there is no serialization framework here, just a manually-built hash.

Alternative considered: apply at parser level (inside `gemfile.rb`, `pnpm.rb`, etc.). Rejected — invites drift between parsers, makes unit tests interpret raw parser output differently, and produces no behavioural benefit since nothing else consumes parser output before `#server_data` does.

### Decision: Keep `Versionline.owner` untouched

Some parser paths use `row.owner == :attention_needed` for control-flow decisions (e.g. counting `unowned_issues` in `mode_summary`). Canonicalizing in-place would convert those symbols to strings and break the equality check. Confining normalization to the outbound payload sidesteps the problem entirely.

## Risks / Trade-offs

- **Risk**: a downstream tool reads the `[upload]` debug log and is surprised that the rendered owner names look different. → Mitigation: this is a strictly improving change (names get cleaner), and the log output is for operator inspection.
- **Risk**: payload size increases because every owner is recomputed instead of passed by reference. → Negligible — same string length category, single `Library` row per library.
- **Trade-off**: we apply normalization only on the outbound side, so the gem's internal data model can still carry raw parser output. That is intentional (see decisions) but means a future contributor reading `row.owner` could be surprised to find it differs from what the server sees. The canonicalization function and its single call site should be commented to flag this.

## Migration Plan

No data migration. This is a code-only change that affects future uploads only. Ship via the usual release cycle; consumers do not need to coordinate. If the server change (`normalize-owner-team-names` in `library_tracking`) has not yet shipped, this gem change is still safe: it produces strictly cleaner inputs to an unchanged server.

## Open Questions

None.
