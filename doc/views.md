# Views on a System

![](_navigation.html)

The entry point to the documentation. What the suite is for, how well it covers
its subject, and what a new view must do to earn its place.

Reference material sits behind this: [landscape.md](landscape.md) enumerates the
tools and derives the coverage systematically, [stories.md](stories.md) records
the individual findings this argument is abstracted from,
[architecture.md](architecture.md) describes construction,
[gallery.md](gallery.md) shows each view, [todo.md](todo.md) holds the resulting
backlog.

## 1. The problem is distance, not access

The subject is a running system: Squeak, SqueakXR, and the application in the
image.

Squeak's reflective access to that system is excellent and long-standing. Every
measurement in this suite except the external sampler is obtained through
ordinary image facilities: `allObjectsOrNil` and `nextObject`, `vmParameterAt:`,
the `thisContext` mirror primitives, the method dictionary, `SystemChangeNotifier`,
`MessageTally`. None of it required a VM change. Smalltalk developers have used
this data for decades, typically as workspace snippets written for one question
and then discarded.

The deficiency was therefore never access. It was distance.

Every standard tool operates at the granularity of a single thing: the Inspector
one object, the Explorer one graph traversed by hand, the Debugger one stack, the
Browser one method, MessageTally one run. Each gives full fidelity at close
range, and proximity is precisely the limitation — near enough to the objects
that the shape of the whole is not visible. Three operations are missing at that
range, and a fourth problem holds across all of them:

- **Aggregation.** Many objects at once, summed, so that proportion becomes
  visible.
- **Comparison.** Two states, with only the difference retained.
- **Projection.** One body of data laid onto a view built for another.
- And the results of any two tools **cannot be related**: the Inspector's object
  and the Browser's method share no name, no surface, and no way of being seen
  together.

An illustration of the first. From an Inspector one can examine an object's
referrers. One cannot see the *distribution* of referrer counts across the heap:
that the overwhelming majority of objects are reachable from exactly one other,
while a small number are referenced from everywhere. That distribution is not a
property of any object, so no per-object tool can present it. It appears only
when the whole graph is held at once and drawn, which is what the Space Tally's
`otherParents` data makes visible. Further cases of the same kind are collected
in [stories.md](stories.md).

The same difference applies to the snippets. A snippet answers one question once
and is thrown away. A dataset is retained, composes with other datasets, and can
be projected onto a view built for something else. Retained and composable rather
than ad hoc is a larger part of what this suite is than any individual
measurement it takes.

## 2. Views, not dimensions

An earlier version of this analysis classified the tools along abstract axes.
That was the wrong model. An axis partitions the space of possible measurements;
one cannot ask whether an axis is redundant, or whether it may be discarded.

A **view** is a vantage point. It has a footprint, a resolution, a cost, and a
blind spot. Those properties make the operative questions askable: what does this
view cover, what does it miss, what else already covers it, and may it be
dropped.

`SWAView` encodes exactly this. The class owns what is visible (`rootNode`,
`keyIndex`), how it is lit (`colorMode`, datasets), and what it cannot show.
`SWAPane` is the apparatus around the observer. The architecture committed to the
model before the documentation described it.

## 3. Four operations

A view performs up to four operations. Coverage analysis must account for all
four; accounting only for the first is how the redundancies below went unnoticed.

| Operation | Question | Failure mode | Whose |
|---|---|---|---|
| **Observe** | What is the case? | dark region: nothing reports it | mostly Squeak's, inherited |
| **Aggregate** | What is the case *at scale*? | proximity: detail without proportion | the suite's |
| **Relate** | Is this the same thing as that? | isolated result: observed, unrelatable | the suite's |
| **Reduce** | What can be removed? | glare: everything shown, nothing legible | the suite's |

The fourth column matters for any claim this project makes. Observation is
overwhelmingly Squeak's, and old. The contribution, if there is one, is in the
other three.

### 3.1 Relate

Relation is a human act. The mechanisms below lower its cost; none of them
perform it. They differ in who initiates and what is required.

| Kind | Mechanism | Requires | Initiated by |
|---|---|---|---|
| Automatic | colour one view by another's data | a shared name | the mechanism |
| Deliberate | `SWAMarkSet`: assert that these belong together | nothing | the human |
| Incidental | shared clock, shared layout, same window and chrome, a recognised name | nothing | the human |

`crossRefKey` implements the shared name, and it is not the thesis — the thesis is
that a person can relate two results, and GC Stats and the Memory Graph
demonstrate that by carrying no key at all and still being read against the Trace
by clock. Relation by time is weaker, since the human performs the alignment, but
it works.

It is not merely plumbing either. The key is a deliberate commitment to **late
binding**: views refer to program elements *by name* rather than holding
references to objects. This is the mechanism Smalltalk already uses for message
sends, applied one level up — binding visualizations to code the way a send binds
to an implementation.

What that buys is the looseness the suite runs on:

- A result outlives the view that produced it, and survives export to JSON, a
  restart, a different image and a different machine.
- Views are built and destroyed independently; a mark set in one survives the
  rebuild of another, because nothing holds anything.
- Two visualizations that know nothing about each other can be bridged *after the
  fact*, which is what makes a peer dataset or a mask possible at all.
- A key may refer to something not currently present — a method in a package not
  yet loaded, or one deleted since the measurement.

And it costs exactly what late binding always costs: keys can dangle, nothing is
checked until it is looked up, and a rename silently breaks every link to the old
name. The same trade Smalltalk makes with selectors, with the same consequences.

Deliberate relation is the most general of the three and the least developed.
See [todo.md](todo.md) item 1.

### 3.2 Reduce

Light applied uniformly to an entire subject reveals nothing. A UML diagram of
every class and every method is visually equivalent to no diagram. Form is
revealed by contrast, and contrast requires that most of the subject be excluded.

Reduction is therefore not a convenience feature. It is the operation that makes
a measurement legible, and the suite already implements nine forms of it:

| Mechanism | Removes by | Implementation |
|---|---|---|
| Difference | showing only what changed between two states | Heap Diff, Survivor Diff, Young Space Tally, Space Tally `isNew`, Git Map, Change Map |
| Set arithmetic | showing only keys in B and not in A | `SWAMaskSource` |
| Selection | showing only what was marked | `SWAMarkSet`, `SWACodeMarkSetRootNode` |
| Threshold | dropping everything below a size | `pruneBelow:`, `exploreCoarse:` |
| Depth cutoff | stopping at a structural level | `leafKind`, the Depth control |
| Zoom | discarding context in favour of detail | click-again-to-zoom, breadcrumb, Back |
| Dimming | retaining but de-emphasising | search dim; matches and their ancestors stay bright |
| Weighting | making the uninteresting geometrically small | the Size axis: size by covering tests and untested code collapses |
| Filtering | restricting to one relation | `filterToTestKey:`, `prunedToKeys:` |

Weighting is the least obvious of the nine: the Size menu does not only determine
what area means, it determines what shrinks to nothing. It is subtraction by
geometry.

## 4. Regions of the subject

Defined by what a claim about them is about, rather than by how it is obtained.

1. **Code as text** — packages, classes, methods as written
2. **Code as meaning** — what it sends, what types flow, what depends on what
3. **Provenance** — how the code came to be, and who or what has been near it
4. **Live objects and retention** — the heap, and what holds it
5. **Control flow** — what calls what, in what order, in which process
6. **Time budget** — where wall-clock time goes
7. **Memory dynamics** — allocation, collection, generations
8. **The outside** — FFI, GPU, OS process, files, sockets
9. **Correctness and intent** — whether it works, and what it was meant to do
10. **Interaction** — the human or agent acting on the system

## 5. The illumination map

`Views` counts views bearing on the region. `Reduction` records whether the
region can be cut down, which determines whether the light is usable.

| Region | Views | N | Reduction available | Verdict |
|---|---|---:|---|---|
| Code as text | Code Map, Class Diagram, Duplication, Topic Model | 4 | marks, search, depth, zoom, weighting | well lit, complementary |
| **Code as meaning** | — | **0** | — | **dark** |
| Provenance | Change Map, Git Map, OpenCode Access, Change Trace (+3 temporal renderings) | 4 | difference is intrinsic; zoom, calendar drill | over-lit, duplicated sources |
| Live objects, retention | Space Tally, Heap Diff, Survivor Diff, Young Space Tally, Survivor Census | 5 | strongest in the suite: difference, threshold, coarsening, provenance grouping | over-lit, but forced |
| Control flow | Coverage, Invocation Tally, Sampling Tracer, Sampling Tally, Trace | 5 | mask, `prunedToKeys:`, zoom, sub-pixel merge | over-lit, partly accidental |
| Time budget | Timing Tally, Sampling Tracer, Sampling Tally, Trace | 4 | as above | same views as the row above |
| Memory dynamics | GC Stats, GC Recorder, Memory Graph, Alloc Tracer | 4 | almost none: unkeyed, so no mask or marks; pan and zoom only | **glare** |
| The outside | Memory Graph | 1 | none | dim: volume only, never duration |
| **Correctness and intent** | — | **0** | — | **dark** |
| Interaction | click log exists, wired to no view | 0 | — | observed, unlit |

Counts are not independent: rows 5 and 6 are largely the same instruments seen
from two questions.

Twenty-seven placements over ten regions. Two thirds fall on four regions; two
regions have none.

**The system is observed almost entirely while it runs.** The suite is strong on
what the program *does* over time and weak on what it *is*. What the code means,
whether it is correct, and what it was intended to do are unobserved.

## 6. Dark spots

**Code as meaning** is the load-bearing gap. In Smalltalk a send cannot be
resolved without the receiver's class, so the absent call graph follows from
absent type information, and coupling, dependency and complexity analysis follow
from the absent call graph. One gap accounts for four.

**Correctness and intent** is absent as a category, not merely unimplemented.
Every view measures what is; none records what ought to be. Tests appear only as
coverage attribution, never as claims about behaviour. No failure, exception or
assertion data is attached to any key.

**Interaction** is the cheapest of the three to close: the image already records
UI interaction, and nothing projects it onto a view.

## 7. Glare, and two kinds of redundancy

A region covered by five views with no means of subtraction is not well observed.
Memory dynamics is the clearest case: four instruments, no key, and therefore
none of the mask, mark or filter machinery that makes the other regions legible.

Where views do overlap, the distinction that matters is whether the overlap was
forced.

**Forced.** The five object views exist because measurement perturbs its subject.
A snapshot array retains everything it names; a collection destroys the transients
under study. `SRSurvivorCensus` and the move detection in `SWAYoungSpaceTally`
exist solely to avoid disturbing the phenomenon. This redundancy is the price of
an honest measurement and cannot be removed.

**Accidental.** The remainder is history rather than necessity:

| Overlap | Difference between them | Resolution |
|---|---|---|
| Sampling Tracer / Sampling Tally | whether an external process is required | one view, source switch |
| Invocation Tally / Timing Tally | timing is a strict superset; it counts and times | one view, mode switch; already half-merged in `SWADataset>>buildMetrics` behind `hasTimingData` |
| Change Map / Git Map | source is `.changes` or git; Change Map alone sees uncommitted work | one temporal view over two sources |

The suite has roughly fifteen tools where it has nine views and six switches.
Collapsing them is precisely the purpose of the dataset and `SWAStructure` layer,
which has not been applied to the suite itself.

## 8. What a new view must do

A view earns its place by one of four:

1. light a dark region;
2. raise resolution in a dim one;
3. reduce cost or perturbation in an over-lit one;
4. give a region a form of subtraction it lacks.

By this rule a sixth object-set walker fails, a static call graph passes
immediately, and a means of masking the memory-dynamics signals passes on
criterion 4 despite that region already having four instruments.

## 9. Accuracy note

Two caveats bear on how much weight the ownership picture can carry.

First-reached-parent BFS charging is not a dominator tree. It is traversal-order
dependent, and the `SWASpaceTally` class comment records the consequence: the
symbol table appears small because the class table enqueues most symbols first. A
dominator tree answers "if this were released, what else would be released";
BFS charging approximates that and can mislead about ownership.

Sampled and exact results are rendered identically. No view carries an error
estimate, although section 7 depends on the two differing.
