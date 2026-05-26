# Changelog

## v0.1.1 — Data Integrity Cleanup & UI Write-Time Guards

### Migration (one-time, idempotent)

A `MigrationService` runs once at app launch (`UserDefaults` flag `migration_data_correction_v1`) and applies eight data-correction operations to the live database using stable UUIDs. Each operation is pre-checked in-memory so re-running is safe.

Operations applied:
1. Fix broken claim — correct `objectEntityId`, clear stale `value`, attach `memoryId`
2. Add claim: Christina `has_role` "Therapist"
3. Add claim: NJHW `located_at` address entity
4. Add claim: Christina `recommended_resource` "psychologytoday.com"
5. Add alias "North Jersey Health & Wellness" for NJHW entity
6. Clear Christina entity notes (content promoted to claims/alias)
7. Clear NJHW entity notes (content promoted to claims/alias)
8. Add `MemoryEntityLink` joining the address entity to its source memory

### Guard 1 — Live entity resolution on literal value field (AddEditClaimView)

When typing in the object-value text field, a 300 ms debounced lookup calls `EntityResolutionService.findExactMatch`. If a matching entity is found, an inline banner offers "Link as entity" (flips mode, sets entity) or "Keep as text" (dismisses).

### Guard 2 — Auto-switch object mode from predicate (AddEditClaimView)

When the predicate field changes, `PredicateClassificationService.classify` determines whether the predicate is entity-typed or literal-typed. The object mode switches automatically if the object field is still empty, so the user lands on the right input mode without manual toggling.

### Guard 3 — Data Health scan for stranded values (DataHealthView under Settings)

`StrandedValueService.scan` fetches all claims whose `objectEntityId` is nil (i.e. literal `value` claims) for predicates classified as entity-typed, then attempts to match the value against existing entities using exact string matching (strong) or Levenshtein distance ≤ 2 (soft). The new **Data Health** screen (Settings → Data Health) lists results and lets the user promote a claim to an entity link, or create a new entity from the value.

### Guard 4 — Acronym / proper-noun alias suggestion (AddEditEntityView)

When saving an entity with a non-empty notes field, `AcronymAliasDetector` runs two checks before committing:
- **Acronym check**: if the canonical name is 2–6 all-caps letters and the word-initial letters of notes spell that acronym, offer to save notes as an alias and clear the notes field.
- **Short proper noun check**: if notes is ≤ 50 characters with no punctuation and all words are title-cased, offer the same promotion.

A confirmation dialog lets the user accept ("Add as Alias") or decline ("Keep as Notes") before the record is written.

### Guard 5 — Source-memory warning on unsourced claims (AddEditClaimView)

If the user taps Save on a claim that has no attached memory, a confirmation dialog intercepts the save and offers: "Attach Memory" (opens `MemoryPickerView` filtered to the subject entity's memories), "Save Without Source", or "Cancel". The actual write is deferred until the user makes an explicit choice.

### New services

| File | Purpose |
|---|---|
| `Persistence/MigrationService.swift` | One-time idempotent data-correction migration |
| `Services/PredicateClassificationService.swift` | Classify predicates as entity-typed, literal-typed, or unknown |
| `Services/StrandedValueService.swift` | Scan for stranded literal values; promote to entity links |
| `Utilities/AcronymAliasDetector.swift` | Detect acronym/proper-noun patterns in entity notes |

### New screens

| File | Purpose |
|---|---|
| `Features/Settings/DataHealthView.swift` | Scan and repair stranded-value claims (Settings → Data Health) |

### Unit tests (39 test methods across 5 files)

| File | Coverage |
|---|---|
| `EntityResolutionTests.swift` | findMatches, findEntity, findAlias, findExactMatch (8 tests) |
| `PredicateClassificationTests.swift` | Full set coverage for entity/literal/unknown classification (8 tests) |
| `AcronymAliasTests.swift` | checkAcronymAlias and checkShortProperNoun (12 tests) |
| `StrandedValueTests.swift` | scan, promote, Levenshtein, soft-match (7 tests) |
| `MigrationIdempotencyTests.swift` | Correct application, idempotency, empty-DB safety (3 tests) |

All tests use an in-memory `ModelContainer` (`isStoredInMemoryOnly: true`) and `@MainActor` isolation where SwiftData access is required.
