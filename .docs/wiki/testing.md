# Testing Strategy

## Test Levels

| Level | Label | Scope |
|---|---|---|
| L0 | Unit | Isolated logic, no external dependencies |
| L1 | Component | End-to-end within a single bounded context, dependencies mocked or stubbed |
| L2 | Integration | Cross-boundary verification — external API clients, database, full request pipeline |
