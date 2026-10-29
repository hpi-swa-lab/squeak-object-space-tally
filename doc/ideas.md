# Ideas 
![](_navigation.html)


## An Algebra 

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

## Directions

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

## Detachable panes, toward VR

The one-big-window layout of `SWAPane` works well on the desktop, but sometimes small
windows are better, e.g. a source view placed next to a browser. Redesign `SWAPane` so
that each part can be **torn out into a window of its own and docked back** into the
single-pane layout:

- the main view (treemap / class view / flamegraph -- the `SWAView`),
- the **Marks** flap (list, comment editor, provenance),
- the **Source** row (Details box, Shout source pane, covering tests / duplicates),
- the **Data** source / dataset controls.

Docked, it looks and behaves as it does today. Detached, each part is a normal window
that still talks to the same session: selecting in the treemap updates the detached
source window, marking in the detached Marks window paints the treemap, and so on.
Dropping a window back onto its slot (or a "dock" menu item) restores the layout.

**Why: VR.** The real goal is to bring the tool into SqueakXR. One ultra-wide window is
awkward to handle in VR; several smaller panels can be placed around the user, grabbed,
and moved independently. Once the parts are separate, a part can also be **replaced by
real 3D content** -- e.g. a 3D rendering of the treemap (height = a metric, colour = a
dataset) -- while Marks, Source, Details and Data stay ordinary Morphic panels and keep
working unchanged.

What this asks of the design:

- **Split the controller from the chrome.** Today `SWAPane` is chrome, controller and
  dataset orchestrator in one ([smells.md §4.1](smells.md)). Detaching needs a
  window-independent session object (selection, marks, datasets, live tallies) that the
  panes observe; the docked layout becomes just one arrangement of those panes.
- **An explicit view contract.** The panes must talk to the view through a protocol, not
  `respondsTo:` probing ([smells.md §4.3](smells.md)), so that a 3D treemap can stand in
  for `SWATreemapMorph` without the other panes noticing.
- **Lifecycle belongs to the session, not a window.** Closing a detached Source window
  must not tear down a running tally; closing the *last* window of a session must
  ([smells.md §5.2](smells.md)).
- **One session, one peer.** `SWAPane openPanels` / the Data menu should list sessions,
  not every detached window, so peer cross-referencing does not see duplicates.

## CodeTalk: comments on code, in the map

Reviving an idea from our group: annotate a piece of source code, and keep the
annotation with the code. GitHub review comments do something similar. The goal here
is to **talk about code pieces in bulk**, walking the Code Map or Class Diagram and
leaving comments on nodes (package, class, method) or on a section of a method.
That covers commenting for Jens's own use, for review, and for handing work to an agent.

**Today (2026-10-23).** Comments exist, but only as a property of a mark:

- `SWAMarkSet` (`Default` working set, `Reviewed` sign-offs) keeps `keys`,
  `comments` (key -> String), `provenance` (key -> String->String dict).
- `commentAt:put:` ignores unmarked keys, and `remove:` drops the comment with the mark.
  Un-reviewing a method throws its comment away.
- Review keys are `member @<sha1-12 of the text>` (`SWAView>>reviewKeyFor:`). Editing
  the method orphans its comment silently: still in the set, never shown again.
- Comments are visible and editable only in the left Marks panel (`SWAPane>>acceptComment:`).
  Neither the map nor the diagram shows them.
- They persist in the image and in a hand-saved `swa-reviewed.json`, not with the source.

**Comments as a third kind of mark, separate from marking and reviewing:**

- **Own object, own lifetime.** Anchor = member key + text hash at the time + optional
  range inside the method + commit (in history mode). Plus body, author, time, status
  (open / resolved), maybe replies.
- **Anchor sections by quote, not offset** (Web Annotation style: exact text plus some
  prefix/suffix). On display: hash matches -> exact; quote found -> moved; quote gone ->
  shown as *outdated*, the GitHub way, never silently dropped.
- **Press `C` on a selected node** -> a small editor appears *near the node* to add,
  edit or delete the comment. Explicitly **not a toggle** like the review button: typed
  text must not be lost by an accidental second press. Delete is its own action.
- **Visible where you look.** Class Diagram: a comment glyph (with count) next to the
  review dot, reusing `reviewBadgeRectFor:` / `GraphvizMorph>>markers:`. Code Map: a
  badge per tile, aggregated up the tree like git state (`computeGitStateOf:`). Source
  pane: commented ranges get a background colour; "comment selection" makes a range
  anchor. Left pane: a Talk list, `showMarkKey:` to jump.
- **Persisted with the code.** Candidates: a sidecar per class file (`classFilePathFor:`
  already maps members to files), one `.codetalk/` JSON, or `git notes` under
  `refs/notes/codetalk` (attaches to commits without touching the source; fits history
  mode).
- **Agent in the loop.** Comments are data reachable over MCP: an agent reads the open
  ones, replies in the thread (author: BlindGoldi), the replies show up as badges.
  Then the bulk walk through the map *is* the conversation, with no copying through
  the clipboard (`clipboardStringForKeys:` is today's poor version of this).

**Later, optional: semantic / voice.** The image can optionally carry LLM text support
and a voice model; the pieces exist, the time does not yet.

- Dictation into the comment editor instead of typing.
- Inline chat about the code under the node: ask about a method or section right in
  the popup, answer appears there, can be kept as a reply in the comment thread.
- With voice: walk the diagram and talk, in desktop or XR.

Intended to be handed to an OpenCode session once `SWAPane` work settles.
