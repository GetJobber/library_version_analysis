## ADDED Requirements

### Requirement: Canonical owner name function

The gem SHALL expose `LibraryVersionAnalysis::Ownership.canonicalize(name)` that returns the canonical form of any input. The canonical form is produced by: stringifying the input, stripping outer whitespace, stripping any surrounding `"` or `'` characters, stripping any leading or trailing `:` characters, stripping outer whitespace again, downcasing, and replacing an empty result with the literal string `unknown`. The function MUST be idempotent: `canonicalize(canonicalize(x))` returns the same value as `canonicalize(x)` for every input.

#### Scenario: Strips leading and trailing colons
- **WHEN** the input is `:bizops:`
- **THEN** the result is `bizops`

#### Scenario: Strips wrapping quotes captured by the Gemfile regex
- **WHEN** the input is `"bizops"` or `'bizops'`
- **THEN** the result is `bizops`

#### Scenario: Downcases mixed case
- **WHEN** the input is `:Bizops`
- **THEN** the result is `bizops`

#### Scenario: Handles Ruby symbols
- **WHEN** the input is `:attention_needed` as a Ruby `Symbol`
- **THEN** the result is `attention_needed`

#### Scenario: Empty or punctuation-only input falls back to unknown
- **WHEN** the input is the empty string, `nil`, only whitespace, or only colons/quotes
- **THEN** the result is `unknown`

#### Scenario: Function is idempotent
- **WHEN** the input is any string `s`
- **THEN** `canonicalize(canonicalize(s))` equals `canonicalize(s)`

### Requirement: Upload payload owner values are canonical

The gem SHALL apply `Ownership.canonicalize` to every owner value placed into the upload payload by `CheckVersionStatus#server_data`. The in-memory `Versionline.owner` field MAY retain its pre-canonicalization value; only the outbound payload is required to be canonical.

#### Scenario: Gemfile-sourced owners are stripped of colons in the payload
- **GIVEN** a parser populates `row.owner` as `":bizops"`
- **WHEN** `CheckVersionStatus#server_data` builds the upload payload
- **THEN** the corresponding entry in `payload[:libraries]` has `owner` equal to `bizops`

#### Scenario: attention_needed symbol becomes the canonical string in the payload
- **GIVEN** a parser populates `row.owner` as the Ruby symbol `:attention_needed`
- **WHEN** `CheckVersionStatus#server_data` builds the upload payload
- **THEN** the corresponding entry in `payload[:libraries]` has `owner` equal to `attention_needed`

#### Scenario: In-memory Versionline.owner is unchanged
- **GIVEN** a parser populates `row.owner` as `:attention_needed`
- **WHEN** `CheckVersionStatus#server_data` runs
- **THEN** `row.owner` still equals `:attention_needed` after the payload is built
- **AND** downstream logic that branches on `row.owner == :attention_needed` continues to work
