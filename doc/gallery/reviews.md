# Reviews (sign-offs)

![](_navigation.html)

[Gallery index](index.md) · **shared aspect** of the four code views

> Which of these changes have I actually read?

A sign-off says *"I have read this member as it reads now"*. Sign-offs live in
their own mark set, `SWAMarkSet reviewed`, next to the ordinary
[marks](marks.md), and every code view reads and writes the same set.

Journal: [2026-10-23b](../../../journal/2026-10-23b-the-code-map-learns-history-and-an-idea-for-xr.md)
section 7.

## The key follows the code, not the range

A review key is the **member plus 12 hex digits of the SHA-1 of the text reviewed**
-- the method source, the class definition in Monticello form, or `(removed)` plus
the text that went. For example `SRBlinkOverlay>>step: @34342...`.

So a sign-off holds wherever the member reads the same -- in any range, on any
branch, in the plain image -- and **lapses when the member changes**. Git and
image sources hash the same. Loading a range reports *"n of m changes already
reviewed"*.

## Signing off

| Where | How |
|---|---|
| any code view | **r** toggles the selection's sign-off (the diagram takes keyboard focus on click) |
| Browser | **r** signs off what the code pane shows, or everything under it when it did not change itself; **R** everything under the selection; both also in the list menu |
| Linear | the header row menu |
| Marks flap | the **Reviewed** list, with its own **Load**; comments on a reviewed row go to the reviewed set |

Each sign-off records `reviewedAt`, `reviewScope` (the range label) and the
**last change** of the member: `SWAGitHistory>>lastChangeOfMember:inFile:from:`
walks first parents back from the To end, skipping every commit whose class-file
blob is unchanged (~0.3 s for `SRObject>>addChild:`). It runs in the background and
shows in the selection's info line (*"last change a82eb22 21 October 2026 ... Jens
Lincke: tools and axis"*). Following first parents attributes a change that came
from another branch to the merge that brought it in.

## How each view shows it

| View | Signed off looks like |
|---|---|
| Code Map | a thin **sky-blue inner frame** (`drawTileFrame:in:on:`), inside the yellow mark frame, so a tile can show both and keep its change colour |
| Class Diagram | a **review marker** dot on the record row, clickable |
| Browser, Linear | the item **fades and turns italic** |

The frame replaced a blue fill, which clashed with the blue of tests in the coverage
colours and hid the change kind.

![Changes only, zoomed into SRAvatar: four teleport methods signed off (blue frames), openMenuForHand: selected with its diff below](../media/source-diff-codemap.png)

<!-- SCREENSHOT source-diff-codemap.png -- swap in empty sets first, so Jens' sign-offs
are neither read nor changed (the same trick as SWAMarksPanelTest):
savedR := SWAMarkSet classPool at: #Reviewed.
[SWAMarkSet classPool at: #Reviewed put: SWAMarkSet new.
 ...range, rangeView: #changes, zoomInto: SRAvatar...
 #('SRAvatar>>teleportTo:' 'SRAvatar>>commitTeleport' 'SRAvatar>>aimTeleportFrom:' 'SRAvatar>>cancelTeleportAim')
   do: [:k | view toggleReviewed: (view keyIndex at: k)].
 view selectedNode: (view keyIndex at: 'SRAvatar>>openMenuForHand:'). pane openSource.
 ...shoot...] ensure: [SWAMarkSet classPool at: #Reviewed put: savedR. SWAMarkSet default notifyPanes].
-->

## Known gaps

- Editing a reviewed method orphans its sign-off **and its comment** silently: the
  key is still in the set, it never matches again. See *CodeTalk* in
  [ideas.md](../ideas.md) for comments that survive this.
- There is no "next change not yet signed off" step, so a range cannot be reviewed
  from the keyboard alone.
- The reviewed set persists in the image, and on disk only when saved by hand.
