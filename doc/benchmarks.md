# Experiments and Benchmarks

![](_navigation.html)

An active essay. Every figure below is preceded by the expression that produced
it; select a block, print it, and you have re-run the experiment. Properties that
must hold are asserted as contract tests ([tests.md §8](tests.md)); magnitudes
that merely drift are recorded here with the date they were taken.

<!-- MAINTENANCE
Every code block is standalone and runnable in a Workspace as written. When you
re-run one, append the new result next to the old rather than replacing it.

Environment for the 2026-09-17 figures:
  ARM64 Linux under WSL2, Squeak 6.0 Cog JIT, live image with the XR world and
  the MCP server running. Not a quiet machine, deliberately -- that is the
  condition the tools actually run in.

Loop timings include the enclosing timesRepeat:, so sub-microsecond figures are
upper bounds. Noted in the rows where it changes the conclusion.
-->

## 1. Why this file exists

`SWAMemoryProbe` says an NVML call costs "roughly 0.7 ms per call".
`SWAMemoryGraphMorph`, about the same call, says "0.26 ms". Both statements are
in the image; neither has a date. So measure it:

```smalltalk
| t |
SWAMemoryProbe vramUsedKB.                        "warm up"
t := Time millisecondsToRun: [50 timesRepeat: [SWAMemoryProbe vramUsedKB]].
t / 50.0
```

> **0.16** ms per call (2026-09-17).

Neither claim was right, and nobody was wrong when they wrote them. The number
moved and the prose did not. A magnitude in a class comment is a claim with no
owner and no expiry, which is the whole argument for this file.

## 2. Two kinds of empirical claim

| | Property | Magnitude |
|---|---|---|
| Form | holds or does not | a number |
| Example | `identityHash` survives a scavenge | a heap sweep costs 43 ms |
| Fails by | becoming false | drifting |
| Belongs in | a contract test, [tests.md §8](tests.md) | here |
| On change | the build breaks | the figure is appended to |

Conflating the two is how these ended up in comments. A property genuinely is
documentation; a magnitude is a measurement wearing documentation's clothes.

## 3. The cost of asking

### Reading the clock

`SWATimingWrapper` brackets every instrumented call with two clock reads, and its
overhead compensation is built on what that costs. The class comment says
"~0.1 us per read".

```smalltalk
| n t |
n := 100000.
t := Time millisecondsToRun: [n timesRepeat: [Time utcMicrosecondClock]].
t * 1000.0 / n
```

> **0.33** us per read (2026-09-17), including the `timesRepeat:` overhead, so an
> upper bound. Still three times the stated figure.

This is the measurement with consequences. Two reads per call at 0.33 us puts the
floor below which a wrapper cannot usefully time a method three times higher than
the comment implies, which is an argument for the sampling tools over the timing
wrapper across a wider band of method sizes than previously assumed.

### Reading a VM counter

The GC graphs and `SWATraceSeries` poll `vmParameterAt:` once per frame. Whether
that is affordable was never checked.

```smalltalk
| n t |
n := 100000.
t := Time millisecondsToRun: [n timesRepeat: [Smalltalk vmParameterAt: 2]].
t * 1000.0 / n
```

> **0.01** us per read (2026-09-17).

Effectively free. Polling several counters per frame costs nothing measurable,
which retrospectively justifies `SWAStepTraceWrapper` taking four readings per
Morphic cycle without a second thought.

### Reading the process and the device

Three sources, three very different costs, which is why the memory graph throttles
some strips and not others.

```smalltalk
| t |
{ Time millisecondsToRun: [200 timesRepeat: [SWAMemoryProbe rssKB]]       / 200.0.
  Time millisecondsToRun: [20  timesRepeat: [SWAMemoryProbe smapsRollup]] / 20.0.
  Time millisecondsToRun: [50  timesRepeat: [SWAMemoryProbe vramUsedKB]]  / 50.0 }
```

> **0.05** ms (`/proc/self/statm`), **13.4** ms (`/proc/self/smaps_rollup`),
> **0.16** ms (NVML) — 2026-09-17.
>
> Claimed in comments: 0.08 ms, ~23 ms, 0.7 ms / 0.26 ms.

`statm` is cheap enough for the per-frame path, `smaps_rollup` is not and never
was, and the ordering the code relies on is unchanged even though every
individual number has moved.

### Sweeping the heap

Every tool in the heap-diff family begins with this call, twice.

```smalltalk
Time millisecondsToRun: [SystemNavigation default allObjectsOrNil]
```

> **43** ms (2026-09-17). The `SWAHeapDiff` comment claims ~50 ms.

The one recited figure that held. It is also the figure that justifies the
two-phase design: at 43 ms a pair of sweeps fits inside a frame budget only
barely, which is why the expensive set operations are deferred out of the hot
path.

## 4. Properties

### `identityHash` survives a scavenge — known, and not the open question

Stability across a collection was established long before this file and is not in
doubt. It is worth keeping as a cheap contract test, since it is the premise
`SRSurvivorCensus` rests on, but it is not what needed measuring. The open
question is **collisions**, in the section after this one.

```smalltalk
| objs before after |
objs := (1 to: 2000) collect: [:i | Array new: 3].
before := objs collect: [:o | o identityHash].
Smalltalk garbageCollectMost.
after := objs collect: [:o | o identityHash].
(1 to: objs size) count: [:i | (before at: i) = (after at: i)]
```

> **2000** of 2000 unchanged (2026-09-17). Holds.

### How often does `identityHash` actually collide?

`SRSurvivorCensus` fingerprints objects instead of retaining them, and its class
comment concedes the limitation: "identityHash is 22 bits, so with millions of
objects hashes collide. The result is therefore a class-composition estimate
(counts by class are robust to individual collisions), not exact per-object
identity."

That "robust to individual collisions" was asserted and never measured. It is the
assumption the whole technique stands on, so measure it.

```smalltalk
| objs n bits distinct maxH |
objs := SystemNavigation default allObjectsOrNil.
n := objs size.
bits := ByteArray new: 524288.   "2^22 bits, one per possible hash"
distinct := 0.  maxH := 0.
1 to: n do: [:i | | h bi bm b |
	h := (objs at: i) identityHash.
	h > maxH ifTrue: [maxH := h].
	bi := (h bitShift: -3) + 1.
	bm := 1 bitShift: (h bitAnd: 7).
	b := bits at: bi.
	(b bitAnd: bm) = 0 ifTrue: [bits at: bi put: (b bitOr: bm). distinct := distinct + 1]].
{ n. distinct. maxH. n - distinct }
```

> 2026-09-17, 692 ms: **2,953,348 objects**, **2,139,167 distinct hashes**, max
> hash 4,194,302 (confirming a 22-bit space of 4,194,304 values).
>
> **814,181 objects — 27.6% — share a hash with another object.**

Globally, then, better than one object in four collides. If the census matched
fingerprints across the whole heap, that would be its error rate, and the
technique would be unusable.

But the claim is about counts *within a class*, and that is a different birthday
problem: the population is the class's instance count, not the heap's.

```smalltalk
| objs counts top |
objs := SystemNavigation default allObjectsOrNil.
counts := IdentityDictionary new.
1 to: objs size do: [:i | | c |
	c := (objs at: i) class.
	counts at: c put: (counts at: c ifAbsent: [0]) + 1].
top := (counts associations asSortedCollection: [:a :b | a value >= b value]) asArray first: 10.
top collect: [:assoc | | inst hashes |
	inst := assoc key allInstances.
	hashes := Set new: inst size.
	inst do: [:o | hashes add: o identityHash].
	{ assoc key name. inst size. hashes size. inst size - hashes size }]
```

> 2026-09-17, ten largest classes by instance count:
>
> | Class | Instances | Distinct hashes | Colliding | % |
> |---|---:|---:|---:|---:|
> | ByteString | 806,111 | 752,008 | 54,103 | **6.7** |
> | Array | 469,339 | 448,513 | 20,826 | **4.4** |
> | Association | 395,243 | 376,473 | 18,770 | **4.7** |
> | CompiledMethod | 99,483 | 98,622 | 861 | 0.9 |
> | LargePositiveInteger | 92,671 | 91,906 | 765 | 0.8 |
> | GitTreeEntry | 81,734 | 81,127 | 607 | 0.7 |
> | SWAOpenCodePart | 80,128 | 79,728 | 400 | 0.5 |
> | ByteSymbol | 77,892 | 77,266 | 626 | 0.8 |
> | Point | 78,705 | 77,677 | 1,028 | 1.3 |
> | DateAndTime | 71,733 | 71,275 | 458 | 0.6 |

**The assumption holds, and now has an error bar.** Within-class collision runs
0.5% to 6.7%, against 27.6% globally, because only the very largest classes
approach a population where a 22-bit space gets crowded. A class-composition
estimate from this technique is good to a few percent for the biggest classes and
under one percent for everything else.

**One consequence worth acting on.** The gap between 6.7% and 27.6% is entirely a
matter of *when* the class is taken into account. If the census bins fingerprints
by class before matching, its error is the first column. If it matches hashes
globally and attributes classes afterwards, it inherits the second, and a hash
freed by a dying `ByteString` can be reused by a newborn `Array` and counted as a
survivor of the wrong class. Which of the two `SRSurvivorCensus` does is worth
checking; per-class binning is roughly five times more accurate for no extra cost.

### A better fingerprint, for free

If `identityHash` alone collides, what other state is cheap, stable across a
move, and available without allocating? Two candidates: **`basicSize`** for
variable-sized objects, and a **sample of content** — bytes for byte objects,
slot or instance-variable `identityHash`es for pointer objects.

Content is only usable if nothing mutates between the two walks. That holds here,
but not by luck: the census already runs at `highestPriority` so that nothing else
executes or allocates in the window. What was a performance decision turns out to
be the precondition that makes content-based fingerprinting sound at all.

```smalltalk
"variable-sized: identityHash, then + basicSize, then + three sampled bytes"
| inst n h1 h2 h3 |
inst := ByteString allInstances.
n := inst size.
h1 := Set new: n.  h2 := Set new: n.  h3 := Set new: n.
inst do: [:o | | hh sz fp b |
	hh := o identityHash.  sz := o basicSize.
	h1 add: hh.
	fp := hh * 4194304 + (sz min: 4194303).
	h2 add: fp.
	sz > 0
		ifTrue: [
			b := ((o basicAt: 1) * 65536) + ((o basicAt: sz) * 256) + (o basicAt: sz + 1 // 2).
			h3 add: fp * 16777216 + (b \\ 16777216)]
		ifFalse: [h3 add: fp]].
{ n. n - h1 size. n - h2 size. n - h3 size }
```

> Variable-sized classes, 2026-09-17:
>
> | Class | n | hash | + `basicSize` | + size + content |
> |---|---:|---:|---:|---:|
> | ByteString | 807,912 | 54,449 (6.74%) | 4,018 (**0.5%**) | 447 (**0.06%**) |
> | Array | 236,878 | 6,088 (2.57%) | 787 (0.33%) | 223 (0.09%) |

`basicSize` alone is a **13x** improvement on strings, for a header-field read.

It does nothing at all for **fixed-size** classes, where `basicSize` is 0 for
every instance — which is why `Association` was unmoved. Those need named
instance variables instead:

> Fixed-size classes, sampling `instVarAt:` 1 and 2:
>
> | Class | n | hash | + ivar 1 | + ivars 1 and 2 |
> |---|---:|---:|---:|---:|
> | Association | 372,139 | 16,894 (4.54%) | 65 (**0.02%**) | **0** |
> | Point | 71,032 | 811 (1.14%) | 5 (0.01%) | 3 |
> | DateAndTime | 71,166 | 450 (0.63%) | **0** | 0 |

One instance variable takes `Association` from 4.54% to 0.02%, a factor of 227.
Two give zero collisions across 372,000 instances.

**So the fingerprint should be shape-dependent**, and everything it needs is O(1)
per object: `identityHash` always, `basicSize` when the object is variable-sized,
and one or two content samples — bytes for byte objects, slot or ivar
`identityHash`es for pointer objects. That moves collisions from 0.6–6.7% to
0.0–0.09%, roughly two orders of magnitude.

Three implementation warnings, the last of which is the dangerous one:

1. **Content must be read through the mirror primitives.** `SWASpaceTally` uses
   `thisContext object:instVarAt:` and `object:basicAt:` precisely so that proxies
   such as `FutureMaker` and `Context` cannot intercept the access. A census
   reading `instVarAt:` directly would invoke overridden accessors and could run
   arbitrary code mid-walk.
2. **No-mutation-between-walks is now load-bearing**, not incidental. It deserves
   a contract test rather than a comment.
3. **Packing overflows into allocation.** `SmallInteger maxVal` is 60 bits. Two
   22-bit fields pack to 44 bits and stay immediate; **three do not** — they reach
   66 bits and silently become a `LargePositiveInteger`, which allocates, once per
   object, destroying the zero-allocation property the whole technique rests on.
   The measurement above did exactly that. Either cap the fields to fit 60 bits,
   or avoid packing entirely and use parallel preallocated arrays, which is the
   pattern `SWAYoungSpaceState` already uses for its `hashArrays`.

Note also that instance counts drift between runs in a live image — `Array` reads
469,339 in one measurement above and 236,878 in another, minutes apart. Collision
*rates* are stable; absolute counts are not.

### Which ingredients may be assumed stable

Content is only usable if it does not change between samples, and that depends
entirely on the window:

| Regime | Window | What may be used |
|---|---|---|
| `SRSurvivorCensus` | two walks bracketing one scavenge, at `highestPriority` | **everything** — no other process runs, so nothing can mutate |
| `SWAYoungSpaceState` | N samples with ordinary execution in between | only ingredients that are stable under mutation |

The second regime is the one that needs a rule. Ranked by how safe each ingredient
is to assume:

| Ingredient | Stability | Basis |
|---|---|---|
| `identityHash` | total | preserved across moves; measured above |
| class | total, barring `become:` / `adoptInstance:` | objects do not change class |
| `basicSize` | total | `Array` and `ByteString` are fixed-size at creation; neither grows in place |
| Association **key** | immutable by convention | mutating it would put the association in the wrong hash bucket and corrupt its dictionary; `key:` has 128 senders |
| Association **value** | mutable | `value:` has **11x** as many senders (1,431); `Dictionary>>at:put:` sets the value of an existing association |
| `Array` / `ByteString` contents | mutable | `at:put:` is ordinary usage |

**The failure directions are not symmetric, and that settles the trade.**

- A **collision** makes two distinct objects share a fingerprint, so a dead object
  looks like a survivor. That is a **false positive**, and it sends you
  investigating a retainer that does not exist.
- A **mutation** changes one object's fingerprint, so a survivor looks like a
  death plus a birth. That is a **false negative**, and it merely under-reports.

For retention analysis the false positive is much the worse error, because the
whole point is to chase what is named. So adding state to the fingerprint trades a
serious error for a benign one, even when the added state is not perfectly stable.

**And the stable-only fingerprint is already almost as good as the unrestricted
one.** `instVarAt: 1` on an `Association` *is* the key — `allInstVarNames` is
`#('key' 'value')` — so the 0.02% row measured above used nothing but stable
state. Restricting to identityHash, class, `basicSize` and the Association key
gives:

| Class | hash alone | stable-only fingerprint |
|---|---:|---:|
| Association | 4.54% | **0.02%** (key) |
| ByteString | 6.74% | **0.5%** (size) |
| Array | 2.57% | **0.33%** (size) |

Between 13x and 227x better, with no assumption that any mutable field holds
still. Content sampling buys a further 5–8x and should be reserved for the
single-window census, where it is free of risk.

Written up as a standalone finding in [research.md](research.md) entry 1.

### A large allocation is born old — and a failed experiment

`SWAYoungSpaceState` relies on its ~21 MB buffer being born directly in old
space, so that the instrument is invisible to the measurement. The first attempt
to verify this was wrong, and is kept here because the mistake is instructive:

```smalltalk
"WRONG -- proves nothing. Do not use."
| big before after |
big := Array new: 3000000.
before := big identityHash.
Smalltalk garbageCollectMost.
after := big identityHash.
before = after
```

> `true` — and meaningless.

The section above establishes that `identityHash` is *preserved across a move*.
An unchanged hash is therefore consistent with the object having moved and with
it not having moved. The two experiments cannot share an instrument: properties
about **movement** require the raw address, properties about **identity** may use
the hash.

The valid form reads the address the way the production code does, via
`AlienStub>>addressField`, one object at a time and never feeding an oop back.
Not yet run here, and it belongs with the contract tests rather than as a
one-off:

```smalltalk
"TO WRITE -- see tests.md §8. Sketch only."
| probe big a1 a2 small s1 s2 |
probe := AlienStub new.
big := Array new: 3000000.       "expected old: should not move"
small := Array new: 3.            "expected young: should move"
a1 := probe addressOf: big.  s1 := probe addressOf: small.
Smalltalk garbageCollectMost.
a2 := probe addressOf: big.  s2 := probe addressOf: small.
{ a1 = a2.      "expect true  -- born old"
  s1 = s2 }     "expect false -- young, moved"
```

Three further properties are load-bearing and not re-verified here: young objects
move while old ones do not, `allObjectsOrNil` returns new space as a contiguous
tail, and the tight census walk allocates nothing. All three are listed in
[tests.md §8](tests.md).

## 5. The runtime under measurement

Sections 3 and 4 measure the instruments. This one measures the subject, and it
is where the instruments have changed what we believe.

### Scavenging cost tracks survival, not allocation

The intuitive worry is that creating many short-lived objects is expensive. For a
generational copying collector it should not be: a scavenge copies the survivors
and abandons the rest, so objects that die young cost nothing to collect. That is
a claim about Squeak specifically and it is testable — hold allocation volume
constant and vary only how much survives.

```smalltalk
| n run |
n := 1500000.
run := [:keepEvery | | c0 m0 c1 m1 t keep |
  keep := keepEvery > 0 ifTrue: [OrderedCollection new: (n // keepEvery) + 8] ifFalse: [nil].
  Smalltalk garbageCollectMost.
  c0 := Smalltalk vmParameterAt: 9.  m0 := Smalltalk vmParameterAt: 10.
  t := Time millisecondsToRun: [
    1 to: n do: [:i | | a |
      a := Array new: 6.
      (keep notNil and: [i \\ keepEvery = 0]) ifTrue: [keep add: a]]].
  c1 := Smalltalk vmParameterAt: 9.  m1 := Smalltalk vmParameterAt: 10.
  { keepEvery. t. c1-c0. m1-m0. (keep ifNil: [0] ifNotNil: [keep size]) }].
{ run value: 0. run value: 10. run value: 2 }
```

> 2026-09-17, 1.5 M allocations in every case:
>
> | Retained | Wall ms | Scavenges | GC ms | Survivors | GC ms per scavenge |
> |---|---:|---:|---:|---:|---:|
> | none | 141 | 17 | **13** | 0 | 0.76 |
> | 10% | 192 | 18 | **15** | 150,000 | 0.83 |
> | 50% | 294 | 20 | **55** | 750,000 | 2.75 |

Allocation volume and scavenge count are effectively constant across the three
runs; only survival changes. Total collection time rises 4.2x and per-scavenge
cost 3.6x. **One and a half million objects cost 13 ms of GC if they all die.**

The practical consequence is that allocation rate is the wrong thing to optimise.
Survival rate is the thing, which is exactly the polarity already encoded in the
allocation flamegraph — red for kept, green for reclaimed
([stories.md](stories.md)).

> **This result is desktop-only and does not transfer.** On the Quest a scavenge
> with under 10,000 survivors sometimes costs 7 ms, roughly ten times worse per
> survivor than measured here. Whatever dominates on the device is not survivor
> count. See [section 6](#6-squeakxr-benchmarks) before applying any of this to
> the headset.

### You do not choose when a scavenge happens; eden does

The open puzzle is why survivors accumulate at all. The ideal model says a
scavenge should land *after* the frame's work, when the temporaries are dead, and
find almost nothing to copy. Forcing exactly that at the frame boundary was tried
and made things **slower** (journal 2026-08-14b). The reason is visible once you
measure what actually schedules a collection.

```smalltalk
| samples |
samples := OrderedCollection new.
Smalltalk garbageCollectMost.
[samples size < 6] whileTrue: [ | c0 b0 c1 b1 s0 s1 |
	c0 := Smalltalk vmParameterAt: 9.   b0 := Smalltalk vmParameterAt: 34.
	s0 := Smalltalk vmParameterAt: 35.
	[(Smalltalk vmParameterAt: 9) = c0] whileTrue: [200 timesRepeat: [Array new: 6]].
	c1 := Smalltalk vmParameterAt: 9.   b1 := Smalltalk vmParameterAt: 34.
	s1 := Smalltalk vmParameterAt: 35.
	samples add: { b1 - b0. s1 - s0 }].
samples
```

> 2026-09-17. Bytes allocated between consecutive scavenges:
> 5.14, 4.21, 5.14, 5.58, 5.17, 5.58 MB — **eden is about 4.9 MB**.
>
> Parameter 35, documented as *survivors* in `SRGCRecorder`, is a **gauge and not
> a counter**: it reads 5,976 on an idle image and 18,722 after retaining 200,000
> objects, so it reports current survivor-space occupancy. Taking deltas of it per
> scavenge, as an earlier version of this section did, is meaningless.

**Allocation volume schedules the collector, not the program.** If a frame
allocates more than about 4.9 MB, at least one scavenge lands *inside* the frame,
at a moment when the frame's working set is still entirely live — and every one
of those live objects is copied. Forcing an additional collection at the frame
boundary cannot prevent that one. It only adds a second collection to the frame,
which is precisely the observed slowdown.

So "why do survivors build up" separates into two questions that are measured
differently:

1. **Are scavenges landing mid-frame?** Measurable as frames-between-scavenges,
   which is already on the fps lane (journal 2026-09-15). Below one frame per
   scavenge, boundary forcing cannot work.
2. **Of what survives, how much is genuinely live at that instant, and how much is
   a standing floor** that is re-copied every time until tenured? The survivor
   diff with provenance by home method already answers this; the ~3,000 closures
   and contexts it named are the suspicious part, since deferred messages and
   callbacks hold their outer contexts live by construction.

### The FFI boundary costs 42x an ordinary allocation

If short-lived objects are cheap, why is conversion at the Raylib boundary a
problem? Measure the conversion against a plain allocation of similar size.

```smalltalk
| n c v |
n := 100000.
c := Color red.  v := Vector3 x: 1.0 y: 2.0 z: 3.0.
{ (Time millisecondsToRun: [n timesRepeat: [c asRlColor]])  * 1000.0 / n.
  (Time millisecondsToRun: [n timesRepeat: [v asRlVector]]) * 1000.0 / n.
  (Time millisecondsToRun: [n timesRepeat: [Array new: 6]]) * 1000.0 / n }
```

> **4.67** us for `asRlColor`, **4.57** us for `asRlVector`, **0.11** us for
> `Array new: 6` (2026-09-17). A factor of **42**.

This separates two explanations that were previously entangled. The cost of an
FFI conversion is **not** garbage-collection pressure — the section above shows
that short-lived objects are nearly free to collect. It is the wall-clock cost of
building and populating an external structure, paid immediately, on the calling
thread.

The arithmetic matters for the headset. At 72 Hz a frame is 13.9 ms, so a
thousand conversions per frame is 4.7 ms, a third of the budget, before anything
is drawn.

It also changes what the fix has to be. Reducing GC pressure in general would not
have helped; caching or reusing `RlColor` and `RlVector3` instances addresses the
actual cost. The `"TODO more efficient conversion. Caching?"` already in
`Color>>asRlColor` was aimed at the right target for a reason its author had not
yet measured.

### Iterating all objects, and an untested confound

Full-heap iteration is slow, and there was a suspicion that instrumentation was
responsible. Check for live wrappers first, then measure the three ways of
walking the heap.

```smalltalk
| wrappers n |
wrappers := SWAMethodWrapper allSubclasses
	inject: SWAMethodWrapper allInstances size
	into: [:a :c | a + c allInstances size].
n := 0.
{ wrappers.
  Time millisecondsToRun: [SystemNavigation default allObjectsOrNil].
  Time millisecondsToRun: [ | o |
	o := Object nextObject.
	[o == nil or: [o == 0]] whileFalse: [n := n + 1. o := o nextObject]].
  n.
  Time millisecondsToRun: [Array allInstances] }
```

> 2026-09-17, with **0 live wrappers**:
>
> | Method | ms | Note |
> |---|---:|---|
> | `Array allInstances` | 16 | |
> | `allObjectsOrNil` | **61** | earlier the same day: 43 |
> | `nextObject` full walk | **317** | over 2,536,862 objects |

`nextObject` is roughly five times the cost of `allObjectsOrNil`, and the image
was **not instrumented** when this was taken, so that gap is real rather than an
artefact of measurement. The two are also not interchangeable: `SWAYoungSpaceState`
records that `nextObject` from the heap head walks old space only and never
reaches young.

The confound is not thereby settled, only bounded. Zero wrappers *now* does not
establish that zero wrappers were live when the slowness was first noticed. What
exists now is a clean baseline; the experiment that would settle it is the same
block run with a known number of wrappers installed, which belongs with the
instrumentation tier in [tests.md §6](tests.md).

Note also the 43 ms / 61 ms spread for the same call on the same day. Live-image
timings carry that much variance, which is an argument for reporting ranges and
against reading a 20% difference as a result.

## 6. SqueakXR benchmarks

### The observation that breaks the desktop model

On the Quest, a scavenge with **fewer than 10,000 survivors sometimes takes 7 ms**.
On the desktop, roughly 37,500 survivors cost 2.75 ms.

That is about ten times worse per survivor, and it is the single most important
figure in this file, because it falsifies the model built in section 5. *Cost
tracks survival* is a desktop result. On the device the dominant term is something
else, and at 7 ms out of a 13.9 ms frame at 72 Hz it consumes half the budget.

Three properties of the observation constrain the explanation:

- **Survivor count is low.** Ten thousand small objects is a few hundred
  kilobytes. No plausible memory bandwidth makes copying that take 7 ms. The cost
  is not in the copying.
- **It is intermittent** — "sometimes". A constant per-scavenge overhead would
  show on every collection. Intermittency points to a **threshold being crossed**,
  not a steady tax.
- **It does not reproduce on the desktop** at all, on the same code.

Candidates, each with the parameter that would confirm or eliminate it. All four
are already recorded per sample by `SRGCRecorder`, so the instrument exists and
needs only to be run on the device and correlated against the outliers:

| Candidate | Mechanism | Diagnostic |
|---|---|---|
| **Tenuring** | survivors promoted to old space, in bulk when survivor space overflows | `p11` delta on the expensive scavenges only |
| **Old-space growth** | promotion forces the heap to grow; on a memory-constrained device that means fresh pages from the OS | `p1` delta coinciding with the spike |
| **Remembered set** | old-to-young pointers scanned as roots every scavenge, independent of survivor count | `p21`, which on the desktop sits near 900 idle |
| **Device memory behaviour** | page faults, commit cost, thermal or scheduling effects absent on desktop | none of the above move, yet the time does |

Tenuring is the first place to look. The desktop run above shows `p11` jumping by
162,000 the instant objects were retained into a long-lived collection, and
tenuring is exactly the kind of bulk, threshold-triggered work that is cheap when
memory is plentiful and expensive when it is not.

**The diagnostic is a per-scavenge delta, not an average.** Record `p1`, `p9`,
`p10`, `p11`, `p21` on the device, isolate the scavenges whose `p10` delta is
large, and ask what else moved on exactly those. An average over a run hides the
outliers, which are the entire phenomenon.

Note also that the VM's GC counters are in whole milliseconds, so sub-millisecond
scavenges round hard. A 7 ms reading is well clear of that, but the 0.2 ms
desktop comparison has to be derived from totals over many collections rather than
read off a single one.

### Everything else

The measurements above were taken from the desktop image and mostly by hand. The
open questions about running SqueakXR and SWAGame smoothly on the Quest need a
standing set, and none of these exist yet.

| Question | Experiment |
|---|---|
| How many FFI conversions happen per frame? | count `asRlColor` / `asRlVector` / `asRlMatrix` calls over a frame with an invocation tally; 36 call sites are known, the per-frame multiplier is not |
| What does a cached conversion save? | a reusable `RlColor` against the current allocate-per-call, measured as in section 5 |
| Where does frame time actually go? | st-spy against the render loop, with the conversion cost above as the expected term |
| What survives a frame, and from where? | allocation flamegraph over one frame, coloured by retention |
| Does the desktop result hold on the device? | every block above, run through the XR image; different allocator, different clock, no NVML |
| Is full-heap iteration on any hot path? | senders of `allObjectsOrNil`, `nextObject` and `allInstances` reachable from the render loop |

The last row is worth doing first because it is free: if nothing on the hot path
iterates the heap, the 317 ms figure is a tooling cost rather than an application
one, and the question closes.

### Hypothesis: the scavenge lands on the peak, every frame

Not yet tested. Recorded now so that the prediction precedes the measurement.

The claim is that **per-frame liveness is not flat — it has a peak**, and where the
scavenge lands within that shape decides what it costs. Mid-computation, the stack
is deep and every frame of it is a GC root: receivers, arguments and temporaries,
plus everything transitively reachable from them. A render loop accumulating
vertex data, building a batch and then submitting it has a moment where that whole
intermediate is live and young. A scavenge at that instant copies it. The same
scavenge at the frame boundary, where the stack is shallow and the batch has been
handed off, copies almost nothing.

A single unlucky collection does not matter. The hypothesis is about **rhythm**:
if per-frame allocation is roughly constant and eden is fixed at ~4.9 MB, then
scavenges recur at a fixed allocation interval and therefore land at roughly the
same *phase* of every frame. If that phase coincides with the liveness peak, the
peak is copied every frame, forever.

Two things already support the underlying mechanism, and one obstacle blocks the
specific claim.

**Supported.** Cost per scavenge tracks what is alive at collection time, measured
above: 0.76 ms with nothing retained against 2.75 ms at 50% retention, with
allocation volume and scavenge count held constant. Liveness at the instant of
collection is the variable that matters.

**Also supported.** Frame allocation near eden capacity is exactly the regime that
produces phase locking rather than drift. At ~1 scavenge per frame the phase is
stable; far away from that ratio it would wander and the cost would average out.

**The obstacle.** The existing instruments cannot locate a scavenge *within* a
frame. The VM offers no collection callback, only cumulative counters, so
`SWATraceMarker` detects a collection after the fact and pins it to the end of the
step, explicitly recording that the duration is real but the position is not. The
one measurement this hypothesis needs is the one currently unavailable.

**The experiment that would settle it.** Drain the counters at several points
across the render loop instead of once per cycle — the `SWAStepTraceWrapper`
pattern at finer granularity. Each probe records `vmParameterAt: 9` and `10`, so
an increment localises the collection to the segment between two probes. Over many
frames that yields a phase histogram, and pairing each scavenge with the cost
delta yields cost by phase.

Predictions, in falsifiable order:

1. The phase distribution is **not uniform**. Uniform phase refutes the rhythm
   claim outright and the hypothesis fails here.
2. Per-scavenge cost **correlates with phase**, with the expensive ones clustered
   in the deep-stack segments rather than spread evenly.
3. **Detuning moves it.** Changing per-frame allocation volume — which the FFI fix
   does substantially — should shift or break the phase lock. If the lock is real,
   cost variance rises and mean cost falls as the ratio moves away from one
   scavenge per frame. This is the strongest test, because a resonance responds to
   detuning and a constant does not.

If all three hold, the cost decomposes into two independent factors with different
remedies:

| Factor | Driven by | Lever |
|---|---|---|
| Scavenges per frame | per-frame allocation volume | remove allocation, e.g. the FFI conversions |
| Cost per scavenge | liveness at the moment of collection | shift the phase, or flatten the peak by holding less across the deep part of the stack |

That decomposition also explains why the frame boundary was the right instinct.
It is special for two reasons, and the one about stack depth is the stronger:
temporaries are dead there, *and* the stack is shallow, so a collection forced
there is cheap. It only helps if it happens **instead of** the mid-frame one,
which requires the frame to fit inside eden.

### A prediction worth recording before it is tested

Frame-boundary collection was tried and was a pessimisation. The eden measurement
above supplies a mechanism: if a frame allocates more than ~4.9 MB, a scavenge
lands mid-frame regardless, and forcing a second one at the boundary adds work
without removing any.

The FFI conversions are a large, removable part of that per-frame volume. So:

> **Prediction.** Once `RlColor` and `RlVector3` allocation per draw call is
> removed, frames-per-scavenge rises. If it rises above one, forced
> frame-boundary collection should stop being a pessimisation and begin behaving
> as the ideal model predicts — a collection that finds few survivors because the
> frame's temporaries are already dead.

Falsifiable, and it fails in an informative way. If frames-per-scavenge rises
above one and boundary forcing is *still* slower, then the survivors are not
frame temporaries at all but a standing floor — caches, deferred-message closures,
scene state — and the target moves from allocation volume to retention. That is
the survivor diff's question, not the allocation flamegraph's.

Measure in this order: frames-per-scavenge before the change, then after, then
re-try the forced boundary collection. Recording the before figure is the part
that is easy to skip and impossible to reconstruct later.

## 7. Scaling

A single figure misleads wherever cost is superlinear. The duplication scan is
the case that matters, because it is currently unusable on the whole suite.

```smalltalk
| rows |
rows := OrderedCollection new.
#('SWA-Widgets' 'SWA-ClassDiagram' 'SWA-Duplication' 'SWA-Coverage' 'SWA-Nodes')
  do: [:cat | | m t n |
    m := 0.
    (SystemOrganization listAtCategoryNamed: cat) do: [:cn | | c |
      c := Smalltalk at: cn ifAbsent: [nil].
      c ifNotNil: [m := m + c selectors size + c class selectors size]].
    t := Time millisecondsToRun: [n := (SWACodeSimilarity new duplicatesInPackage: cat) size].
    rows add: { cat. m. t. n }].
rows
```

> 2026-09-17, at the default threshold of 0.7:
>
> | Package | Methods | ms | Pairs |
> |---|---:|---:|---:|
> | SWA-Widgets | 29 | 49 | 0 |
> | SWA-ClassDiagram | 38 | 36 | 0 |
> | SWA-Duplication | 43 | 90 | 0 |
> | SWA-Coverage | 168 | 1418 | 0 |
> | SWA-Nodes | 340 | 2749 | 3 |
> | SWA-Base | 650 | 14102 | 2 |

Shingle construction is linear in source length; the comparison is pairwise. Below
about 340 methods the linear part dominates and cost looks nearly linear — 168 to
340 methods doubles the time for double the methods. From 340 to 650 it grows by a
factor of five for a factor of 1.9, an exponent near 2.5, because `SWA-Base` also
holds the longest methods in the suite.

Extrapolation is unsafe, but even the quadratic reading puts a scan of all 2,608
selectors at four minutes and the observed exponent puts it near eight. That
settles the design question in [smells.md §9.2](smells.md): a whole-suite
duplication scan cannot be a synchronous call and belongs behind the existing
async Generate pattern.

### Still curves without points

| Experiment | Known points |
|---|---|
| Squarify layout vs tile count | ~6.3k tiles ≈ 7.6 s, build+LOC ≈ 0.7 s (2026-06-23, unverified) |
| Space Tally vs heap size | defaults moved from 200k to 3M visits for full walks |
| Heap-diff noise floor vs image activity | 1500–2300 objects at rest |
| Wrapper cost vs call rate | eviction threshold chosen, never measured |
| Git history scan vs commit count | ~50 ms per commit |
| OpenCode scan vs database size | ~30 s over 1.4 GB, down from 55 s |

Squarify is the next one worth taking, since it is what the progress bars exist
to hide.

## 8. The suite's own tests

```smalltalk
| s |
s := TestSuite new.
(SystemOrganization listAtCategoryNamed: 'SWA-Tests') do: [:n | | c |
  c := Smalltalk at: n.
  (c inheritsFrom: TestCase) ifTrue: [s addTests: c buildSuiteFromSelectors tests]].
s run
```

> **29 run, 29 passes, 0 failures, 0 errors, 2.7 s** (2026-09-17).

## 9. Not measurable here

- **Anything on the Quest.** These are desktop figures. The Quest has no NVML, a
  different allocator profile and a different clock. A device column needs the
  same blocks run through the XR image.
- **Sampling accuracy.** The samplers can be compared against each other
  ([landscape.md §3.1](landscape.md#31-execution-five-instruments-for-one-question)),
  but there is no ground truth to measure either against.
- **Anything depending on the live world's contents**, which change under the
  measurement.

## 10. Two rules

The harness matters less than these.

1. **Class comments should stop quoting magnitudes.** A number in a comment has
   no date, no machine and no way to be re-run. Comment the constraint — "too
   expensive for the per-frame path" — and put the figure here with its code.
   This is the existing comment rule, reasons and constraints rather than
   behaviour, applied to measurements.
2. **Never overwrite a superseded figure; append.** Two dated numbers are a
   trend. One undated number is the situation this file exists to end.

A `SWABenchmark` in `SWA-Tests`, one method per block above, would make a re-run
one send instead of a paste. It shares fixtures with the contract tests and
differs only in asserting nothing. See [todo.md](todo.md) item 25.
