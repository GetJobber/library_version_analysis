## 1. Canonicalization helper

- [x] 1.1 Add `LibraryVersionAnalysis::Ownership.canonicalize(name)` as a class method that implements the spec rule (stringify, strip whitespace, strip surrounding quotes, strip leading/trailing colons, downcase, fallback to `unknown` on empty).
- [x] 1.2 Add a comment above the method noting that it must stay in lockstep with `library_tracking`'s `Owner.canonicalize_team`.
- [x] 1.3 Add unit specs covering: colon stripping, quote stripping, downcase, `:attention_needed` symbol, empty/`nil`/whitespace fallback, and the idempotency requirement.

## 2. Apply at the payload seam

- [x] 2.1 In `CheckVersionStatus#server_data`, wrap the `owner` value in `LibraryVersionAnalysis::Ownership.canonicalize(...)` at the `libraries.push({...})` call site.
- [x] 2.2 Verify no other `payload[...]` builder includes the owner field (sanity check `vulns.push` and `new_versions.push`).
- [x] 2.3 Confirm `row.owner` is not mutated; only the payload entry is normalized.

## 3. Tests

- [x] 3.1 Extend `spec/check_version_analysis_spec.rb` (or add a focused spec file) covering the three payload scenarios: Gemfile-style `:bizops` input, `:attention_needed` symbol input, and quote-wrapped `"bizops"` input.
- [x] 3.2 Add a regression assertion confirming `row.owner` retains its pre-payload value after `#server_data` runs.
- [x] 3.3 Run `bundle exec rspec`; all specs pass.

## 4. Verification

- [ ] 4.1 Manual run: execute the gem against a sample repo and inspect the `[upload]` log output; confirm owner names are canonical.
- [ ] 4.2 Confirm payload sent to `library_tracking` contains canonical owner names by hitting a staging server or by intercepting the serialized payload in a spec.
