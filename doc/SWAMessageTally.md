# SWAMessageTally -- Sampling Profiler, Flamegraph & Treemap for Squeak

> **STATUS: STUB.** This document is a placeholder. The tool exists
> (`SWA-StSpy` package: `SWAStSpy`, `SWAStSpyNode`, `SWAStSpyFlamegraphMorph`,
> `SWAStSpyTreemapMorph`) but the full write-up is pending. See the journal entry
> [2026-06-19 (SWAStSpy flamegraph)](../../journal/2026-06-19-swastspy-flamegraph.md)
> and the note [st-spy](../../notes/st-spy.md) for current details.

## Motivation

Where the **[Code Map](SWACodeMap.md)** shows *static* structure and **test
coverage**, and **[SWASpaceTally](SWASpaceTally.md)** shows *memory*, the Message
Tally shows **where time actually goes at runtime**: a sampling profiler over a
running Squeak image, presented as a call tree you can explore three ways.

## What it does (overview)

- Drives the external **st-spy** sampling profiler (non-blocking: detached launch +
  forked poller + deferred UI update).
- Parses a chrome-trace **flamechart** into a wall-clock-time-weighted call tree
  (`SWAStSpyNode`): each frame's self time = its span minus its children.
- Presents that one tree through the shared SWA view layer:
  - an **Explorer** (multi-column tree browser),
  - a **TreeMap** (`SWAStSpyTreemapMorph`, tiles sized by sample count),
  - a **Flamegraph** (`SWAStSpyFlamegraphMorph`, cached-Form blit, select-then-zoom,
    embedded Shout-highlighted source pane).

## Shared architecture

Like the Code Map and Space Tally, the Message Tally's nodes subclass `SWANode`
(supplying `name`, `totalSize` = sample count, and a `'Class>>selector'`
`crossRefKey`) and its views subclass `SWAView`, so the same `SWANavPanel` chrome
and the same **cross-referencing** mechanism apply. This means a profiler run can be
cross-referenced against an open Code Map -- e.g. *"highlight in the Code Map
exactly which methods the profiler sampled, and how hot they were"* -- since both
speak the same `crossRefKey` vocabulary.

## To be documented

- Recording workflow and the non-blocking launch/poll machinery.
- Flamechart parsing and the self-vs-total time model.
- The three views and their navigation (zoom, back, browse, show source).
- Cross-referencing the profiler against the Code Map and Space Tally.
- Relationship to the `SQUEAKSPY_ROADMAP` external-profiler effort.

## See Also

- **[SWACodeMap](SWACodeMap.md)** -- static structure, byte composition, coverage.
- **[SWASpaceTally](SWASpaceTally.md)** -- structural memory analysis.
- **[index](index.md)** -- the shared SWA tools index.
