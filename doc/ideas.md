# SWA -- Ideas & Research Direction

![](_navigation.html)


## An Algebra 

Static maps under-serve this. What the agent-authorship setting demands is
**difference and composition over time and over concerns**:

- *What did this agent run just change?* -> **diff / mask**: subtract the pre-run
  dataset from the post-run one; colour the survivors by churn, coverage, or bytes.
- *Is the new code tested, or did the agent skip the tests it claimed to write?* ->
  **compose**: project a coverage dataset onto the change map; mask the changed set by
  the covered set to reveal changed-but-uncovered.
- *Did it touch the parts I care about?* -> **project** marks / a hand-picked subset
  onto whatever the agent produced.
- *Did it quietly duplicate existing logic instead of reusing it?* -> **project** a
  duplication dataset onto the change map.

Each of these is a *set/overlay operation* on `crossRefKey`-keyed datasets, not a new
picture. So the algebra (`SWAMaskSource`, `SWAPeerViewSource`, `SWAStructure`; see
[architecture.md §6](architecture.md)) is the substrate that turns a gallery of maps
into a way of *interrogating a change*. That is where we think there's something worth
studying -- and it happens to be interesting for us specifically as **Software
Architecture / Programming Experience / Explorative & Live Programming** researchers,
because it is a live, in-image, composable analysis loop rather than a batch report.

## Future Work 

1. **Agent-run diff as a first-class view.** Snapshot datasets before/after an agent
   turn; the default view is the *difference*, algebra-composed, not the whole map.
   ("What just happened?" as the home screen.)
2. **Close the mask algebra.** `SWAMaskSource` is `B \ A` only; union / intersection /
   symmetric-difference are the natural operators for the questions above
   ([smells.md §6.3](smells.md)). Intersection = "changed *and* uncovered"; xor =
   "diverged".
3. **Trust overlays.** Compose coverage x change x duplication into a single
   "review-risk" tint: changed, uncovered, and near-duplicate lights up hottest.
4. **Provenance as a dataset.** If agent authorship can be attributed per method
   (which agent, which turn, which prompt), that becomes just another `crossRefKey`
   dataset to project, mask, and diff like any other -- "colour the map by *who/what*
   wrote it."
5. **Live, not batch.** Because analysis runs *in the image the agent is editing*, the
   loop can be immediate: agent edits -> re-walk -> the diff view updates. An
   explorative/live-programming take on code review.
6. **Legibility as the eval question.** The open empirical question is whether *any* of
   this actually helps a human cope with agent-speed code. That is a
   programming-experience study waiting to be designed, not a claim we can make yet.
