# Testing the Suite

![](_navigation.html)

A plan for unit-testing SWA itself. Known debt is in [smells.md](smells.md);
work items are in [todo.md](todo.md). This file is about what to assert and what
not to.

<!-- MAINTENANCE
Run one test class:

	SWADatasetTest buildSuiteFromSelectors run

Run everything in the SWA-Tests package:

	| s |
	s := TestSuite new.
	(SystemOrganization listAtCategoryNamed: 'SWA-Tests') do: [:n | | c |
		c := Smalltalk at: n.
		(c inheritsFrom: TestCase) ifTrue: [
			s addTests: c buildSuiteFromSelectors tests]].
	s run

Verified 2026-09-17: 29 run, 29 passes, 0 failures, 0 errors, ~2.7 s.

Keep new test classes in the SWA-Tests package, named <ClassUnderTest>Test, and
keep fixtures (containers, dummies, synthetic graphs) there too rather than in
the package under test.

Update the counts in section 1 when they drift; they are the argument for the
priorities below.
-->

## 1. Current state

| | |
|---|---|
| Classes in `SWA-*` | 147 |
| Of those, not `Morph` subclasses | 108 |
| Test classes | 2 |
| Test methods | 29, all passing |

`SWADatasetTest` (23 tests) covers the dataset layer: metric rollup, axis
binding, menu construction, provenance, links, and switching between two
datasets of the same kind. `GraphvizPlainParserTest` (6 tests) covers one parser
against a sample fixture. `SWADatasetTestContainer` is a synthetic node fixture.

The distribution is informative. The one subsystem with real coverage is the one
that is pure and algebraic. It got tested because it was testable, not because it
was the most important.

## 2. Why this suite is awkward to test

Four hazards, none of which apply to ordinary application code.

**Instrumentation can take down the process running the test.** Method wrapping
is the mechanism behind six tools. Wrapping the wrong method has crashed and hung
this image repeatedly; [BISECT-FINDINGS](../../notes/BISECT-FINDINGS.md) exists
because of it. A test that installs a wrapper badly does not fail, it kills the
runner.

**The measurements are non-deterministic by construction.** A heap diff around a
no-op reports 1,500–2,300 objects because the render loop and the MCP server are
running. Sampling is statistical. Scavenges happen when they happen. Assertions
on values are assertions on weather.

**The tools measure the image they run in.** A heap walk sees the test's own
objects, the test runner, and SUnit's result collection. Self-exclusion is not a
detail of the implementation, it is a correctness property, and it is testable.

**Several tools depend on things outside the image**: the `dot` binary, the
`st-spy` binary under sudo, a GitS repository, a 1.4 GB `opencode.db`,
`/proc/self/*`, NVML. Absence must produce a skip, never a failure.

## 3. Principles

**Test what can be silently wrong.** A view that fails to open is obvious and
self-reporting. A view that charges bytes to the wrong parent, rebuilds a call
tree in the wrong order, or double-counts inclusive time up a hierarchy produces
a confident, plausible, wrong picture. That is where a test earns its place. This
is the same criterion as [views.md §8](views.md#8-what-a-new-view-must-do),
applied to tests.

**Prefer degraded production code over a test double.** The house rule already:
making `SRMorphTexture` survive a missing GL context deleted three doubles and
made the tests exercise the shipping classes. `SWAMemoryProbe` is the model here —
it answers `nil` when `/proc` or NVML is missing rather than signalling. A Class
Diagram should behave the same way when `dot` is absent. Every double avoided this
way is a class of production bug caught rather than mocked away.

**Assert invariants, not values.** Conservation (a parent's rolled-up total
equals its own plus its children's), ordering, monotonicity, round-trip identity,
idempotence, and bounds. Never an absolute byte count or microsecond figure.

**Never instrument a system class in a test.** Wrapping happens only on a
fixture class owned by `SWA-Tests`.

**Anything that can hang runs in a forked child.** The bisection harness already
spawns headless children for exactly this; generalise it rather than inventing a
second mechanism.

## 4. Tier 1: pure logic, no image state, no display

About 40% of the suite, currently almost untested, and zero risk to run. This is
the whole of the near-term work.

| Target | Properties to assert |
|---|---|
| `squarify:scales:into:`, `worstAspectRatio:`, `emitRow:` | tiles partition the rectangle exactly; area proportional to weight; no overlap; aspect ratio bounded; degenerate cases (one child, zero weights, weights spanning six orders of magnitude) |
| `SWANode` protocol | `depth`, `pathString`, `isLeaf`, `withAllChildrenDo:` visits each node once; `markKey` defaults to `crossRefKey`; package and category overrides |
| `SWAMaskSource` | `B \ A` membership; metrics mirrored from B and gated to survivors; a mask over a mask (the algebra must close) |
| `SWADatasetMetric` | `#sum` vs `#max` rollup; that inclusive-time metrics use `#max` and self-time `#sum`, since summing nested totals double-counts |
| `SWACodeSimilarity` | identical sources score 1.0; disjoint score 0.0; symmetry; a one-line edit stays above threshold; shingle size `k` monotonic in sensitivity |
| `SWAChangeParser` | a fixture chunk string parses to the expected records; malformed chunks do not abort the scan |
| `SWASpaceTallyJsonWriter` / `Reader` | round-trip identity on a synthetic tree, **including** `otherParents` graph edges through mint-on-first-sight ids |
| `SWAMarkSet` | insertion order preserved; re-add is first-wins; JSON round-trip carries comments and provenance; `removeAll:` |
| `SWATraceNode class>>fromLanes:` | reconstruction from synthetic exit-ordered records: correct nesting from recorded depth; **identical timestamps must not change the tree**, which is the reason depth is recorded rather than inferred; truncated lanes still yield a valid tree |
| `SWASamplingTallyNode` | `childNamed:` is find-or-create; `rollUpTotals` conserves; `prunedToKeys:` keeps ancestors of survivors; `asCodeGroupingRoot` preserves total weight |
| `SWABitermTopicModel` | with a seeded `Random`, the run is reproducible; vocabulary pruning respects `minWordFreq`; biterm cap respected |
| Temporal bucketing | a day boundary, a week boundary, and an empty range produce the expected cells |

`SWATraceNode class>>fromLanes:` is the highest-value item on this list. Its
correctness rests on an argument stated in a class comment — that exit-ordering
plus recorded depth determines the tree where timestamp containment does not —
and nothing currently checks it.

## 5. Tier 2: synthetic object graphs, no display

The insight that makes the Space Tally testable: **the walker does not need the
whole image.** It takes explicit `roots:`, so a graph built in the test is a
complete and deterministic universe.

Build a known graph — a few fixture objects with named ivars, an indexable
collection, a shared object referenced twice, a weak reference, a cycle — and
assert:

- every object is reached exactly once;
- first-reached-parent charging puts the shared object under the earlier root, and
  records the other referrer in `otherParents`;
- `totalSize` equals `selfSize` plus the children's totals, at every level;
- `edgeLabel` names the slot actually traversed (ivar name, `[N]`, `#literals[N]`);
- weak slots are not followed;
- the cycle terminates;
- **the walker's own state does not appear in the tally**;
- `compact` nils the object references and the tree survives it.

For `SWAHeapDiff`, allocate a known number of instances of a fixture class inside
the measured block and assert those instances appear, with the noise floor
tolerated rather than asserted away.

## 6. Tier 3: instrumentation

Dangerous, and the reason for the fixture-class rule. Wrap only
`SWA-Tests`-owned methods.

- exact counts after a known number of sends;
- `realMethod` peels stacked wrappers in order;
- **balance under unwinding**: an exception, a non-local return, and a process
  termination through a wrapped method each restore the caller's state;
- per-process isolation: two processes running the same wrapped method
  concurrently keep separate frame records and separate trace lanes. This is the
  bug that crashed the VM as a global boolean, so it is the one test in this
  section that must exist;
- `uninstall` restores every method, verified by comparing method dictionaries
  before and after;
- **overhead compensation as a property**: a caller's reported inclusive time must
  not grow with the number of instrumented callees it invokes. This is the subtle
  part of `SWATimingWrapper` and it fails silently.

Guard the whole section: if a test in it hangs, the runner is gone. Either run
this tier in a forked headless child, or gate it behind an explicit switch so a
routine run does not touch it.

## 7. Tier 4: views

`SWADatasetTest` already reaches view level, so the approach is established.

Assert decisions rather than pixels: which colour a node resolves to, which menu
entries exist, that a colour change flushes the cached Form while a size change
invalidates the layout, that zoom preserves selection, that `setRoot:` rebuilds
the `keyIndex`. Render to an offscreen Form only when the question is genuinely
about rendering.

Degradation belongs here too: absent `dot`, absent `/proc`, absent NVML, an empty
tree, and a tree with one node should each produce a view rather than an error.

## 8. Contract tests: guarding against the image changing

The tiers above test our logic. They do not protect against the ground moving,
and this suite rests on an unusual amount of other people's behaviour: VM
parameter numbering, undocumented allocator properties, base-image navigation,
GitS internals. When one of those changes the tools do not break, they keep
producing numbers that mean something else. That is the silent-wrongness
criterion of section 3 in its purest form.

**Observed properties, verified once by hand and never re-checked.** Each of
these is load-bearing, stated as verified in a class comment, and testable
behaviourally. The experiments that establish them, and the measured magnitudes
that are *not* assertable, are in [benchmarks.md](benchmarks.md):

| Assumption | Relied on by | Test |
|---|---|---|
| `identityHash` is preserved across a scavenge | `SRSurvivorCensus` | hash a set of objects, `garbageCollectMost`, re-hash, compare |
| A large allocation is born directly in old space | `SWAYoungSpaceState` | allocate a multi-megabyte array, assert it does not move across a scavenge |
| Young objects move on a scavenge, old ones do not | young-space move detection | read addresses, collect, re-read, assert the partition |
| `allObjectsOrNil` returns new space as a contiguous tail | `SWAYoungSpaceTally` | assert freshly allocated objects occupy the final slots |
| The tight heap walk allocates nothing | `SRSurvivorCensus` | measure allocation across the walk and assert it is zero |

**VM parameter indices.** `vmParameterAt:` is positional, and the suite reads at
least 1, 2, 7, 8, 9, 10, 11, 21, 34, 35 and 54 across `SRGCRecorder`,
`SWATraceSeries`, `SWATraceMarker` and `SWAChangeTraceRecorder`. If the VM
renumbers, every GC graph keeps drawing, with a different signal. Test each by
its behaviour rather than its value: the scavenge count must increase after
`garbageCollectMost` and the full-GC count must not; the full-GC count must
increase after `garbageCollect`; used-young must drop across a scavenge; bytes
allocated since last GC must be monotonic between collections.

**Base-image and package APIs** that are not ours and carry no compatibility
promise: `SystemNavigation>>allObjectsOrNil`, the `thisContext` mirror
primitives, `AlienStub>>addressField`, primitive 571 for FFI unload,
`WeakActionSequenceTrappingErrors` (subclassed by
`SWAInstrumentedActionSequence`), and the GitS pair
`GSGitWorkingCopy>>changeSetsFromCommit:toCommit:` and
`MCModification>>obsoletion`. A presence-and-shape test per dependency, failing
loudly with the name of what vanished, is cheaper than discovering it through a
wrong picture.

**Baseline datasets.** The suite already exports keyed results as JSON and
already has set arithmetic over them. Committing a baseline — the package and
class inventory, a coverage run, a space-tally class census — and having a test
re-derive and diff it turns any unexplained drift in the image into a failure.
Tolerances matter: exact for structure, banded for bytes and counts. This is
[todo.md](todo.md) item 16 pointed at the suite itself, and it is the only guard
here that catches a change nobody thought to write a test for.

## 9. Not worth testing

- Sampling output values, absolute byte counts, GC timing, frame rates.
- Graphviz layout coordinates. The parser is testable; `dot` is not ours.
- Anything reading the live world, `SRWorld current`, or Jens's open windows.
- Exhaustive coverage of the view classes. This is a probe, not a product
  ([motivation.md](motivation.md)); breadth of coverage is not the goal, and the
  criterion in section 3 is.

## 10. Order of work

1. Tier 1, in the order of the table. Cheap, safe, and it covers the logic most
   likely to be silently wrong.
2. The observed-property and VM-parameter contract tests (section 8). Cheap,
   independent of everything else, and they protect assumptions that are
   currently guarded by a sentence in a class comment.
3. The Space Tally synthetic graph (tier 2), which retires the largest single
   correctness risk in the suite.
4. The per-process isolation test (tier 3), because that failure mode has already
   cost days.
5. Degradation tests (tier 4), which are cheap and double as the argument for
   deleting test doubles.
6. Baselines last: they are only worth having once the structure they record has
   stopped moving.

Fixtures and a forked-child harness are prerequisites for 2 and 3 and should be
built with them rather than in advance.
