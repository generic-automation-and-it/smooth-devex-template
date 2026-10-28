---
description: 'Backend WireMock stubbing — stub through the Aspire test-framework admin client, which is the single source of truth for stub shape'
globs: "tests/**/*.cs"
paths:
  - "tests/**/*.cs"
applyTo: 'tests/**/*.cs'
alwaysApply: false
---

# Backend WireMock Stubbing Rules

Updated: 2026-10-28

## Scope

WireMock runs as an Aspire test dependency (`wiremock/wiremock`, host port 19091), added by
`tests/Project.TestFramework.Aspire/DistributedApplicationBuilderExtensions.cs`. Stub through the test
framework, not the container directly:

- `tests/Project.TestFramework/Fixtures/AspireFixture.cs` → `CreateWireMockAdminClient()`
- `tests/Project.TestFramework/Fixtures/WireMockAdminClient.cs` → `ResetAsync()` and
  `StubJsonResponseAsync(method, path, responseBody, statusCode)`

## Rules

1. `WireMockAdminClient` is the single source of truth for stub shape. A test stubs through it; it never
   POSTs `__admin/mappings` itself.
2. Call `ResetAsync()` before stubbing so mappings and requests do not leak between tests.
3. Stub payloads must match the seed data the test's database actually holds — assert against the same
   identifiers, not copies invented in the test.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-10-28 | Retargeted to `WireMockAdminClient` + `AspireFixture`; scope widened to `tests/**/*.cs`; added Changelog |
