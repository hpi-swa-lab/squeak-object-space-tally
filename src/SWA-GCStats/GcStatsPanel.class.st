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
		'youngGraph',
		'oldZoomGraph',
		'labelFont',
		'backingForm',
		'backingCanvas',
		'enabledGraphs',
		'enabledWeights',
		'surface',
		'labelPoint',
		'formPoint'
	],
	#classVars : [
		'ShowChangesLane',
		'ShowFpsLane',
		'ShowOldFullLane',
		'ShowOldZoomLane',
		'ShowSurvivorLane',
		'ShowYoungLane'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:02'
}
GcStatsPanel class >> lanePrefsDo: aBlock [
	"Evaluate aBlock with (menuLabel, getterSelector, setterSelector) for each lane
	preference, so the XR and Morphic menus build identical toggles from one place."
	aBlock value: 'FPS lane' value: #showFpsLane value: #showFpsLane:.
	aBlock value: 'Young lane' value: #showYoungLane value: #showYoungLane:.
	aBlock value: 'Old zoomed-in lane' value: #showOldZoomLane value: #showOldZoomLane:.
	aBlock value: 'Old full lane' value: #showOldFullLane value: #showOldFullLane:.
	aBlock value: 'Survivor lane' value: #showSurvivorLane value: #showSurvivorLane:.
	aBlock value: 'Changes lane' value: #showChangesLane value: #showChangesLane:
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:55'
}
GcStatsPanel class >> refreshAllPanels [
	"A lane preference changed. Re-fit every live panel to the new set of enabled lanes:
	 - XR (SRGCStats): weights are pixel heights, so re-scale + rebuild the texture;
	 - Morphic (GcGraphMorph): re-fit the graph forms to the current extent + rebuild the
	   backing Form.
	Guarded so this is a no-op if the XR/Morphic classes are absent."
	self allInstances do: [:p | p invalidateLanes].
	Smalltalk at: #SRGCStats ifPresent: [:cls |
		cls allInstances do: [:s | s reconfigure]].
	Smalltalk at: #GcGraphMorph ifPresent: [:cls |
		cls allInstances do: [:m |
			m extent: m extent.
			m changed]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:30'
}
GcStatsPanel class >> showChangesLane [
	<preference: 'GC Stats: changes lane'
		category: 'SqueakXR'
		description: 'Show the thin change-marker lane in the GC Stats panel (XR and Morphic)'
		type: #Boolean>
	^ ShowChangesLane ifNil: [ShowChangesLane := true]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:30'
}
GcStatsPanel class >> showChangesLane: aBoolean [
	ShowChangesLane := aBoolean.
	self refreshAllPanels
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:30'
}
GcStatsPanel class >> showFpsLane [
	<preference: 'GC Stats: FPS lane'
		category: 'SqueakXR'
		description: 'Show the frames-per-second lane in the GC Stats panel (XR and Morphic)'
		type: #Boolean>
	^ ShowFpsLane ifNil: [ShowFpsLane := true]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:30'
}
GcStatsPanel class >> showFpsLane: aBoolean [
	ShowFpsLane := aBoolean.
	self refreshAllPanels
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:02'
}
GcStatsPanel class >> showOldFullLane [
	<preference: 'GC Stats: old full lane'
		category: 'SqueakXR'
		description: 'Show the zoomed-out (full) old-space lane in the GC Stats panel'
		type: #Boolean>
	^ ShowOldFullLane ifNil: [ShowOldFullLane := true]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:02'
}
GcStatsPanel class >> showOldFullLane: aBoolean [
	ShowOldFullLane := aBoolean.
	self refreshAllPanels
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:01'
}
GcStatsPanel class >> showOldZoomLane [
	<preference: 'GC Stats: old zoomed-in lane'
		category: 'SqueakXR'
		description: 'Show the zoomed-in old-space lane (young resolution) in the GC Stats panel'
		type: #Boolean>
	^ ShowOldZoomLane ifNil: [ShowOldZoomLane := true]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:02'
}
GcStatsPanel class >> showOldZoomLane: aBoolean [
	ShowOldZoomLane := aBoolean.
	self refreshAllPanels
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:30'
}
GcStatsPanel class >> showSurvivorLane [
	<preference: 'GC Stats: survivor lane'
		category: 'SqueakXR'
		description: 'Show the survivor/tenure lane in the GC Stats panel (XR and Morphic)'
		type: #Boolean>
	^ ShowSurvivorLane ifNil: [ShowSurvivorLane := true]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:30'
}
GcStatsPanel class >> showSurvivorLane: aBoolean [
	ShowSurvivorLane := aBoolean.
	self refreshAllPanels
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:01'
}
GcStatsPanel class >> showYoungLane [
	<preference: 'GC Stats: young lane'
		category: 'SqueakXR'
		description: 'Show the young-space (scavenge sawtooth) lane in the GC Stats panel'
		type: #Boolean>
	^ ShowYoungLane ifNil: [ShowYoungLane := true]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:01'
}
GcStatsPanel class >> showYoungLane: aBoolean [
	ShowYoungLane := aBoolean.
	self refreshAllPanels
]

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
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:55'
}
GcStatsPanel >> graphHeightWeights [
	"Heights of the ENABLED lanes only, in the same order as #graphs, from #laneSpecs. On
	the XR path these double as pixel heights (see #scaleForFactor:). The mem graph gets the
	dominant share; the changes lane is a thin marker strip."
	enabledWeights ifNil: [self rebuildLanes].
	^ enabledWeights
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:55'
}
GcStatsPanel >> graphs [
	"The ENABLED lanes only, top-to-bottom. Answers a CACHED array (rebuilt lazily from
	#laneSpecs on first use / after #invalidateLanes) so the per-frame render path allocates
	no collection. At least one lane is always kept so the panel never collapses to nothing."
	enabledGraphs ifNil: [self rebuildLanes].
	^ enabledGraphs
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:01'
}
GcStatsPanel >> initialize [
	"The GC-stats graph models. The old memory lane is now split into three toggleable
	lanes: young (youngGraph), zoomed-in old (oldZoomGraph), zoomed-out old (fullGraph)."
	graph := SRGCFpsGraph new.
	youngGraph := SRGCYoungGraph new.
	oldZoomGraph := SRGCOldZoomGraph new.
	fullGraph := SRGCMemGraph new.
	survivorGraph := SRGCSurvivorGraph new.
	changesGraph := SRGCChangesGraph new.
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:55'
}
GcStatsPanel >> invalidateLanes [
	"Drop the cached lane arrays so they are rebuilt lazily on next access. Sent when a lane
	preference changes."
	enabledGraphs := nil.
	enabledWeights := nil
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:01'
}
GcStatsPanel >> laneSpecs [
	"The single source of truth for the lanes, top-to-bottom: each is
	{ graph model. relative/pixel height. enabled-boolean }. #graphs and
	#graphHeightWeights both filter from this, so they can never fall out of sync.
	Enabled state comes from the class-side lane preferences."
	^ {
		{ graph.          50.  self class showFpsLane }.
		{ youngGraph.     50.  self class showYoungLane }.
		{ oldZoomGraph.   80.  self class showOldZoomLane }.
		{ fullGraph.      200. self class showOldFullLane }.
		{ survivorGraph.  50.  self class showSurvivorLane }.
		{ changesGraph.   35.  self class showChangesLane } }
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:55'
}
GcStatsPanel >> rebuildLanes [
	"Recompute the cached enabled-graph / enabled-weight arrays from #laneSpecs. Called
	once at init and whenever a lane preference changes (via #invalidateLanes), NEVER per
	frame -- the per-frame #graphs / #graphHeightWeights just answer these cached arrays so
	the render path allocates no collections. An all-disabled panel keeps one fallback lane."
	| specs enabled |
	specs := self laneSpecs.
	enabled := specs select: [:spec | spec third].
	enabled isEmpty ifTrue: [
		enabledGraphs := { fullGraph }.
		enabledWeights := #(300).
		^ self].
	enabledGraphs := enabled collect: [:spec | spec first].
	enabledWeights := (enabled collect: [:spec | spec second]) asArray
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
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:55'
}
GcStatsPanel >> render [
	"Composite the three graphs + labels into the retained backing Form, in place.
	This is the desktop analogue of the XR path compositing into its SRTextureSource:
	one retained surface, mutated each frame, no per-frame allocation of forms."
	self ensureBackingForm.
	surface ifNil: [surface := GcStatsCanvasSurface new].
	surface
		canvas: backingCanvas origin: 0 @ 0 width: backingForm width font: self labelFont.
	self renderOn: surface
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:14'
}
GcStatsPanel >> renderOn: aSurface [
	"Composite all three graphs and their labels onto the drawing surface, exactly the
	same layout for the desktop morph (Canvas surface) and the XR texture (texture
	surface). Each stack is [label strip][graph form]. The surface abstracts the three
	primitives the two backends implement differently."
	| labelH y graphs g form formTop mid midY |
	labelH := self labelStripHeightFor: aSurface.
	y := 0.
	labelPoint ifNil: [labelPoint := 0@0. formPoint := 0@0].
	"Index loop over the CACHED graphs array (no #do: closure) and two retained scratch
	Points mutated in place, so compositing allocates no collection and no Point."
	graphs := self graphs.
	1 to: graphs size do: [:i |
		g := graphs at: i.
		form := g graph form.
		aSurface fillLabelStripAt: y height: labelH.
		aSurface drawLabel: g labelString at: (labelPoint setX: 2 setY: y + 1).
		y := y + labelH.
		formTop := y.
		aSurface drawForm: form at: (formPoint setX: 0 setY: y).
		y := y + form height.
		"A graph packing several lanes may caption a divider with a second label drawn
		INSIDE the form (over a filled strip so it stays readable)."
		mid := g midLabelString.
		mid ifNotNil: [
			midY := formTop + (form height * g midLabelFraction) truncated.
			aSurface fillLabelStripAt: midY height: labelH.
			aSurface drawLabel: mid at: (labelPoint setX: 2 setY: midY + 1)]]
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
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:01'
}
GcStatsPanel >> stepGraphsWithDelta: aDeltaMsOrNil [
	"Advance the three graph models one frame. aDeltaMsOrNil, when supplied, is the
	authoritative render-loop frame delta (XR passes SRFrame's deltaTime); when nil the
	fps graph measures wall-clock time between steps."
	graph updateTimeWith: aDeltaMsOrNil.
	graph updateGraph.
	youngGraph updateGraph.
	oldZoomGraph updateGraph.
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
