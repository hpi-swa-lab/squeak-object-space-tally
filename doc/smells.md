# SWA -- Smells, Duplications & Open Ends (As-Is Findings)

![](_navigation.html)

Legend: **[dup]** duplication · **[open]** unfinished / TODO-shaped · **[risk]**
correctness/robustness · **[naming]** clarity · **[design]** structural ·
**[dead]** likely-dead/legacy.

---

## 1. Duplication

### 1.1 `addDataset:` duplicated verbatim on view + Code Map **[dup]**
`SWAView>>addDataset:` and `SWACodeTreemapMorph>>addDataset:` are byte-identical
(mint modeSymbol per metric, register in `metricsByMode`). Same for
`datasetForDataMode:`, `metricForMode:`, `metricsByMode`, `datasets`,
`setDataMode:`, `intrinsicColorMode` pattern. The Code Map overrides exist only to
also handle the size/decoration axes in `selectDataset:` -- but the plain
`addDataset:`/`metricForMode:` copies add nothing and can drift. **Candidate:** keep
only the `SWAView` versions; let the Code Map override *just* `selectDataset:`.

### 1.2 Duplication scan implemented twice **[dup]**
`SWACodeTreemapMorph>>computeDuplicationScores` (live, in-morph) and
`SWADuplicationData>>buildFromMethodNodes:...` (offline) are the *same*
inverted-shingle Jaccard algorithm, stage for stage, with slightly different
progress plumbing. The comment on the latter even says "same EXACT algorithm... so
it can run offline." **Candidate:** one algorithm object; the morph consumes its
result like any other dataset (the offline path already produces exactly that).

### 1.3 Coverage/space-tally JSON string-escaping written 3+ ways **[dup]**
Four separate JSON emitters coexist: `Json render:` / `jsonWriteOn:` (used by
`SWAMarkSet`, `SWADuplicationData`, `SWATopicData`, `SWACoverageData`),
`SWASpaceTallyJsonWriter>>writeJsonString:` (delegates to `Json escapeForCharacter:`),
`SWASpaceTallyNode>>printJsonString:on:` (hand-rolled escape table),
`SWASpaceTallyClassSummary>>writeJsonString:on:` (delegates to `Json`). The hand-rolled
one in `SWASpaceTallyNode` is the odd one out and a latent escaping-bug source.
**Candidate:** one JSON-string helper; the streaming space-tally writer already has
a good one.

### 1.4 `openExplorerWindow` / `openExplorerSelecting:` duplicated (node vs group) **[dup]**
`SWASpaceTally>>openExplorerWindow`/`openExplorerSelecting:` and
`SWASpaceTallyNode>>openExplorerWindow`/`openExplorerSelecting:` are near-identical
(the node version exists so the treemap overlay, which holds a node not a group, can
open an explorer). The 7-column setup block is copy-pasted. **Candidate:** factor the
column config + path-building into one place.

### 1.5 Retention/parents Graphviz builders overlap **[dup]**
`SWASpaceTallyNode` has `parentsToRootsGraphMax:`, `retentionGraphMax:pathsPerRoot:`,
and `retentionAncestryMax:pathsPerRoot:` -- three upward-DAG builders with a lot of
shared BFS + DOT-emission scaffolding (and `kPerRoot` is "accepted for API
compatibility but unused"). **Candidate:** collapse to one parameterized builder;
drop the dead param.

### 1.6 Three `dotEscape:` / `htmlEscape:` variants **[dup]**
`SWACodeNode class>>dotEscape:`, `SWASpaceTallyNode class>>dotEscape:`, and
`SWACodeNode class>>htmlEscape:` each re-implement escaping. Minor, but they will
drift. **Candidate:** a shared Graphviz-escape utility (SWA-Graphviz already owns the
backend).

### 1.7 Coverage color ramp defined in two places **[dup]**
`SWADataset>>coverageScale`/`duplicationScale` and `SWAView>>coverageColorForWeight:`
/`heatColorForWeight:` encode overlapping green/heat ramps; the Code Map's
`dupHeatColorForScore:` is a third copy of the duplication ramp. Confirm which is
canonical.

### 1.8 `zoomOut`/`refreshChrome`/`selectedSourceString` re-declared per view **[dup]**
The flamegraph, class diagram, and each treemap re-implement small chrome hooks
(`refreshChrome` = `navPanel ifNotNil: [:p | p refresh]` appears ~4x;
`selectedSourceString` guard-and-delegate appears ~4x). Cheap to pull up to `SWAView`.

---

## 2. Naming / clarity

### 2.1 `SWAView` vs `SWAPane` **[naming]**
Already flagged in `gallery.md` ("consider whether `SWAView` wants a clearer name
alongside `SWAPane`"). `SWAView` is the *content morph*; `SWAPane` is the *window
chrome*. The names invite confusion (a "pane" usually *is* the content). Worth
settling before more subclasses appear.

### 2.2 "MessageTally" package holds a **Sampling** tally **[naming]**
`SWA-MessageTally` contains `SWASamplingTally` (external statistical sampler) *and*
`SWATallyWrapper` (in-image deterministic invocation counter) *and* `SWAStructure`
(a generic dataset-structure class unrelated to tallies). Three different concerns
under a tally banner. The docs already carefully disambiguate "three flavours of
message tally" -- the package name doesn't. **Candidate:** `SWAStructure` belongs in
SWA-Base; the sampling vs deterministic split could be clearer.

### 2.3 `SWASampleTallyData` vs `SWASamplingTally` vs `SWASamplingTallyNode` **[naming]**
Three very close names for: the flattened per-method self-count dataset, the
recorder/driver, and the call-tree node. Easy to mis-reach.

### 2.4 `coverageTally` / `updateTallyButton` / `tallyButton` reference a removed button **[dead]**
`SWAPane>>coverageTally` is a "BACKWARD COMPAT" shim for a Tally header button that
no longer exists; `updateTallyButton` reads a `tallyButton` ivar that is never set
(the ivar isn't even in the class def -- it would DNU if reached). Dead-ish.
**Candidate:** delete both once confirmed no old panels are deserialized.

---

## 3. Dead / legacy code

### 3.1 `GraphvizPlainParser` superseded by `GraphvizJsonParser` **[dead]**
`GraphvizMorph>>render` uses `-Tjson` + `GraphvizJsonParser` (records + field rects).
`GraphvizPlainParser` + `parsePlain:withForm:` remain fully implemented but appear
unused by the live path (only the JSON parser is wired in `render`). `SWA-Tests`
still tests the plain parser. **Candidate:** confirm unused, then retire or mark
test-only.

### 3.2 Legacy coverage overlay path parallel to datasets **[design]/[dead?]**
The Code Map still carries the *pre-datasets* single-ivar coverage machinery
(`showCoverage:`, `highlightWeights:`, `coverageData`/`coverageKind`, the
`#coverage`/`#tally` legacy colorModes, `enterCoverageColorMode`,
`enterTallyColorMode`) *alongside* the coverage `SWADataset` path. Comments say
datasets are "additive... will absorb it piece-meal later." That absorption hasn't
happened; both paths are live and must be kept consistent (they interact in
`intrinsicColorForNode:`). This is the single biggest structural debt.

### 3.3 `SWACoverage` bisection harness **[dead?]**
`bisectWrapPackages:toLog:` / `spawnBisectForPackages:tag:` were built to hunt the
VM-crash-on-wrap bug. Valuable history, but debugging scaffolding shipping in the
tool. Keep, but flag as diagnostics-only.

### 3.4 `SWACoverageWrapper` `Recording` class-var + `whileRecordingDo:` **[dead]**
After the move to `SWACapturingLayer`, `captureIn:` no longer consults `Recording`
(the comment says "we no longer need a separate Recording flag"), yet the class-var,
`whileRecordingDo:`, and `resetRecordingState`'s `Recording := false` remain.
Likely vestigial.

### 3.5 `SWACoverage class>>inMetaMode`/`inMetaMode:` **[dead]**
`InMetaMode` class-var + accessors describe the *old* reentrancy guard superseded by
`SWACapturingLayer`. Search of the hot path shows the layer is what actually guards
now. Probably dead.

### 3.6 Exclusion lists deliberately emptied **[open]**
`excludedPackagePatterns`, `excludedTestCategoryPatterns` return `#()` "by request";
comments say "restore from version history before running broadly." So whole-image
coverage is currently *unguarded except* for `substratePackagePatterns`. Intentional,
but a foot-gun worth a louder note.

---

## 4. Design / structural

### 4.1 `SWAPane` is a god object **[design]**
43 ivars, ~130 methods spanning coverage, tally lifecycle, datasets, masks,
structure morphing, marks flap, source flap, class-diagram spawning, JSON loading,
generation. It's the chrome *and* the controller *and* the dataset orchestrator. This
is the natural place to split (e.g. a dataset/generation controller vs the pure flap
chrome).

### 4.2 `SWAView` is nearly as heavy **[design]**
23 ivars carrying datasets + cross-ref + coverage-provenance + search + marks. The
coverage-provenance machinery in particular (testKeys/testFilterKeys/coveringTestFilter
+ the blue-test/green-cover ramps) is Code-Map-specific but lives in the shared
superclass, so the flamegraph and space tally inherit dead coverage state.
**Candidate:** push coverage-provenance down into a mixin or into `SWACodeTreemapMorph`.

### 4.3 Heavy `respondsTo:` / duck-typing between pane and view **[design]**
`SWAPane` constantly does `(view respondsTo: #selectDataset:)`,
`(view respondsTo: #leafKind:)`, `(view respondsTo: #decorationMetric)`, etc. to
capability-gate its header. This is flexible but fragile and untyped -- the "contract"
between pane and view is implicit and scattered. **Candidate:** an explicit
capability protocol (a `viewCapabilities` set, or default no-op methods on `SWAView`).

### 4.4 `SWANode` marks/nodeKind bleed into a pure tree contract **[design]**
`SWANode` gained `markKey`, `nodeKind`, and derives a kind Symbol from the class name.
Reasonable, but the "pure tree" abstraction now also knows about the marks feature.
Fine as-is; note the coupling.

### 4.5 Datasets know their own view classes **[design]**
`SWADataset>>maskStructures`/`structures` hard-references
`SWASamplingTallyFlamegraphMorph`, `SWASamplingTallyTreemapMorph`,
`SWASpaceTallyTreemapMorph`. So the *data* layer depends on specific *view* classes,
inverting the intended layering (views should depend on data, not vice versa).
**Candidate:** structures should carry a view *policy*/symbol the pane resolves, not a
concrete morph class.

### 4.6 Two parallel "size resolves up the parent chain" mechanisms **[design]**
`SWACodeNode` resolves `weightMetric`, `sizeMetric`, `coverageData`,
`coverageWeightMode`, and `topicData` up the parent chain independently, each with its
own `ifNotNil: [^ ...] parent ...` boilerplate and its own rollup cache + flush. Five
near-identical inheritance mechanisms. **Candidate:** one "inherited attribute" helper.

---

## 5. Correctness / robustness watch-list

### 5.1 Instrumentation is a minefield (well-guarded, but fragile) **[risk]**
The wrapper family works *only* because of a long list of hard-won guards
(`SWACapturingLayer`, `realMethod` peeling, `uninstallAllStrayWrappers`,
`doesNotUnderstand:` never wrapped, infrastructure classes excluded, per-process
layer). Every method comment reads like an incident report. This is genuinely
dangerous code touching the live UI; any change needs the same paranoia. Not a
"smell" so much as a "here be dragons" marker for anyone editing SWA-Coverage /
SWATallyWrapper / SWACapturingLayer.

### 5.2 `SWAPane>>delete` must tear down tallies -- easy to break **[risk]**
Closing a pane with a live tally *must* uninstall wrappers, or orphaned wrappers
linger and corrupt unrelated tools (the recurring "Git-tool DNU"). This invariant is
currently upheld in `delete` -> `abandonInvocationTally`, but it's a single point of
failure with no test. **Candidate:** an image-level safety sweep on some heartbeat, or
a test.

### 5.3 Topic model default LLM endpoint/model hard-coded **[risk]/[open]**
`SWATopicData class>>defaultLlmEndpoint` -> `http://172.16.64.127:11434/api/generate`,
`defaultLlmModel` -> `'qwen3.6:latest'`. A hard-coded LAN IP + a model tag that looks
like a typo (`qwen3.6`?). Environment-specific config baked into a class method.

### 5.4 st-spy binary path + sudo assumption **[risk]/[open]**
`SWASamplingTally class>>stSpyBinary` -> `'./st-spy'`, run via `sudo -n` relying on a
NOPASSWD rule and the VM's cwd being the repo root. Documented, but a hard
environment coupling with silent-empty-log failure modes (much of the class is
failure-diagnosis code for exactly this).

### 5.5 `SWAChangeParser` re-opens the same file many times **[risk-perf]**
`scanStartForTailBytes:`, `chunkAlignedStartBefore:`, `commonPrefixLengthWith:`,
`scanBoundariesFrom:to:`, `scanRecordsFrom:to:` each `FileStream readOnlyFileNamed:`
independently (some just to read `size`). On a large `.changes` file that's a lot of
opens. Functional, minor.

### 5.6 `mustNotInstrument:` / substrate guard is the only wall on `'*'` **[risk]**
With the exclusion lists emptied (3.6), a whole-image tally/coverage run rests
entirely on `substratePackagePatterns` + `infrastructureClasses` + the
`doesNotUnderstand:` special-case. If a substrate class slips the glob, the VM goes
down. High-stakes single guard.

---

## 6. Open ends / unfinished

### 6.1 `SWAMessageTally.md` is a stub **[open]**
Doc explicitly `STATUS: STUB`. The tool is mature; the write-up isn't.

### 6.2 Deterministic ("full") message tally not built **[open]**
`SWAMessageTally.md`'s table lists a "Full / deterministic" flavour as "-- (future)".
`SWATallyWrapper` + the call-tree capture are effectively *most* of it (exact
invocation counts + a flamegraph tree), but it's surfaced only as a Code-Map dataset,
not as a standalone tool/view with its own opener parallel to the sampling tally.

### 6.3 Mask algebra is `#minus` only **[open]**
`SWAMaskSource>>recompute` errors on any operator but `#minus`. Intersection / union /
symmetric-difference are natural next steps the structure already anticipates
("operator" is stored) but doesn't implement.

### 6.4 Class-diagram containment mode removed, nothing replaced it **[open]**
`gallery.md` notes the containment graph mode was removed as "superseded by the
treemap Code Map." Fine, but the diagram is now inheritance-only; a package-level
*collaboration/reference* diagram is an obvious gap (and `SWACodeInstVarNode` was
added "so instance variables can... later carry EDGES to other nodes -- composition/
type information... the way method/class nodes already cross-link" -- an explicitly
stated but unbuilt feature).

### 6.5 `SWACodeInstVarNode` edges are stubbed **[open]**
Its `buildChildren` comment: "edges to type/composition targets are a separate, future
overlay, not tree children." The node exists for marking today; the type/composition
cross-linking it was designed for is not built.

### 6.6 Sim space tally: `instVarNamesOfClassOop:` returns nil **[open]**
`SWASimSpaceTally>>instVarNamesOfClassOop:` -- "possible but not yet implemented;
returning nil makes slot labels fall back to '[N]'." So simulated-image walks show
`[3]` instead of ivar names. Known gap.

### 6.7 `SWASpaceTally` deadline/timeout mentioned in docs but removed in code **[open]**
`SWASpaceTally.md` and the class comment still reference `deadlineMs` / `#timeout`,
but the closed-universe rewrite removed wall-clock deadlines (only `maxVisits`
remains, "testing only"). Doc drift.

### 6.8 `SWAStructure` only ever built for tallies/space-tally **[open]**
The generic structure/projection mechanism is only exercised by call-tally and
space-tally datasets. Coverage/duplication/topic datasets are decorate-only. The
projection idea is more general than its current use.

---

## 7. Documentation drift (the existing `doc/*.md`)

- `packages.md` says **14 packages / 64 classes / 1591 methods**; the earlier live
  read counted ~**60 classes** across the SWA categories -- numbers are close but not
  pinned (and the file itself warns "if they drift, re-run the snippet"). The class
  hierarchy diagram omits `SWACodeInstVarNode`, `SWACodeMarkSetRootNode`,
  `SWAMaskSource`, `SWAStructure`, and the whole marks/instrumentation family.
- `index.md` / `gallery.md` / per-tool docs predate the **Marks**, **Mask (B\A)**,
  **Generate** (async on-the-fly datasets), **topic model**, and **live
  class-diagram-of-marks** features -- none are documented.
- `SWASpaceTally.md` "Performance" and "deadline" sections describe a pre-rewrite
  walker (see 6.7).
- The per-tool docs are user-facing/marketing in tone; there was no architecture /
  API / smells layer until now (this pass).

---

## 8. Quick wins vs deeper work (my rough split -- to discuss)

**Low-risk quick wins:** 1.1, 1.4, 1.6, 1.8 (pull-up dedup), 2.4 / 3.4 / 3.5 (delete
vestigial), 6.7 / 7 (doc fixes), 5.3 / 5.4 (extract config to a settings object).

**Worth a design conversation first:** 3.2 (retire the legacy coverage overlay in
favour of datasets -- the big one), 4.1 / 4.2 (split the god objects), 4.3 (explicit
pane<->view capability protocol), 4.5 (invert the dataset->view class dependency),
2.1 / 2.2 (naming/package reshuffle).

**Feature open-ends to prioritize:** 6.2 (deterministic tally as a first-class tool),
6.3 (richer mask algebra), 6.4 / 6.5 (composition/type diagram via ivar edges).
