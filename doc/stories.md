# Findings

![](_navigation.html)

Concrete things the tools showed, and what each one generalises to. These are
the individual results that the coverage argument in [views.md](views.md) is
abstracted from; kept separately because the detail is the point.

<!-- MAINTENANCE
Admission criteria, so this does not decay into a changelog:

  1. A specific observation, with numbers where numbers exist.
  2. Sourced: a journal entry, a class comment, or a figure in media/.
  3. It generalises past the incident that produced it.

Numbers quoted below are from class comments and journal entries at the time of
writing. They are measurements of one image on one machine and will drift; they
are here because the magnitude is the finding, not because the digits are exact.
Group by what the finding teaches, not by which tool produced it.
-->

## Aggregation shows what no single object can

### The referrer distribution

An Inspector can show one object's referrers. It cannot show the shape of the
whole: that the overwhelming majority of objects in the image are reachable from
exactly one other object, and that a small minority are referenced from
everywhere.

That distribution is not a property of any object, so no per-object tool can
present it, however good it is. It exists only in the aggregate. The Space Tally
records extra referrers as `otherParents` and draws them
([figure](media/swaspacetally-treemap-otherparents.png)), which turns "who points
at this" from a question asked one object at a time into a visible property of
the heap.

This is the clearest case of the general claim: the limitation of the classical
tools was proximity, not access.

### The agent edits an image, not a directory

From 223 sessions and 24,425 tool calls in this project: the agent read 765 files
and wrote 494, but read about 7,100 and wrote about 6,100 Smalltalk methods and
classes.

File access is a minority activity, because in Squeak the program is the image
rather than a tree of text. The consequence is methodological: any analysis of
agent behaviour that counts file operations is measuring the wrong thing here,
and the Code Map projection of the session history is the one that carries
information. Source: `SWAOpenCodeHistory` class comment, journal
[2026-08-05](../../journal/2026-08-05-opencode-sessions-in-swa-and-two-sqlite-bugs.md).

## The measurement changes what is measured

### The snapshot that prevents death

The obvious way to find which objects survive a garbage collection is to
enumerate the heap before and after. The array returned by the enumeration holds
every object it names, so nothing can be collected, and the phenomenon under
study is destroyed by the act of observing it.

`SRSurvivorCensus` avoids this by storing each object's `identityHash` — an
immediate, so neither an allocation nor a reference — into a preallocated integer
table. It trades exactness for non-interference: 22-bit hashes collide across
millions of objects, so the result is a class-composition estimate rather than
per-object identity. Stating that limit is part of the finding.

### The instrument that is invisible by accident of size

`SWAYoungSpaceTally` needs to enumerate young space without perturbing it. The
enumeration allocates an array of roughly 21 MB, and because it is large it is
born directly in old space. It therefore never enters young space and is
invisible to the measurement, with no filtering required.

The same property makes move-detection self-cleaning: young objects move during a
scavenge and old ones do not, so the tool's own buffers, being old, can never be
mistaken for the data. A correctness argument that rests on an allocator's size
threshold is fragile, and worth writing down where it is relied on. Source:
`SWAYoungSpaceState` class comment, journal
[2026-08-21](../../journal/2026-08-21-young-object-ages-solved.md).

### The noise floor of a live image

A heap diff around an action that does nothing still reports 1,500 to 2,300 new
objects. The XR render loop is running, and the MCP server is servicing the very
call that requested the measurement.

There is no quiet moment in a live image to measure against. Every heap
difference is a difference plus the observer, and the floor has to be known
before a result above it means anything.

### A global flag that crashed the VM

Instrumentation must not instrument itself, so the wrapper machinery runs its own
bookkeeping in a suppressed mode. Implemented as a global boolean, this raced and
took the VM down: wrapping the live Morphic UI means several processes execute
wrapped methods at the same time.

`SWACapturingLayer` is therefore a per-process dynamic variable rather than a
flag. Any suppression state in a preemptively scheduled image has to be
process-scoped, and the failure appears only under the concurrency that makes the
measurement worth taking. Journal
[2026-06-26](../../journal/2026-06-26-instrumentation-substrate-rearchitecture.md).

## The artefact is not the phenomenon

### Why the symbol table looks tiny

The Space Tally charges each object to the first parent that reaches it, which
turns the object graph into a spanning tree. Under breadth-first order the class
table enqueues most symbols before the symbol table does, so the symbols are
charged to `Classes` and the `SymbolTable` root appears almost empty.

The number is correct and the reading is wrong. First-reached-parent charging is
not a dominator tree: it answers "who got here first", not "what would be
released if this were released". Every ownership claim from this tool carries
that qualification. See [todo.md](todo.md) item 18.

### A garbage collection that cannot be timed

The VM provides no callback when a collection occurs, only cumulative counters.
Collections can therefore be detected after the fact, never observed as they
happen.

The Trace drains those counters at step boundaries and draws each collection as a
span pinned to the end of the step that has just finished. The duration is real,
taken from the VM's own totals; the position inside the step is not known. A
marker means "this step lost 4 ms to a collection", never "the collection began
at this microsecond". Source: `SWATraceMarker` class comment.

## Honest pictures

### A silently short trace is a lie

A per-call trace buffer will fill. A ring buffer is the cheaper choice, but
overwriting old records orphans exits whose parents are gone, leaving a tree that
cannot be rebuilt. The lanes therefore stop recording when full and set a
truncation flag that the interface must show.

Generalisation: when a measurement is incomplete, the incompleteness is part of
the result. The same rule produces the sub-pixel handling below.

### Spans too small to draw are merged, not dropped

At any useful zoom most calls in a flame chart are narrower than a pixel.
Drawing them is impossible; discarding them would show an empty stretch where
thousands of calls ran. Runs of adjacent too-narrow siblings collapse into one
hatched box labelled with its count, and the number of spans not individually
drawn appears in the view's meta-information.

### The time axis stays honest and zoom does the work

Change history is extremely bursty: a save writes forty records in one second, a
commit stamps all of its changes with the same second, and then nothing happens
for four hours. On a linear axis most of the width is empty and each burst is a
thin spike.

Collapsing idle gaps or spacing events by rank would buy density at the cost of
x still meaning time. The timeline keeps the gaps and makes zoom the remedy, so
the rhythm of the work — nights, weekends, the shape of a day — stays readable.
Source: `SWATimelineMorph` class comment.

## Two instruments, one cause

### The FFI boundary allocates on every draw

Getting SqueakXR and SWAGame to run smoothly on the Quest turned on a conversion
nobody was looking at. Every value crossing into Raylib is converted by allocating
a fresh external structure:

```smalltalk
asRlVector
	^ RlVector3 new x: self x; y: self y; z: self z

asRlColor
	"TODO more efficient conversion. Caching?"
	^ RlColor new
		r: (self red * 255) asInteger;
		g: (self green * 255) asInteger;
		b: (self blue * 255) asInteger;
		a: (self alpha * 255) asInteger
```

`asRlColor` has 22 senders and `asRlVector` 14, concentrated in
`SRRaylibRenderer`, `SRRaylibRendererFlat` and `SRTexture` — that is, in the
render loop, once per value, per draw call, per frame.

**Two instruments converged on it.** The memory side saw the volume: thousands of
short-lived objects per frame, and the survivor work that named roughly 4,000
`Vector3` and 3,000 closure and context instances surviving each scavenge. The
external sampler saw the time: the cost showed up at the boundary rather than in
the drawing. Neither view alone identified the conversion as the thing to change;
the agreement between them did.

**And then the mechanism turned out not to be the obvious one.** The natural
reading is garbage-collection pressure: many short-lived objects, therefore many
collections, therefore lost frames. Measurement says otherwise. Squeak's scavenger
charges for survival and not for allocation — 1.5 million objects that die young
cost 13 ms of collection in total (see below) — so churn alone was never the
problem.

What the conversion actually costs is wall-clock time at the point of the call:
**4.67 us for `asRlColor` against 0.11 us for a comparable plain allocation, a
factor of 42.** Building and populating an external structure is expensive per
call, immediately, on the calling thread. At 72 Hz a thousand conversions is a
third of the frame budget before anything is drawn.

The correction matters because it changes the fix. Reducing allocation pressure
generally would not have helped; reusing `RlColor` and `RlVector3` instances
addresses the cost that is actually being paid. The TODO about caching was aimed
at the right target for a reason its author had not yet measured.

**The suspicion was already written down.** `asRlColor` carries a TODO about
caching, and `asRlMatrix` carries a three-option comment weighing reinterpreting
the byte representation via `fromHandle:`, doing the conversion externally through
FFI, and subclassing `Matrix4x4` to maintain an internal `RlMatrix`. The author
knew. What the measurement supplied was not the idea but the *priority*: a
suspicion in a comment became the item standing between the application and a
smooth frame rate on the headset.

This is the pattern the tools are actually for. They did not diagnose anything.
They made an anomaly large enough to be worth asking about.

### A desktop result that did not survive contact with the device

Measuring Squeak's scavenger on the desktop gives a clean law: cost tracks what
survives, not what is allocated. Holding allocation at 1.5 million objects and
varying only retention moves total collection time from 13 ms to 55 ms, and
per-scavenge cost from 0.76 ms to 2.75 ms. A million and a half objects that die
young cost 13 ms in total. The reassuring conclusion is that churn is nearly free
and only retention matters.

On the Quest, a scavenge with **fewer than 10,000 survivors sometimes takes 7 ms**
— about ten times worse per survivor, and half a frame at 72 Hz.

The law is not wrong; it is local. Something on the device dominates that is
absent on the desktop, and because the effect is intermittent it is most likely a
threshold being crossed — bulk tenuring, old-space growth against a constrained
memory system — rather than a steady tax. Ten thousand small objects is a few
hundred kilobytes, so whatever costs 7 ms, it is not the copying.

Two lessons, and the second is the uncomfortable one. A measurement establishes a
relationship *within the conditions it was taken in*, and the platform is one of
those conditions. And the well-lit half of this suite is well lit **on the
desktop**: every instrument in [benchmarks.md](benchmarks.md) was run against an
image on a workstation, while the performance question that actually matters lives
on a headset with a different allocator, a different memory system and a third of
the frame budget.

## Inverted intuitions

### Red means the collector failed

The allocation flamegraph colours allocation sites by retention, and the polarity
is the opposite of the usual reflex. Green marks objects that died in the
scavenge: transient, reclaimed, healthy. Red marks objects kept across it — the
working set that plateaus and is copied again on every collection.

Width remains allocation count, so the sites that matter are the wide red ones:
they allocate heavily and then keep what they allocate. A wide green band is
churn that costs nothing. Source: `SWAAllocFlamegraphMorph` class comment.

### Retention and creation are different questions

The survivor diff can say which objects outlived a scavenge and which objects
hold them. It cannot say which code made them: a surviving `Vector3` leaf carries
no stack.

Naming roughly 4,000 `Vector3` and 3,000 closure and context instances per frame
by class was as far as the object-side tools reached. The Alloc Tracer answers
the other half by instrumenting the constructor and folding the live sender chain
into a call tree. Two tools, two halves of one question, and neither substitutes
for the other. Journals
[2026-08-14b](../../journal/2026-08-14b-frame-boundary-gc-and-the-survivor-hunt.md),
[2026-08-18](../../journal/2026-08-18-allocation-survival-flamegraph-and-the-set-dont-new-question.md).

### Measuring a method makes its caller look slow

Bracketing every call with a clock read costs time, and that time falls inside
the *caller's* interval. A method that calls many small methods therefore appears
far more expensive than it is.

Each instrumented frame consequently measures its own instrumentation cost plus
that of its whole subtree and reports the sum upward, so the caller can subtract
it. Comparable to the `bias` calibration in Python's profiler, but measured per
call rather than estimated once. Source: `SWATimingWrapper` class comment.

## Less shown, more seen

### A diagram of everything is a diagram of nothing

A UML class diagram rendered over all classes and all methods of a real package
is unreadable. The containment-graph mode was removed for this reason: it was
legible only on packages small enough not to need it.

The same diagram over a dozen hand-marked classes tells a story.
`SWACodeMarkSetRootNode` builds exactly that view, with the marked set as its
root. The open problem is not rendering but derivation: where the interesting
dozen comes from. See [todo.md](todo.md) item 1.

### What one edit costs

A single class or method change fans out synchronously to about eight
subscribers of the change notifier, of which the code mapper and the working copy
are the expensive ones.

This was invisible before it was instrumented, and it is paid on every save in
every image. Source: `SWAChangeTraceRecorder` class comment, journal
[2026-08-06](../../journal/2026-08-06-flow-map-timeline-spans-and-the-calendar.md).

## Negative results

Kept because they cost the same to obtain as positive ones and are rarely
written down.

- **Young-space ages by identity-hash masking.** Marking everything currently
  alive as old hides the standing young floor, and a 22-bit hash table collides
  heavily at 2.6 M objects. Two approaches abandoned before move detection
  worked. Journals
  [2026-08-19](../../journal/2026-08-19-young-space-tally-and-two-dead-ends.md),
  [2026-08-21b](../../journal/2026-08-21b-young-space-age-dumpster-fire.md).
- **Three wrong claims about scavenge cost**, corrected by measurement. Journal
  [2026-08-14b](../../journal/2026-08-14b-frame-boundary-gc-and-the-survivor-hunt.md).
- **Forcing a collection at the frame boundary made things slower.** The intent
  was to have the scavenge land when the frame's temporaries were already dead,
  so that it would find almost nothing to copy. It was a pessimisation, and the
  mechanism only became clear later: eden holds about 4.9 MB, so a frame that
  allocates more than that is interrupted by a scavenge anyway, at a moment when
  its working set is entirely live. The forced collection did not replace that
  one, it was added to it. Still open — whether it becomes a win once the FFI
  conversions stop consuming the per-frame allocation budget is a stated
  prediction in [benchmarks.md §6](benchmarks.md).
- **A synthetic lane for the Morphic step.** Wrapping the step methods and giving
  them a lane of their own duplicated rows the trace already had. A measurement
  belongs in a band, not in a row of boxes. Source: `SWAStepTraceWrapper` class
  comment.
