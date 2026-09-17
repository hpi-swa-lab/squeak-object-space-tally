# Research Gems

![](_navigation.html)

Small, self-contained findings that might generalise beyond this project. Each is
written as a mini abstract — **domain, problem, approach, evaluation** — so that
it can be judged on its own, and later kept, developed or discarded.

Nothing here is claimed to be novel. The point is to capture an insight at the
moment it is understood, with its numbers attached, rather than letting it
dissolve back into a class comment.

<!-- MAINTENANCE
Add an entry when an argument produced a *transferable* insight, not merely a
project fact. The test: could this be told to someone who has never seen SWA and
still be useful to them?

Keep the four-part abstract at the top of each entry, short enough to read in
thirty seconds. Put the supporting numbers and the traps in a detail section
below it, and link out to benchmarks.md rather than duplicating the code.

Entries end with an honest Status line. Most will say "unevaluated beyond our own
use" for a long time, and that is fine -- the alternative is losing them.
-->

---

## 1. Identifying objects in a moving heap without retaining them

### Abstract

**Domain.** Recognising individual objects across time in a live, garbage-collected
system — the prerequisite for asking which objects survived a collection, which
were allocated by a given action, or how a population changes between samples.

**Problem.** The obvious method, holding references to the objects, destroys the
phenomenon: a retained object cannot die, so a survivor analysis that keeps its
subjects measures only its own grip. Addresses cannot substitute, because a
copying collector moves surviving objects by definition. What is needed is a
*fingerprint*: derived from the object, stable across relocation, O(1) to compute,
and — critically — **allocation-free**, since allocating during the measurement
perturbs the young space being measured.

**Approach.** `identityHash` satisfies stability and allocation-freedom (the VM
preserves it across moves; it is an immediate), but in Spur it is 22 bits against
image populations of millions, so it collides. The refinement is to augment it
with additional state chosen by two criteria that are usually confused:
*discriminating power* and *stability over the measurement window*. Augmentation
must be **shape-dependent** — `basicSize` for variable-sized objects, named
instance variables for fixed-size ones — and the admissible ingredients depend on
how long the window is. Where a domain invariant guarantees stability, it can be
exploited: an `Association`'s key is immutable by convention, because mutating it
would place the association in the wrong hash bucket and corrupt its dictionary.

**Evaluation.** Measured on a live 2.95 M-object Squeak image. `identityHash`
alone collides for 27.6% of objects globally and 0.5–6.7% within a class. Adding
`basicSize` reduces `ByteString` collisions 13-fold, from 6.74% to 0.5%; adding
three sampled bytes reaches 0.06%. For fixed-size classes, where `basicSize` is
useless, one instance variable reduces `Association` collisions 227-fold, from
4.54% to 0.02%, and two eliminate them entirely across 372,000 instances. A
fingerprint restricted to provably stable ingredients still achieves 0.02–0.5%,
so almost none of the benefit depends on assuming that mutable state holds still.
Not yet applied in production, and not validated at other heap scales.

### Detail

Full method and code in [benchmarks.md](benchmarks.md).

| Class | `identityHash` | + `basicSize` | + content sample |
|---|---:|---:|---:|
| ByteString | 6.74% | **0.5%** | 0.06% |
| Array | 2.57% | 0.33% | 0.09% |

| Class | `identityHash` | + ivar 1 | + ivars 1 and 2 |
|---|---:|---:|---:|
| Association | 4.54% | **0.02%** | **0** |
| Point | 1.14% | 0.01% | 3 |
| DateAndTime | 0.63% | **0** | 0 |

**The window determines what is admissible.** Two regimes, and only the second
needs a rule:

- A census that brackets a *single* collection while running at `highestPriority`
  has no other process executing, so nothing can mutate and any state may be used.
- A multi-sample analysis, with ordinary execution between samples, must restrict
  itself to ingredients stable under mutation: `identityHash`, class, `basicSize`
  (fixed at creation — neither `Array` nor `ByteString` grows in place), and
  invariants like the Association key.

**The error modes are asymmetric, and this is what makes the heuristic
defensible.** A collision makes two objects share a fingerprint, so a dead object
appears to have survived — a **false positive**, which sends the investigator
after a retainer that does not exist. A mutation changes one object's fingerprint,
so a survivor appears as a death plus a birth — a **false negative**, which merely
under-reports. For retention analysis the first is much the worse error, so adding
imperfectly stable state trades a serious failure for a benign one.

**Three traps, the last found by falling into it.**

1. Content must be read through mirror primitives (`thisContext object:instVarAt:`,
   `object:basicAt:`), not ordinary accessors, or a proxy intercepts the read and
   runs arbitrary code mid-walk.
2. "Nothing mutates between samples" becomes load-bearing rather than incidental,
   and should be enforced by a test rather than asserted in a comment.
3. **Packing overflows into allocation.** `SmallInteger maxVal` is 60 bits. Two
   22-bit fields pack to 44 and stay immediate; three reach 66, silently become a
   `LargePositiveInteger`, and allocate once per object — destroying the
   zero-allocation property the entire technique rests on. Use parallel
   preallocated arrays instead of packing.

**Where it applies.** `SRSurvivorCensus` and `SWAYoungSpaceState` here, and in
principle any sampling analysis of object populations in a moving-collector
runtime: allocation profiling, leak detection by population diff, generational
residency measurement.

**Open questions.** Whether the 22-bit constraint is the real limit or the
technique simply becomes unnecessary on a VM with wider identity hashes. Whether
`become:` and friends can be detected rather than merely excluded. Whether the
same collision figures hold on the Quest, where the heap is smaller but the
pressure is higher. And a literature check: fingerprinting without retention
resembles sketching and minhash techniques from a different field, and the
overlap has not been examined.

**Status.** Measured, not yet implemented. Unevaluated beyond this project.

---

## Candidates for future entries

Findings from the same session that may or may not deserve promotion. Recorded
here so the option is not lost.

- **Measuring a collector from inside the process it collects.** The family of
  tricks that make non-perturbing measurement possible: a snapshot array retains
  everything it names, a collection destroys the transients under study, buffers
  large enough to be born in old space are invisible to a young-space measurement,
  and move-detection is self-cleaning because the instrument does not move. Well
  evidenced; arguably the same gem as above seen from the other side.
- **Late binding as the substrate for composing analyses.** Referring to program
  elements by name rather than by reference, so that independently built
  visualizations can be bridged after the fact and results survive export and
  restart — the mechanism Smalltalk uses for message sends, applied one level up.
  Has a clear cost model (dangling keys, no check until lookup, renames break
  links) but no evaluation beyond "it works here".
- **Scavenge cost tracks survival, not allocation — conditionally.** Clean on the
  desktop and contradicted on the device, where fewer than 10,000 survivors
  sometimes cost 7 ms. Currently a live question rather than a finding; it becomes
  an entry only if the device mechanism is identified.
