# SWAMessageTally -- Sampling (Statistical) Message Tally for Squeak

> **STATUS: STUB.** This document is a placeholder. The tool exists
> (`SWA-MessageTally` package: `SWASamplingTally`, `SWASamplingTallyNode`,
> `SWASamplingTallyFlamegraphMorph`, `SWASamplingTallyTreemapMorph`) but the full
> write-up is pending. See the journal entry
> [2026-06-19 (flamegraph)](../../journal/2026-06-19-swastspy-flamegraph.md) and the
> note [st-spy](../../notes/st-spy.md) for current details.

## Three flavours of message tally

"Message tally" is ambiguous, so keep the three flavours distinct:

| Flavour | What it measures | How | In this suite |
|---|---|---|---|
| **Full / deterministic** | *exact* call counts (every send) | instrumentation / wrappers | -- (future) |
| **Statistical, in-image** | approximate hot spots | Squeak's own `MessageTally` (`spyOn:`), sampling from *inside* the VM | -- (built into Squeak) |
| **Statistical, external** | approximate hot spots, wall time | the **st-spy** sampler ptraces the VM from *outside* | **`SWASamplingTally`** (this tool) |

This tool is the **external statistical (sampling)** flavour. `st-spy` is the
internal sampler binary it drives -- an implementation detail, not the tool's name.

## Motivation

Where the **[Code Map](SWACodeMap.md)** shows *static* structure and **test
coverage**, and **[SWASpaceTally](SWASpaceTally.md)** shows *memory*, the Sampling
Tally shows **where time actually goes at runtime**: a statistical sampling profiler
over a running Squeak image, presented as a call tree you can explore three ways.

## What it does (overview)

- Drives the external **st-spy** sampler (non-blocking: detached launch +
  forked poller + deferred UI update).
- Parses a chrome-trace **flamechart** into a wall-clock-time-weighted call tree
  (`SWASamplingTallyNode`): each frame's self time = its span minus its children.
- Presents that one tree through the shared SWA view layer:
  - an **Explorer** (multi-column tree browser),
  - a **TreeMap** (`SWASamplingTallyTreemapMorph`, tiles sized by wall time),
  - a **Flamegraph** (`SWASamplingTallyFlamegraphMorph`, cached-Form blit,
    select-then-zoom, embedded Shout-highlighted source pane).

## Shared architecture

Like the Code Map and Space Tally, the Sampling Tally's nodes subclass `SWANode`
(supplying `name`, `totalSize` = sample count, and a `'Class>>selector'`
`crossRefKey`) and its views subclass `SWAView`, so the same `SWAPane` chrome
and the same **dataset** layer apply. A live profiler panel is therefore selectable
as a `#peer` dataset from any other tool's **Data** menu -- e.g. *"colour the Code
Map by which methods the profiler sampled, and how hot they were"* (container tiles
roll up their sampled methods) -- since both speak the same `crossRefKey`
vocabulary. The flamegraph colours intrinsically per frame, so it is a good
cross-reference *source* but not a colour *target*.

## To be documented

- Recording workflow and the non-blocking launch/poll machinery.
- Flamechart parsing and the self-vs-total time model.
- The three views and their navigation (zoom, back, browse, show source).
- Cross-referencing the profiler against the Code Map and Space Tally (as a `#peer`
  dataset in the Data menu).
- Relationship to the `SQUEAKSPY_ROADMAP` external-profiler effort.

## See Also

- **[SWACodeMap](SWACodeMap.md)** -- static structure, byte composition, coverage.
- **[SWASpaceTally](SWASpaceTally.md)** -- structural memory analysis.
- **[index](index.md)** -- the shared SWA tools index.
