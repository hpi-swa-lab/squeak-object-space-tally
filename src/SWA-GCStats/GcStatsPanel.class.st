"
Shared GC-stats display model for both the desktop GcGraphMorph and the XR SRGCStats.

Holds the three improved graph models (SRGCFpsGraph / SRGCMemGraph / SRGCSurvivorGraph) and owns the layout + compositing logic. Rendering is done against a drawing-surface adapter (see GcStatsSurface subclasses) so the exact same layout/composite code drives either a Morphic Canvas or an SRTextureSource texture.

Layout (top to bottom): [fps label strip][fps graph][mem label strip][mem graph][surv label strip][surv graph].

Protocol a surface must answer:
  labelFont                        -- the font used for label strips
  labelStripHeight                 -- pixel height of a label strip
  fillLabelStripAt: y height: h    -- clear a label band
  drawForm: aForm at: aPoint       -- blit a graph form
  drawLabel: aString at: aPoint    -- draw label text

Use #graphs to iterate, #stepGraphs to advance them, #extent for total size, and #renderOn: aSurface to composite.
"
Class {
	#name : #GcStatsPanel,
	#superclass : #Object,
	#instVars : [
		'graph',
		'fullGraph',
		'survivorGraph',
		'changesGraph',
		'labelFont',
		'backingForm',
		'backingCanvas'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsPanel >> ensureBackingForm [
	"(Re)allocate the backing Form only when the composited size actually changes --
	i.e. on first use and on resize, never per frame. One Form + one FormCanvas are
	retained; steps mutate them in place."
	| ext |
	ext := self extent.
	(backingForm notNil and: [backingForm extent = ext]) ifTrue: [^ self].
	backingForm := Form extent: ext depth: 32.
	backingCanvas := backingForm getCanvas
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsPanel >> extent [
	"Composited pixel size for the panel's own font: three [label strip + graph] stacks,
	widest graph wins the width."
	| labelH |
	labelH := self labelStripHeight.
	^ (self graphs inject: 0 into: [:m :g | m max: g graph form width])
		@ (self graphs inject: 0 into: [:sum :g | sum + labelH + g graph form height])
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> extentFor: aSurface [
	"Total pixel size of the composited panel: three [label strip + graph] stacks,
	widest graph wins the width. Depends on the surface's label font."
	| w labelH |
	labelH := self labelStripHeightFor: aSurface.
	w := self graphs inject: 0 into: [:m :g | m max: g graph form width].
	^ w @ (self graphs inject: 0 into: [:sum :g | sum + labelH + g graph form height])
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:35'
}
GcStatsPanel >> fitWidth: totalWidth height: totalHeight labelStripHeight: labelH [
	"Resize the graph forms so the composited panel fills totalWidth @ totalHeight.
	Wider forms show more history (one bar per sample, scrolled left); taller forms
	show more vertical detail (values scale to form height). The three label strips
	take fixed vertical space; the remaining height is split by graphHeightWeights."
	| graphArea weights weightSum tops |
	graphArea := (totalHeight - (self graphs size * labelH)) max: self graphs size.
	weights := self graphHeightWeights.
	weightSum := weights inject: 0 into: [:s :w | s + w].
	tops := 0.
	self graphs with: weights do: [:g :w | | h |
		"Give the last graph the leftover pixels so rounding never overflows/underflows."
		h := (graphArea * w // weightSum) max: 1.
		tops := tops + h.
		g graph width: (totalWidth max: 2) height: h]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsPanel >> form [
	"The retained backing Form the panel composites into (mirror of the XR
	SRTextureSource's form). Allocated lazily / on resize by #ensureBackingForm."
	^ backingForm ifNil: [self ensureBackingForm. backingForm]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> fullGraph [
	^ fullGraph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> graph [
	^ graph
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:00'
}
GcStatsPanel >> graphHeightWeights [
	"Relative heights of the graphs (fps : mem : survivor : changes), same order as
	#graphs. The memory graph gets twice the height because it packs two lanes; the
	changes lane is a thin marker strip."
	^ #(50 100 50 35)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:00'
}
GcStatsPanel >> graphs [
	"Top-to-bottom order used for layout and compositing."
	^ { graph. fullGraph. survivorGraph. changesGraph }
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:11'
}
GcStatsPanel >> initialize [
	"Use the improved GC-stats graph models (developed on the XR side)."
	graph := SRGCFpsGraph new.
	fullGraph := SRGCMemGraph new.
	survivorGraph := SRGCSurvivorGraph new.
	changesGraph := SRGCChangesGraph new.
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> labelFont [
	^ labelFont ifNil: [labelFont := TextStyle defaultFont]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> labelFont: aFont [
	labelFont := aFont
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsPanel >> labelStripHeight [
	"Height of the clear label band above each graph, for the panel's own font."
	^ self labelFont height + 2
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> labelStripHeightFor: aSurface [
	"Height of the clear label band above each graph, for the surface's font."
	^ aSurface labelFont height + 2
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsPanel >> refresh [
	"Advance one frame and composite it into the backing Form. The caller then just
	blits self form (no re-issuing of draw ops)."
	self stepGraphs.
	self render
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsPanel >> render [
	"Composite the three graphs + labels into the retained backing Form, in place.
	This is the desktop analogue of the XR path compositing into its SRTextureSource:
	one retained surface, mutated each frame, no per-frame allocation of forms."
	| surface |
	self ensureBackingForm.
	surface := GcStatsCanvasSurface new
		canvas: backingCanvas origin: 0 @ 0 width: backingForm width font: self labelFont.
	self renderOn: surface
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> renderOn: aSurface [
	"Composite all three graphs and their labels onto the drawing surface, exactly the
	same layout for the desktop morph (Canvas surface) and the XR texture (texture
	surface). Each stack is [label strip][graph form]. The surface abstracts the three
	primitives the two backends implement differently."
	| labelH y |
	labelH := self labelStripHeightFor: aSurface.
	y := 0.
	self graphs do: [:g |
		aSurface fillLabelStripAt: y height: labelH.
		aSurface drawLabel: g labelString at: 2 @ (y + 1).
		y := y + labelH.
		aSurface drawForm: g graph form at: 0 @ y.
		y := y + g graph form height]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:35'
}
GcStatsPanel >> scaleForFactor: scale [
	"Resize each graph's FormGraph so its bars/lines are drawn at the given scale
	(1 for the morph's 1x screen path, N for the XR texture's supersampled path).
	Base sizes: fps 480x50, mem 480x100, survivor 480x50."
	self graphs with: self graphHeightWeights do: [:g :h |
		g graph width: 480 * scale height: h * scale]
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:58'
}
GcStatsPanel >> stepGraphs [
	"Advance one frame, measuring the frame delta from the wall clock. Used by the
	desktop morph, which steps once per Morphic cycle so the measured interval is the
	real frame time."
	self stepGraphsWithDelta: nil
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:00'
}
GcStatsPanel >> stepGraphsWithDelta: aDeltaMsOrNil [
	"Advance the three graph models one frame. aDeltaMsOrNil, when supplied, is the
	authoritative render-loop frame delta (XR passes SRFrame's deltaTime); when nil the
	fps graph measures wall-clock time between steps."
	graph updateTimeWith: aDeltaMsOrNil.
	graph updateGraph.
	fullGraph updateGraph.
	survivorGraph updateGraph.
	changesGraph updateGraph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsPanel >> survivorGraph [
	^ survivorGraph
]
