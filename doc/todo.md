# SWA Backlog

![](_navigation.html)

Actionable items derived from the coverage analysis in [views.md](views.md) and
the enumeration in [landscape.md](landscape.md). Research directions and the
argument for why any of this matters are in [ideas.md](ideas.md); known debt is
in [smells.md](smells.md). This file holds work items only.

## Near term

### 1. Promote a dataset to a mark set

**Problem.** A UML diagram of every class is illegible; a diagram of a chosen
dozen tells a story. `SWACodeMarkSetRootNode` already builds a view whose
children are the marked classes, so the mechanism exists. But `SWAMarkSet`
offers only `add:`, `toggle:`, `add:from:`, `removeAll:` and `loadFromFile:`.
Marks are authored by hand or from a file, and by nothing else.

**Change.** One operation taking a dataset (or a metric plus a threshold) and
adding its keys to the mark set, with provenance recording which dataset
supplied them.

**Why it is the first item.** It closes the one open loop in the algebra:
reductions compose with each other but cannot currently feed the selection. Once
closed, the interesting set can be derived from the hot methods of a profile, the
classes that survived a scavenge, the methods a commit touched, the members of a
duplication cluster, the classes an agent edited this session, or any `B \ A`
mask — and then rendered as a class diagram, a treemap, or a flame chart.

### 2. Wire the interaction log to a view

The image already records UI interaction; nothing projects it. A recorder in the
shape of `SWAChangeTraceRecorder`, keyed where a morph can be attributed to a
class, makes the Interaction region non-dark at low cost.

### 3. Complexity metrics on the Code Map

Branch count, nesting depth, temp count, send count per method. One parse-tree
walk, cached exactly as `loc` is. Gives the Size axis a measure that separates a
40-line accessor block from a 40-line decision tree.

### 4. Finish the tally merge

`SWADataset>>buildMetrics` already gates timing metrics behind `hasTimingData`
inside the `#coverage` kind, so Invocation Tally and Timing Tally are half-merged
already. Complete it: one view, one mode switch, lower cost when timing is not
required.

### 5. Merge the two samplers

Sampling Tracer and Sampling Tally differ only in whether an external process is
required. One view with a source switch.

## Medium term

### 6. Static send graph

Parse-tree walk producing, per method, the set of selectors sent and the
instance variables read and written. Yields fan-in and fan-out, a package
dependency map, an ivar access graph, and cycle detection. The 2026-07-28
Scripts-panel work did ivar-write analysis without a parser and is the seed.

Unsound without types (see item 7), but useful immediately: an unresolved send
graph still exposes layering violations and coupling that LOC cannot.

This is the load-bearing item on the list. Mud is a coupling phenomenon, and
coupling is the one thing the suite does not measure — so it cannot currently
tell its own author whether an agent is producing structure or a ball of mud,
which is the question an architecture tool for agent-authored code exists to
answer. See [motivation.md](motivation.md) and
[smells.md §9.3](smells.md#93-what-is-still-hand-only).

### 7. Type harvest

The load-bearing gap. Two routes, not mutually exclusive.

*Dynamic.* `SWAMethodWrapper>>run:with:in:` already holds the receiver and the
arguments and discards them. A wrapper subclass recording receiver and argument
classes per key, plus a dataset kind to carry the result, is the smaller and more
characteristic route: it produces concrete observed types that no static analysis
can match, at the usual wrapper cost.

*Static.* Inference over literals, `self`, `super`, instance-variable assignment
and unique implementors. Cheap and always available; unsound in the interesting
cases.

Worth building both, because they can disagree, and the disagreement is a
finding. Together they resolve the send graph of item 6 into a call graph.

### 8. Failure dataset

Nothing records where the program breaks. Exception frequency per key,
debugger-entry counts, test outcomes as opposed to test coverage. Closes half of
the Correctness region, and a failure map projected onto a Code Map points at
where debugging effort actually goes.

### 9. Locate a collection within the frame

The VM gives no GC callback, so `SWATraceMarker` can only detect a collection
after the fact and pin it to the end of the step, recording honestly that the
duration is real and the position is not. That makes one question unanswerable:
*where* in a frame did the scavenge land. The scavenge-phase hypothesis in
[benchmarks.md §6](benchmarks.md) turns on exactly that.

Approach: drain `vmParameterAt: 9` and `10` at several probe points across the
render loop rather than once per cycle, localising each collection to the segment
between two probes. This is the `SWAStepTraceWrapper` pattern at finer
granularity, and the cost is already known to be negligible — a VM parameter read
is 0.01 us.

### 10. Subtraction for the memory signals

Memory dynamics has four instruments and effectively no reduction, because the
signals are unkeyed and therefore outside the mask, mark and filter machinery.
Options: difference of two recordings, thresholded event extraction (show only
frames whose scavenge cost exceeded n ms), or a lane-level mask. The region does
not need a fifth instrument.

### 11. FFI and GL call duration

Time spent outside the image is currently indistinguishable from primitive self
time. Given the proportion of SqueakXR that is FFI, applying the established
wrapper pattern to `ExternalLibraryFunction` invocation moves a large
unattributed block into the picture.

### 12. Merge the two history sources

Change Map and Git Map cover the same region from `.changes` and from git. One
temporal view over two sources. Change Map's only distinct claim is uncommitted
work, which becomes a source selection rather than a separate tool.

## Longer term

### 13. Object age as a standing metric

The 2026-08-21 work established that ages are obtainable. The result is not yet a
property of the heap that a view can be sized or coloured by.

### 14. Comparison as a general operation

Differencing exists three times ad hoc (Heap Diff, Survivor Diff, the `B \ A`
mask). It is not a general operation over datasets, so regression between two
runs or two versions is unobservable. Closing the mask algebra to union,
intersection and symmetric difference ([ideas.md](ideas.md) direction 2) is the
first step; a snapshot of code state, currently absent, is the second.

### 15. Uncertainty in the presentation

Sampled and exact values render identically, although [views.md §7](views.md)
depends on the two differing. Views should distinguish a measured value from an
estimated one.

### 16. Dominator tree for retention

First-reached-parent BFS charging is traversal-order dependent and can mislead
about ownership; the `SWASpaceTally` class comment records the symbol-table case.
A dominator tree answers the ownership question correctly. Expensive, and worth
it only if the ownership picture is to carry real weight.

### 17. Cross-image comparison

Desktop and Quest are separate images. Nothing measures across them or compares
them, although both run the same packages and the interesting question about the
Quest is precisely where it differs.

### 18. Non-temporal cost

Time and bytes are the only currencies. `SWAOpenCodeSession` already carries
`cost` and five token counts, but these describe agent sessions and are never
projected onto code. Energy and network volume are absent entirely.

## Trimming the suite

Using SWA on SWA. The findings and the two scans that produced them are in
[smells.md §9](smells.md); the guards are in [tests.md §8](tests.md).

### 19. Mark the entry points

The unsent-selector scan returns 242 non-test candidates, but in a live image
"never sent" includes the whole workspace-facing API: `parseTraceFile:`,
`exploreCoarse:`, `maxVisits:` are all documented usage and all on the list.
Until entry points are marked — a method category convention or a pragma — the
scan cannot separate an entry point from a corpse, and the list has to be read by
hand every time. Marking them first makes every later pass cheap.

### 20. Delete the confirmed dead paths

The scan independently confirmed two clusters already identified by hand: the
vestigial `coverageTally` on `SWAPane`, and the legacy cross-reference and
coverage-loading path (`clearCrossReference`, `crossReferenceFrom:`,
`highlightWeights`, `loadCoverageJson:`, `loadDuplicationJson:`,
`importCoverage`, `clearCoverage`) that the dataset layer replaced. The second is
`smells.md` 3.2 and is the larger one; it wants the design conversation recorded
there before deletion.

### 21. Cross-package duplication scan

`SWACodeSimilarity` is scoped to one package, so it structurally cannot find the
suite's own worst duplications, every one of which is cross-package. It also
costs 14 s for twelve classes and does not extrapolate to 147, so a whole-suite
scan belongs behind the async Generate pattern. Pair output additionally prints
the same method name on both sides with no class, which makes a cross-package
result unreadable; that is a smaller fix and a prerequisite.

### 22. A shape-dependent fingerprint for the survivor census

Measured 2026-09-17 ([benchmarks.md](benchmarks.md)): `identityHash` alone
collides at 0.6–6.7% within a class. Adding `basicSize` for variable-sized objects
takes `ByteString` from 6.74% to 0.5%; adding a three-byte content sample reaches
0.06%. For fixed-size classes `basicSize` is useless — it is 0 for every instance —
but one instance variable takes `Association` from 4.54% to 0.02% and two give
zero collisions over 372,000 instances.

All of it is O(1) per object and allocation-free. Content is safe to read in the
census, which runs at `highestPriority` so nothing can mutate between its two
walks; it is **not** safe in multi-sample analyses such as `SWAYoungSpaceState`,
where ordinary code runs between samples.

For those, restrict to ingredients that are stable under mutation: `identityHash`,
class, `basicSize` (fixed at creation for `Array` and `ByteString`, neither of
which grows in place), and the **key** of an `Association` — immutable by
convention, since mutating it would put the association in the wrong hash bucket,
and `key:` has 128 senders against 1,431 for `value:`. That restricted set still
gives 0.02% on `Association` and 0.33–0.5% on the variable-sized classes, between
13x and 227x better than the hash alone.

The two error modes are also asymmetric, which makes the trade safe: a collision
is a **false positive** that sends you chasing a retainer that does not exist,
while a mutation is a **false negative** that merely under-reports. Adding
imperfectly stable state trades the serious error for the benign one.

Three constraints on the implementation: read content through the `thisContext`
mirror primitives, not `instVarAt:`, or a proxy intercepts the access; treat
no-mutation-between-walks as a contract test rather than a comment; and do **not**
pack three 22-bit fields into one `SmallInteger` — that reaches 66 bits against a
60-bit limit and silently allocates a `LargePositiveInteger` per object. Use
parallel preallocated arrays, as `SWAYoungSpaceState` does.

### 23. Check how the survivor census matches fingerprints

`identityHash` collisions were measured for the first time on 2026-09-17: 27.6%
of objects in the image share a hash, but only 0.5–6.7% collide *within* a class
([benchmarks.md](benchmarks.md)). The whole difference is whether class is taken
into account before or after matching. If `SRSurvivorCensus` bins fingerprints by
class before comparing walks, its error is the small figure; if it matches
globally, a hash freed by a dying `ByteString` can be reused by a newborn `Array`
and counted as a survivor of the wrong class. Roughly 5x accuracy for no extra
cost, if it is not already done that way.

### 24. Contract tests for borrowed behaviour

The assumptions that carry the most weight are about other people's code: VM
parameter numbering, `identityHash` stability across a scavenge, large objects
being born old, `allObjectsOrNil` returning new space as a tail, GitS and
Monticello internals. Each is currently guaranteed by a sentence in a class
comment saying it was verified once. Behavioural tests for each are cheap and
independent of the rest of the test plan. See [tests.md §8](tests.md).

### 25. Benchmark harness, and magnitudes out of class comments

A re-measurement found three of six recited figures wrong, including two
conflicting claims about the same NVML call (0.7 ms and 0.26 ms; measured
0.16 ms) and a clock-read cost three times the stated one, which raises the floor
below which `SWATimingWrapper` can usefully time anything. A `SWABenchmark` in
`SWA-Tests` with one method per row of [benchmarks.md](benchmarks.md) makes a
re-run one send. The accompanying rule matters more than the harness: class
comments should state the constraint and not the number.

### 26. Committed baselines

Export the class inventory, a coverage run and a space-tally class census as
JSON, commit them, and diff on demand. Exact tolerance for structure, banded for
bytes and counts. This is item 16 applied to the suite itself, and it is the only
guard that catches a change nobody thought to write a test for.

## Not planned

- **A sixth object-set walker.** The Live objects region is already covered five
  times, and the redundancy there is forced rather than accidental.
- **Further intrinsic colour modes on the Code Map.** The region is well lit; new
  colour modes add light where contrast is what is missing.
