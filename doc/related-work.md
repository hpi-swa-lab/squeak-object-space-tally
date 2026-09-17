# SWA -- Related Work

![](_navigation.html)

<!-- MAINTENANCE
Citations below are from recall and are NOT verified against the literature.
Author/venue/year must be checked before any of this goes into a paper, a talk
or a grant application. Items marked (?) are the ones held with least confidence.

Structure follows views.md: measure, relate, reduce. The reduce section is the
one that matters for positioning -- it is where the suite's actual contribution
would have to be defended, and it is the section that was missing entirely until
2026-09-17.
-->

Grouped by the operations of [views.md §3](views.md#3-four-operations). Observation
is largely inherited from Squeak and is old; the groups that matter for
positioning are reduction and relation.

## Reduction, focus and degree of interest

The claim that contrast rather than brightness reveals structure is not new, and
this is the literature the suite must be positioned against.

- **Generalized Fisheye Views** (Furnas, CHI 1986) -- degree of interest as
  *a priori* importance minus distance from the focus; the origin of the idea
  that a view should compute what to omit.
- **Mylar / Mylyn task context** (Kersten, Murphy, AOSD 2005 / FSE 2006) -- a
  degree-of-interest model over program elements, built from what the developer
  actually touched, used to filter the IDE itself. The closest prior art to
  [todo.md](todo.md) item 1: deriving the interesting set rather than selecting
  it by hand.
- **Visual information-seeking mantra** (Shneiderman, 1996) -- overview first,
  zoom and filter, then details on demand. The treemap navigation follows it.
- **Degree-of-interest trees** (Card, Nation, 2002) (?) -- DOI applied to tree
  layout under fixed screen space.
- **Differential flame graphs** (Gregg) -- difference of two profiles as the
  primary artefact rather than a profile.

The suite's reduction mechanisms ([views.md §3.2](views.md#32-reduce)) are mostly
independent rediscoveries of this line, with one distinction worth testing: they
compose, and they compose across views rather than within one tool.

## Software cartography and code-as-terrain

- **Codemap / Software Cartography** (Kuhn, Loretan, Nierstrasz) -- spatial map
  with a stable coordinate system; concerns such as search, bugs and authors
  project onto it.
- **CodeCity** (Wettel, Lanza) -- classes as buildings, packages as districts,
  metrics as height and colour.
- **Software maps** (Bohnet, Döllner) and the **HPI** line (Limberger, Scheibel,
  Trapp, Döllner) -- treemap-based, multi-metric, evolution-aware maps; attribute
  layering; level of detail.

## Treemaps

- **Treemaps** (Shneiderman, 1991).
- **Squarified treemaps** (Bruls, Huijsen, van Wijk, 2000) -- implemented as
  `squarify:scales:into:`.

## Software visualization frameworks in Smalltalk

- **Moose** (Nierstrasz, Ducasse) -- model-driven analysis on the **FAMIX**
  meta-model; Pharo; language-agnostic. Broader and model-first, where this suite
  is live and image-first: Moose imports a model, SWA reads the running system.
- **Roassal** -- the Pharo visualization engine Moose renders through; binds
  size, colour and edges to a domain.
- **Glamorous Toolkit** (feenk, Gîrba) -- moldable development; live custom views
  per object. The nearest neighbour to the "views on a system" framing, and the
  clearest point of comparison: GT moulds a view per domain object, SWA composes
  a fixed set of views over one shared identity vocabulary.

## Runtime and memory analysis

The data was always reachable from the image; what was missing was aggregation
and comparison over it. See
[views.md §1](views.md#1-the-problem-is-distance-not-access).

- **Eclipse MAT** -- retained size, dominator trees, snapshot comparison. The
  reference implementation of ownership-based memory accounting, and the standard
  against which [todo.md](todo.md) item 18 should be judged.
- **Chrome DevTools heap profiler** -- heap snapshots, the comparison view,
  objects allocated between two snapshots, allocation sampling and the allocation
  timeline. Heap Diff and the Alloc Tracer are in-image analogues.
- **Squeak `SpaceTally`** -- instances and bytes per class, no object graph. What
  `SWASpaceTally` supersedes.

Neither retained size nor heap diffing is novel as a technique. The parts that
are plausibly distinctive: performing them *inside* the image being measured,
where the analyser is an object in the heap it walks; the generation-aware,
non-perturbing variants (move detection, identityHash fingerprints) built because
a collection destroys the phenomenon; and grouping surviving objects by **home
method**, which bridges object space back to code space and which batch analysers
do poorly for want of a live code model.

## Profiling and traces

- **MessageTally** -- Squeak's own sampling profiler; the one runtime instrument
  developers already had.
- **py-spy** (Frederickson) -- external sampling profiler reading another
  process's memory. The model for `st-spy`.
- **Flame graphs** (Gregg) -- aggregate stacks, x axis sorted rather than
  temporal.
- **Chrome trace event format / Perfetto** -- flame *charts*: one span per call on
  a real time axis, per-process lanes. The distinction between the two is
  documented in `SWATraceMorph` and in
  [landscape.md §3.1](landscape.md#31-execution-five-instruments-for-one-question).

## Instrumentation substrates

- **Wrappers to the Rescue** (Brant, Foote, Johnson, Roberts, ECOOP 1998) -- the
  direct ancestor of `SWAMethodWrapper`: method wrappers installed in the method
  dictionary, forwarding to the original.
- **`tallyFunc`** (Ingalls, Lively Kernel) -- the counting-wrapper pattern cited
  in the `SWACoverage` class comment.
- **Context-oriented programming** (Hirschfeld, Costanza, Nierstrasz, 2008) --
  layers activated dynamically per control flow. `SWACapturingLayer` is a
  COP-style layer scoped per process, used to suppress instrumentation
  re-entrance.
- **SUnit TestCoverage** -- the one-shot coverage wrapper `SWACoverage` builds on.

## Evolution and history

- **Evolution Matrix** (Lanza, Ducasse) (?) -- classes over versions as a grid.
- **Gource**, **code_swarm** -- repository history as animation; the temporal
  views share the question and not the form.
- **GitHub contribution calendar** -- the direct precedent for
  `SWACalendarMorph`.
- **Change distilling** (Fluri, Gall) (?) -- fine-grained change extraction from
  version pairs; `SWAGitHistory` obtains the same granularity from Monticello
  patch operations instead.

## Text-based analysis

- **Semantic clustering** (Kuhn, Ducasse, Gîrba) -- topics identified in source
  code by information retrieval; the precedent for the topic model, and by the
  same author as Codemap above.
- **Biterm Topic Model** (Yan, Guo, Lan, Cheng, WWW 2013) -- implemented as
  `SWABitermTopicModel`; chosen over LDA because method sources are short texts.
- **Shingling and Jaccard similarity** (Broder, 1997) -- the near-duplicate
  method behind `SWACodeSimilarity`.

## Positioning

Most individual measurements in the suite have established equivalents outside
Smalltalk, and most visual forms have established equivalents outside this
project. Three things are plausibly not standard, and all three are about
composition rather than measurement:

1. The measurements are **live and in-image**, so the analyser is subject to the
   conditions it measures. This is a cost, not a feature, except that it forces
   the non-perturbing techniques noted above.
2. Results **compose across views** through one identity vocabulary and a small
   algebra, so a reduction derived in one view can structure or decorate another.
3. Object-space results **resolve back to code**, via home method, which is what
   makes the heap views answerable in the same terms as the code views.

Whether any of this helps a human cope with agent-authored code remains the open
empirical question recorded in [motivation.md](motivation.md) and
[ideas.md](ideas.md) direction 6.
