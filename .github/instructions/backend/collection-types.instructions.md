---
description: 'Choose collection type by intent; T[] for DTOs/outputs, List/HashSet for EF/mutation, Frozen/Span/etc per use case'
globs: "**/*.cs"
paths:
  - "**/*.cs"
applyTo: '**/*.cs'
alwaysApply: false
---

# Collection types

Updated: 2026-10-16

Scope: type selection beyond EF materialisation. `readonly-collections` owns `ToArrayAsync` vs `ToListAsync`; this rule owns which type (`T[]`, `HashSet`, `Frozen*`, `Span`, etc).

## Non-Negotiables

- **DTOs, responses, query outputs: `T[]`.** Never `List<T>`. Array signals fixed snapshot. Same JSON. Less overhead. No null-list ambiguity.
- **Never return deferred `IEnumerable<T>` across handler/DbContext boundary.** Materialise to `T[]` before return. Avoids multiple enumeration + disposed-context bugs.
- **Public contracts: `T[]` or `IReadOnlyList<T>` / `IReadOnlyDictionary<K,V>`.** Concrete `T[]` for DTOs; interface when caller must not mutate.
- **`List<T>` only when `Add`/`Remove`/mutate after creation.** Builder pattern. Else `T[]` + `ToArray()`.
- **EF entities exception.** Navigation: `ICollection<T> X { get; } = new List<T>()`. Many-to-many / dedup: `new HashSet<T>()`. Tracked queries: `ToListAsync`. No-tracking reads: `ToArrayAsync` (see `readonly-collections`).
- **`HashSet<T>` for uniqueness.** `Contains` O(1). Set ops (`ExceptWith`, `IntersectWith`, `UnionWith`). Not for ordered/indexed access.
- **`FrozenDictionary<K,V>` / `FrozenSet<T>` for static read-heavy.** Built once (startup, lookup table), read often. High create cost. Fastest reads. Never when mutated per request.
- **`PriorityQueue<TElement,TPriority>` for priority order.** Scheduling, top-N, work queues. Not manual `Sort` + `RemoveAt(0)`.
- **`Queue<T>` FIFO, `Stack<T>` LIFO.** Never `List` + `RemoveAt(0)` (O(n)) for queue behaviour.
- **`Span<T>` / `ReadOnlySpan<T>` / `Memory<T>` for hot-path slicing.** Parsing, buffers, no-alloc substrings. Stack-only (`Span` = `ref struct`). Never in DTO/entity/public async signatures. Use `Memory<T>` across `await`.
- **`ImmutableArray<T>` / `ImmutableDictionary<K,V>` for shared publish-once.** Cross-thread config, safe publication. Not for high-mutate paths (O(log n) writes).
- **`ConcurrentDictionary<K,V>` / `Channel<T>` for concurrent.** Multi-thread writes / producer-consumer. Else plain `Dictionary` + lock. Never `Dictionary` shared unsynchronised.

```csharp
// Yes — DTO fixed snapshot
public sealed record OrderDto(Guid Id, string[] Lines);

// Yes — EF navigation, mutable tracking
public ICollection<OrderLine> Lines { get; } = new List<OrderLine>();

// Yes — many-to-many dedup
public ICollection<Tag> Tags { get; } = new HashSet<Tag>();

// Yes — static lookup, read often (needs System.Collections.Frozen)
static readonly FrozenDictionary<string, string> Map =
    new Dictionary<string, string> { ["usd"] = "USD" }.ToFrozenDictionary();

// Yes — hot path, zero-alloc, length-guarded
bool TryParseYear(ReadOnlySpan<char> input, out int year)
{
    year = 0;
    return input.Length >= 4 && int.TryParse(input.Slice(0, 4), out year);
}
```

```csharp
// No — List on DTO / frozen output
public sealed record BadOrderDto(Guid Id, List<string> Lines);
List<Item> bad = await db.Items.AsNoTracking().ToListAsync(ct);
```

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-10-16 | Created. Extends `readonly-collections` (DTO `T[]` rule). Sources: MS Learn collections, EF one-to-many. |
