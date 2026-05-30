# Backend WireMock Stubbing Rules

## Scope

Applies to the single remaining Aspire WireMock stub helper:

- `tests/BuilderCatalogue.TestFramework.Aspire/WireMockUserStubsHelper.cs`

> **Note (HLD-12):** `src/BuilderCatalogue.AppHost/WireMockUserStubsHelper.cs` has been deleted. The dev AppHost no longer runs WireMock — it reads from the real upstream API directly. Only the test-framework copy remains.

## Rules

1. Keep the test-framework WireMock stub helper as the single source of truth for stub data shapes.
2. The stub usernames and unique identifiers must match the active seed fixtures/migrations (`DemoFixtures`).
