"
A flamegraph view of an st-spy sampled call tree. Consumes exactly the same duck-typed SWAStSpyNode tree as SWAStSpyTreemapMorph -- no separate data structure.

Layout: one horizontal row per stack depth (root at the top). Each frame is a rectangle whose WIDTH is proportional to the node's #totalSize (wall-clock microseconds) and whose X packs left-to-right under its parent, so a frame is exactly as wide as the sum of its children. Taller stacks = deeper call chains; wide plateaus = where time is spent.

Interaction:
  - hover: balloon with name / time / percent / self / path (a 'frame' is {node. rect. depth}).
  - click a frame: zoom so that frame fills the width (set #focusNode); ancestors shown dimmed above.
  - click the root row (or the top ancestor strip): zoom back out one level.

Color: classic warm flame palette, hashed by frame name for stable, distinguishable bars (deterministic per name).

Open via SWAStSpy>>openFlamegraph, or directly: SWAStSpyFlamegraphMorph on: aSWAStSpyNode.
"
Class {
	#name : #SWAStSpyFlamegraphMorph,
	#superclass : #Morph,
	#instVars : [
		'rootNode',
		'focusNode',
		'rowHeight',
		'frames',
		'minFrameWidth',
		'framesBounds',
		'cachedForm',
		'history',
		'breadcrumbMorph',
		'selectedNode',
		'selectionPathMorph'
	],
	#category : #'SWA-StSpy',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:52'
}
SWAStSpyFlamegraphMorph class >> on: aNode [
	"Create a flamegraph rooted at the given SWAStSpyNode (duck-typed)."
	^ self new setRoot: aNode
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:53'
}
SWAStSpyFlamegraphMorph >> ancestorChain [
	"focusNode's ancestors, root-first (excluding focusNode itself)."
	| chain n |
	chain := OrderedCollection new.
	n := focusNode parent.
	[n notNil] whileTrue: [chain addFirst: n. n := n parent].
	^ chain
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:08'
}
SWAStSpyFlamegraphMorph >> breadcrumbMorph: aMorph [
	breadcrumbMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:08'
}
SWAStSpyFlamegraphMorph >> breadcrumbString [
	"Breadcrumb of the zoom focus (root .. focusNode) + total time, with control
	hints. Mirrors SWATreemapMorph>>breadcrumbString."
	| parts node total |
	parts := OrderedCollection new.
	node := focusNode.
	[node notNil] whileTrue: [
		parts addFirst: (node name ifNil: ['?']).
		node := node parent].
	total := focusNode ifNil: [0] ifNotNil: [:n | n totalSize].
	^ (parts inject: '' into: [:s :p | s isEmpty ifTrue: [p] ifFalse: [s , ' / ' , p]])
		, '   '
		, (rootNode formatMicros: total) , ' total'
		, '   [click: zoom in, Back: zoom out, right-click: explore]'
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWAStSpyFlamegraphMorph >> browseSelected [
	"Open a system browser on the selected frame's method, if it is a resolvable
	Smalltalk frame. Wired to the Browse button via actionSelector: #browseSelected.
	Beeps for native/VM frames or when nothing is selected."
	(selectedNode notNil and: [selectedNode isSmalltalkFrame])
		ifTrue: [selectedNode browse]
		ifFalse: [Beeper beep]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:53'
}
SWAStSpyFlamegraphMorph >> colorForNode: aNode [
	"Classic flamegraph warm palette: reds/oranges/yellows, deterministic per
	frame name so the same method is always the same color."
	| h hue sat bri |
	h := (aNode name ifNil: ['?']) hash.
	hue := 10.0 + ((h \\ 50)).            "10..60 deg: red -> orange -> yellow"
	sat := 0.65 + ((h // 50 \\ 30) / 100.0).  "0.65..0.94"
	bri := 0.82 + ((h // 1500 \\ 15) / 100.0). "0.82..0.96"
	^ Color h: hue s: sat v: bri
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> computeFrames [
	"Build `frames` -- a flat list of {node. rect. depth. isAncestor} -- in LOCAL
	coordinates (origin 0@0), so the layout can be rendered into a cached Form and
	blitted at #position on every draw. Width is proportional to totalSize;
	children pack left-to-right under their parent. Ancestors of the focus are
	full-width dimmed strips above. Records the extent it laid out for so a resize
	triggers a recompute."
	| ancestors topRows width focusTotal |
	frames := OrderedCollection new.
	framesBounds := self bounds.
	(focusNode isNil or: [focusNode totalSize <= 0]) ifTrue: [^ frames].
	width := self width.
	ancestors := self ancestorChain.

	"Ancestor strips: one full-width row each, root at the very top."
	topRows := ancestors size.
	ancestors doWithIndex: [:anc :i |
		frames add: {
			anc.
			(0 @ ((i - 1) * rowHeight) extent: width @ rowHeight).
			i - 1.
			true }].

	"Focus subtree, starting on the row just below the ancestor strip."
	focusTotal := focusNode totalSize.
	self layoutNode: focusNode x: 0 width: width row: topRows scaleTotal: focusTotal.
	^ frames
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:54'
}
SWAStSpyFlamegraphMorph >> drawLabelFor: aNode in: r on: aCanvas font: font [
	"Draw aNode's name inside rect r, clipped, only if there is room."
	| label charW maxChars text |
	r width < 24 ifTrue: [^ self].
	label := aNode name ifNil: ['?'].
	charW := (font widthOf: $m) max: 1.
	maxChars := (r width - 6) // charW max: 0.
	maxChars < 2 ifTrue: [^ self].
	text := label size > maxChars
		ifTrue: [(label first: (maxChars - 1 max: 1)), '~']
		ifFalse: [label].
	aCanvas
		drawString: text
		in: (r insetBy: (3 @ 1))
		font: font
		color: (Color gray: 0.1)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> drawOn: aCanvas [
	"Blit the cached static layer (rendered once, in local coords). No per-frame
	recompute or background fill here -- that is what caused the flicker."
	| form |
	self ensureFrames.
	form := self ensureCachedForm.
	aCanvas
		image: form
		at: self position
		sourceRect: form boundingBox
		rule: Form over
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> ensureCachedForm [
	"Render the whole flamegraph into a Form once (local coords). Re-used as a
	single blit on every subsequent draw until the layout invalidates -- this is
	what eliminates the per-frame fill/repaint flicker."
	| form canvas |
	cachedForm ifNotNil: [^ cachedForm].
	form := Form extent: self extent depth: Display depth.
	canvas := form getCanvas.
	self renderStaticLayerOn: canvas at: 0 @ 0.
	cachedForm := form.
	^ cachedForm
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> ensureFrames [
	"Recompute the frame layout (and drop the cached form) if it is missing or was
	laid out for a different extent (the window may have resized the morph)."
	(frames isNil or: [frames isEmpty or: [framesBounds ~= self bounds]])
		ifTrue: [self computeFrames. cachedForm := nil]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> extent: aPoint [
	"On a real size change, invalidate the layout and the cached form so the next
	draw re-renders at the new extent."
	aPoint = self extent ifFalse: [
		frames := OrderedCollection new.
		cachedForm := nil].
	super extent: aPoint
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> flushCache [
	"Drop the cached Form so the next draw rebuilds it."
	cachedForm := nil.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:10'
}
SWAStSpyFlamegraphMorph >> focusNode [
	^ focusNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> focusNode: aNode [
	"Zoom so aNode's subtree fills the width. Invalidates the layout + cache."
	focusNode := aNode.
	frames := OrderedCollection new.
	cachedForm := nil.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> frameAt: aPoint [
	"The topmost frame whose (local-coord) rect contains aPoint. aPoint is in world
	coords, so translate it into local space first."
	| local |
	self ensureFrames.
	local := aPoint - self position.
	^ frames detect: [:f | (f at: 2) containsPoint: local] ifNone: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:54'
}
SWAStSpyFlamegraphMorph >> frames [
	"The laid-out frames: a list of {node. rect. depth. isAncestor}."
	^ frames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:01'
}
SWAStSpyFlamegraphMorph >> framesBounds [
	"The morph bounds the current `frames` were laid out for."
	^ framesBounds
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:53'
}
SWAStSpyFlamegraphMorph >> handlesMouseDown: evt [
	^ true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:10'
}
SWAStSpyFlamegraphMorph >> history [
	^ history
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:08'
}
SWAStSpyFlamegraphMorph >> initialize [
	super initialize.
	self extent: 1000 @ 600.
	self color: (Color gray: 0.12).
	self borderWidth: 0.
	minFrameWidth := 1.
	frames := OrderedCollection new.
	history := OrderedCollection new.
	"rowHeight is derived from the label font so glyphs are never clipped."
	rowHeight := self labelFont height + 3
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:57'
}
SWAStSpyFlamegraphMorph >> labelFont [
	"A compact font for frame labels. The image's TTC default font is ~25px tall,
	far too big for thin flamegraph rows, so prefer a small bitmap StrikeFont and
	fall back to the default only if unavailable."
	^ (StrikeFont familyName: 'Atlanta' size: 8)
		ifNil: [TextStyle defaultFont]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> layoutNode: aNode x: x width: w row: row scaleTotal: scaleTotal [
	"Emit a LOCAL-coordinate frame for aNode at the given x/width on the given row,
	then lay out its children left-to-right beneath it, each sized in proportion to
	its totalSize. Stops recursing into frames narrower than minFrameWidth or rows
	that fall below the morph height."
	| top childX kids |
	w < minFrameWidth ifTrue: [^ self].
	top := row * rowHeight.
	top + rowHeight > self height ifTrue: [^ self].
	frames add: {
		aNode.
		(x @ top extent: w @ rowHeight).
		row.
		false }.
	"children packed under us, scaled to OUR pixel width by OUR totalSize"
	kids := aNode children asSortedCollection: [:a :b | a totalSize >= b totalSize].
	aNode totalSize <= 0 ifTrue: [^ self].
	childX := x.
	kids do: [:kid | | kw |
		kw := w * kid totalSize / aNode totalSize.
		self layoutNode: kid x: childX width: kw row: row + 1 scaleTotal: scaleTotal.
		childX := childX + kw]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:08'
}
SWAStSpyFlamegraphMorph >> mouseDown: evt [
	"Left-click a frame: select it (highlight + show its path). Click the SAME
	frame again: zoom into it. Right-click: explore the node. Ancestor strips
	always zoom out to that ancestor. Mirrors SWATreemapOverlay>>mouseDown:."
	| f node |
	f := self frameAt: evt position.
	f isNil ifTrue: [^ self].
	node := f at: 1.

	"Right-click: explore."
	evt yellowButtonPressed ifTrue: [^ ToolSet explore: node].

	"Ancestor strip: zoom out to that ancestor directly."
	(f at: 4) ifTrue: [
		selectedNode := node.
		self updateSelectionPath: node.
		^ self zoomInto: node].

	"Same frame clicked twice -> zoom in."
	(selectedNode notNil and: [selectedNode == node])
		ifTrue: [^ self zoomInto: node].

	"Otherwise: select this frame."
	selectedNode := node.
	self flushCache.
	self updateSelectionPath: node
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:09'
}
SWAStSpyFlamegraphMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Paint background and every frame into aCanvas, offset by anOrigin (local
	coords + anOrigin). The selected frame is brightened with a white border."
	| font |
	aCanvas fillRectangle: (anOrigin extent: self extent) color: self color.
	font := self labelFont.
	frames do: [:f | | node r screenR isAnc fill isSel |
		node := f at: 1. r := f at: 2. isAnc := f at: 4.
		screenR := r translateBy: anOrigin.
		isSel := selectedNode notNil and: [selectedNode == node and: [isAnc not]].
		fill := self colorForNode: node.
		isAnc ifTrue: [fill := fill alpha: 0.35].
		isSel ifTrue: [fill := fill lighter lighter].
		aCanvas fillRectangle: (screenR insetBy: (0.5 @ 0.5)) color: fill.
		isSel
			ifTrue: [aCanvas frameRectangle: screenR width: 2 color: Color white]
			ifFalse: [aCanvas frameRectangle: screenR width: 1 color: (Color gray: 0.12)].
		self drawLabelFor: node in: screenR on: aCanvas font: font]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:52'
}
SWAStSpyFlamegraphMorph >> rootNode [
	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:58'
}
SWAStSpyFlamegraphMorph >> rowHeight [
	^ rowHeight
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:10'
}
SWAStSpyFlamegraphMorph >> selectedNode [
	^ selectedNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:08'
}
SWAStSpyFlamegraphMorph >> selectionPathMorph: aMorph [
	selectionPathMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:05'
}
SWAStSpyFlamegraphMorph >> setRoot: aNode [
	rootNode := aNode.
	focusNode := aNode.
	frames := OrderedCollection new.
	cachedForm := nil.
	self changed.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:08'
}
SWAStSpyFlamegraphMorph >> updateBreadcrumb [
	breadcrumbMorph ifNotNil: [
		breadcrumbMorph contents: self breadcrumbString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:09'
}
SWAStSpyFlamegraphMorph >> updateSelectionPath: aNodeOrNil [
	"Update the selection path label to show the full path + time of aNodeOrNil.
	Mirrors SWATreemapMorph>>updateSelectionPath:."
	selectionPathMorph ifNil: [^ self].
	aNodeOrNil
		ifNil: [selectionPathMorph contents: '']
		ifNotNil: [selectionPathMorph contents:
			aNodeOrNil pathString, '   (',
			(rootNode formatMicros: aNodeOrNil totalSize), ')']
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:09'
}
SWAStSpyFlamegraphMorph >> zoomInto: aNode [
	"Make aNode the new focus, if it has children. Push the current focus onto the
	history so Back can return, and clear the selection. Mirrors
	SWATreemapMorph>>zoomInto:."
	| kids |
	(aNode isNil or: [aNode == focusNode]) ifTrue: [^ self].
	kids := aNode children.
	(kids isNil or: [kids isEmpty]) ifTrue: [^ self].
	history addLast: focusNode.
	selectedNode := nil.
	self updateSelectionPath: nil.
	self focusNode: aNode.
	self updateBreadcrumb
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:09'
}
SWAStSpyFlamegraphMorph >> zoomOut [
	"Go back to the previous focus from history, clearing the selection. Mirrors
	SWATreemapMorph>>zoomOut. Wired to the Back button via actionSelector: #zoomOut."
	history isEmpty ifTrue: [^ self].
	selectedNode := nil.
	self updateSelectionPath: nil.
	self focusNode: history removeLast.
	self updateBreadcrumb
]
