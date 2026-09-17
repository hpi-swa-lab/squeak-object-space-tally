# Vision: the Suite as an XR Application

![](_navigation.html)

Why the tools exist at all is [motivation.md](motivation.md); research directions
for the dataset algebra are [ideas.md](ideas.md). This file is about one specific
move: running the views *inside* SqueakXR rather than only pointing them at it.

## 1. The inversion

SqueakXR is currently the **target**. Every figure in [stories.md](stories.md)
about Vector3 survivors, frame-boundary collections and scavenge rates is a
measurement of the XR framework taken from the desktop image.

The proposal is to also make it the **host**: the Code Map, the Space Tally and
the flame charts rendered as objects in an XR world, on the Quest. Software
architecture exploration becomes an XR application.

The relationship then closes into a loop. The tools measure SqueakXR; SqueakXR
renders the tools; the tools are measuring the thing that is drawing them.
Section 6 argues that this is both the main hazard and the most interesting
property of the arrangement.

## 2. Why a second example domain

SWAGame is the games domain. A visualization suite is not merely another demo,
because it loads almost disjoint parts of the framework:

| | SWAGame | SWA views |
|---|---|---|
| Geometry | voxel terrain, many meshes, per-frame updates | a handful of quads |
| Textures | few, large, mostly static | many, small, invalidated on interaction |
| Text | sparse labels | dense, small, the primary content |
| Interaction | grab, collide, move through | ray-point at small targets, select, mark |
| Frame cost | dominated by geometry and physics | dominated by texture upload and text |
| Failure mode | a dropped frame | an illegible label |

A second domain that stresses the opposite half of the framework will surface a
different class of bug. That is the engineering argument, and it holds
independently of whether the visualizations turn out to be useful in XR.

## 3. What already exists

The port is not starting from zero. `SRGCStats` is an SWA-family tool already
running as an `SRObject` in XR, and the machinery around it establishes two
distinct routes.

| Route | Mechanism | Cost | Precedent |
|---|---|---|---|
| **Morph panel** | `SRMorphPanel` hosts any Morph; `SRMorphTexture` renders it to a texture, with `SRDamageRecorder` supplying update rects | pays Morphic's cost, but only on damage | the general Morphic-in-XR path |
| **Surface adapter** | the drawing code targets an abstract surface; `GcStatsCanvasSurface` for Morphic, `GcStatsTextureSurface` for an `SRTextureSource` | zero per-frame allocation | `GcStatsPanel` / `SRGCStats` |

`SRGCStats` took the second route deliberately: it scrolls a one-pixel column
into a persistent buffer and pushes it with one `rlUpdateTexture`, with no Form
and no new objects per frame, because a tool that measures GC must not allocate.
`GcGraphMorph` repaints a Form every step and is the thing it was written to
avoid.

One caveat worth recording: `SRMorphTexture`, which the whole Morph-panel route
depends on, still has a placeholder class comment (`is xxxxxxxxx`, every instance
variable `xxxxx`). The class the plan leans on is the least documented one in the
path.

## 4. Why treemaps are the right first port

A treemap is unusually cheap to put in XR, for a reason specific to how
`SWATreemapMorph` already works: **it renders to a cached Form and re-renders
only when the layout or the colour changes.** Between interactions it is a static
image.

That inverts the cost argument that forced `SRGCStats` down the harder route. A
GC graph changes every frame, so a Form repaint per step was intolerable. A
treemap changes when the user selects, zooms, or switches a metric — a few times
a minute. The expensive Morph-to-texture upload happens on interaction, not per
frame, so the cheap generic route is adequate.

The Form is already there; the work is hosting it, not producing it.

## 5. Which route for which tool

The choice follows from what the tool measures, which is not obvious and is worth
stating as a rule:

- **Tools measuring code, structure or history** — Code Map, Class Diagram, Git
  Map, Change Map, the temporal views — may use the Morph panel route. Their
  subject is unaffected by the allocation their display causes.
- **Tools measuring memory, allocation or GC** — Space Tally, the heap-diff
  family, the allocation flamegraph, anything in `SWA-GCStats` — must use the
  surface route. Rendering them with Morphic Forms in the image they are
  measuring pollutes the measurement with the display.

The second case is the observer problem from [stories.md](stories.md) made
structural: the heap diff already reports a 1500–2300 object noise floor because
the render loop and the MCP server are running. Displaying a memory tool through
a per-frame Form repaint would add the display to its own subject.

## 6. What XR might actually buy

The weak version of this project is a floating flat panel, which is a worse
monitor. Three candidates for something better, stated so they can fail.

**Space as an incidental relation.** [views.md §3.1](views.md#31-relate) lists
three ways a person relates two results: automatic (shared key), deliberate
(marks), incidental (shared clock, shared layout, same window). XR adds a fourth
kind of incidental relation — *shared physical location*. A coverage map on one
wall and a space tally on another, both in view, related by where they are rather
than by a mechanism. Whether standing between two maps beats two windows is an
empirical question and not obviously a win.

**The third axis.** Treemaps carry size and colour. A third dimension carries a
third metric, which is what CodeCity does with building height
([related-work.md](related-work.md)). The open part is not the encoding, which is
solved, but whether *embodiment* adds anything over a rotatable 3D view on a
screen — parallax, physical scale, walking rather than orbiting.

**Magnitude at body scale.** A method allocating 4,000 objects a frame could be
rendered large enough to stand beside. Whether that conveys proportion better
than a large tile is exactly the kind of programming-experience question the
group is set up to ask.

## 7. Risks

**More room is not more contrast.** The central finding of
[views.md §3.2](views.md#32-reduce) is that legibility comes from subtraction,
and XR mainly offers more surface. An unlimited canvas invites the floodlight
mistake in a new form: showing everything because there is finally room to. The
nine reduction mechanisms matter more in XR, not less.

**Text density at headset resolution.** The primary content is small labels. Whether
a treemap label is legible on the Quest at a comfortable panel distance is
unknown and is a measurement, not an opinion — it belongs in
[benchmarks.md](benchmarks.md) as an experiment with a stated panel size and
distance, before any porting effort is justified by it.

**Interaction mapping.** The treemap idioms are click-select, click-again-zoom,
shift-mark, right-click menu and hover tooltip. XR input is ray, trigger and grab
(see the workspace note on trigger-and-grabbing). Click-again-to-zoom maps
cleanly; the modifier-based ones do not, and hover has no obvious equivalent when
the ray is the cursor. Marks may come off best: pointing at a thing and marking
it is more natural in XR than shift-clicking it.

**Chrome does not port.** `SWAPane` is a Morphic god object of buttons, flaps and
splitters ([smells.md §4.1](smells.md)). Porting it wholesale would be the wrong
move; the XR version wants a reduced chrome, which is a useful forcing function
for deciding what that chrome is actually for.

## 8. A staged path

1. **Measure legibility first.** A static treemap Form on an `SRMorphPanel`, at a
   realistic size and distance, read on the Quest. If labels are unreadable, the
   rest of this file is moot and the answer is a different visual encoding rather
   than a port.
2. **One treemap, read-only.** The Code Map on a panel, no interaction. Proves
   the Form-to-texture path at treemap sizes and gives the fast-texture path a
   third client, which the 2026-09-15 audit suggests it needs.
3. **Selection and zoom.** Ray-point plus trigger for select, trigger-again for
   zoom. The minimum interaction that makes a treemap a tool rather than a poster.
4. **Marks across panels.** `SWAMarkSet` is already a process-wide singleton that
   every view observes, so a mark made on one XR panel lights up on every other
   one for free. This is the cheapest demonstration of the shared-identity
   argument, and it is more striking in XR than on a desktop.
5. **A memory tool by the surface route.** Only after 1–4, and only following the
   rule in section 5.

## 9. What would make this fail

Worth writing down in advance, so the answer is not retrofitted:

- Labels are illegible at any comfortable panel size, and no encoding fixes it.
- Ray-pointing is too imprecise for tiles at treemap densities, making selection
  frustrating at exactly the leaf level where the data is.
- The texture upload cost at treemap resolution exceeds the frame budget, which
  would push even the code-side tools down the surface route and multiply the
  work.
- Nothing is gained over a desktop window, which is the honest default outcome
  and the one [motivation.md](motivation.md) already warns about for the suite as
  a whole: an open empirical question, not a claim.
