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
		'selectedNode',
		'navPanel',
		'metaInfo'
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:53'
}
SWAStSpyFlamegraphMorph >> aboutToStyle: aStyler [
	"Shout styling hook (called because we are the source pane's model). Configure
	the styler with the selected frame's class so ivars/selectors highlight in
	context, and allow styling to proceed."
	| ref |
	ref := selectedNode ifNotNil: [:n | n methodReference].
	(ref notNil and: [aStyler respondsTo: #classOrMetaClass:])
		ifTrue: [aStyler classOrMetaClass: ref first].
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:53'
}
SWAStSpyFlamegraphMorph >> aboutToStyle: aStyler requestor: anObject [
	"Shout styling hook (2-arg form the styler actually sends). Delegates to the
	1-arg #aboutToStyle:, mirroring Model>>aboutToStyle:requestor:."
	^ self aboutToStyle: aStyler
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:22'
}
SWAStSpyFlamegraphMorph >> breadcrumbString [
	"Compact breadcrumb of the zoom focus (root .. focusNode), elided from the
	HEAD so the deepest (most relevant) frames stay visible, plus the focus total."
	| parts node path |
	parts := OrderedCollection new.
	node := focusNode.
	[node notNil] whileTrue: [
		parts addFirst: (node name ifNil: ['?']).
		node := node parent].
	path := parts inject: '' into: [:s :p | s isEmpty ifTrue: [p] ifFalse: [s , ' / ' , p]].
	path := self elideHead: path to: 90.
	^ path, '   ', (rootNode formatMicros: (focusNode ifNil: [0] ifNotNil: [:n | n totalSize])), ' total'
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:58'
}
SWAStSpyFlamegraphMorph >> computeFrames [
	"Build `frames` -- a flat list of {node. rect. depth. isAncestor} -- in LOCAL
	coordinates (origin 0@0), so the layout can be rendered into a cached Form and
	blitted at #position on every draw. Width is proportional to totalSize;
	children pack left-to-right under their parent.

	When zoomed in, the ancestors of the focus are NOT given a row each (that wastes
	vertical space). Instead they are collapsed into a SINGLE strip at the very top
	(one full row tall, so it is easy to read and click) -- the full path is in the
	breadcrumb -- and the focus subtree gets the rest of the height."
	| ancestors width focusTotal startY |
	frames := OrderedCollection new.
	framesBounds := self bounds.
	(focusNode isNil or: [focusNode totalSize <= 0]) ifTrue: [^ frames].
	width := self width.
	ancestors := self ancestorChain.
	startY := 0.

	"One collapsed strip for ALL ancestors (only when zoomed in)."
	ancestors notEmpty ifTrue: [
		frames add: {
			focusNode parent.
			(0 @ 0 extent: width @ rowHeight).
			0.
			true }.
		startY := rowHeight].

	"Focus subtree fills the rest, starting just below the ancestor strip."
	focusTotal := focusNode totalSize.
	self layoutNode: focusNode x: 0 width: width top: startY scaleTotal: focusTotal.
	^ frames
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:57'
}
SWAStSpyFlamegraphMorph >> drawLabelFor: aNode in: r on: aCanvas font: font [
	"Draw aNode's name inside rect r, clipped, only if there is room."
	self
		drawLabelString: (aNode name ifNil: ['?'])
		in: r on: aCanvas font: font color: (Color gray: 0.1)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:57'
}
SWAStSpyFlamegraphMorph >> drawLabelString: aString in: r on: aCanvas font: font color: aColor [
	"Draw aString inside rect r, clipped + tilde-truncated to fit, in aColor.
	Only when there is room."
	| charW maxChars text |
	r width < 24 ifTrue: [^ self].
	charW := (font widthOf: $m) max: 1.
	maxChars := (r width - 6) // charW max: 0.
	maxChars < 2 ifTrue: [^ self].
	text := aString size > maxChars
		ifTrue: [(aString first: (maxChars - 1 max: 1)), '~']
		ifFalse: [aString].
	aCanvas
		drawString: text
		in: (r insetBy: (3 @ 1))
		font: font
		color: aColor
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:22'
}
SWAStSpyFlamegraphMorph >> elideHead: aString to: maxChars [
	"Truncate aString to maxChars, dropping characters from the FRONT and prefixing
	an ellipsis, so the tail (end) is always visible."
	aString size <= maxChars ifTrue: [^ aString].
	^ '...', (aString last: (maxChars - 3 max: 1))
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:37'
}
SWAStSpyFlamegraphMorph >> labelFont [
	"Font for frame labels. BitstreamVeraSans (~21px) is ~50% bigger than the old
	compact Atlanta, crisp and readable; rows grow to fit (see #initialize). Falls
	back to a small bitmap font, then the default, if unavailable."
	^ (StrikeFont familyName: 'BitstreamVeraSans' size: 9)
		ifNil: [(StrikeFont familyName: 'Atlanta' size: 8)
			ifNil: [TextStyle defaultFont]]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:56'
}
SWAStSpyFlamegraphMorph >> layoutNode: aNode x: x width: w top: top scaleTotal: scaleTotal [
	"Emit a LOCAL-coordinate frame for aNode at the given x/width with its top at
	the given pixel y, then lay out its children left-to-right one rowHeight below.
	Stops recursing into frames narrower than minFrameWidth or that fall below the
	morph height."
	| childX kids |
	w < minFrameWidth ifTrue: [^ self].
	top + rowHeight > self height ifTrue: [^ self].
	frames add: {
		aNode.
		(x @ top extent: w @ rowHeight).
		top.
		false }.
	"children packed under us, scaled to OUR pixel width by OUR totalSize"
	kids := aNode children asSortedCollection: [:a :b | a totalSize >= b totalSize].
	aNode totalSize <= 0 ifTrue: [^ self].
	childX := x.
	kids do: [:kid | | kw |
		kw := w * kid totalSize / aNode totalSize.
		self layoutNode: kid x: childX width: kw top: top + rowHeight scaleTotal: scaleTotal.
		childX := childX + kw]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:52'
}
SWAStSpyFlamegraphMorph >> metaInfo: aString [
	"Static run-level meta line (pid / duration / samples / rate), set by the opener."
	metaInfo := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:52'
}
SWAStSpyFlamegraphMorph >> metaInfoString [
	"Run-level meta line for the panel. (SWANavPanel content protocol.)"
	^ metaInfo ifNil: ['']
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:52'
}
SWAStSpyFlamegraphMorph >> mouseDown: evt [
	"Left-click a frame: select it (highlight + detail line + source). Click the
	SAME frame again: zoom into it. Click the collapsed ancestor strip at the top:
	zoom out one level. Right-click: explore the node."
	| f node |
	f := self frameAt: evt position.
	f isNil ifTrue: [^ self].
	node := f at: 1.

	"Right-click: explore."
	evt yellowButtonPressed ifTrue: [^ ToolSet explore: node].

	"Collapsed ancestor strip: zoom out one level."
	(f at: 4) ifTrue: [^ self zoomOut].

	"Same frame clicked twice -> zoom in."
	(selectedNode notNil and: [selectedNode == node])
		ifTrue: [^ self zoomInto: node].

	"Otherwise: select this frame."
	selectedNode := node.
	self flushCache.
	self refreshChrome
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWAStSpyFlamegraphMorph >> navPanel [
	^ navPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWAStSpyFlamegraphMorph >> navPanel: aSWANavPanel [
	"The chrome panel that owns my breadcrumb/selection/meta labels + source pane."
	navPanel := aSWANavPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:56'
}
SWAStSpyFlamegraphMorph >> refreshChrome [
	"Refresh the nav-panel chrome (breadcrumb, selection, meta) + source pane.
	No-op when used standalone without a panel."
	navPanel ifNotNil: [:p | p refresh]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:57'
}
SWAStSpyFlamegraphMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Paint background and every frame into aCanvas, offset by anOrigin (local
	coords + anOrigin). The collapsed ancestor strip is drawn as a thin dark
	'zoom out' bar; the selected frame is brightened with a white border."
	| font |
	aCanvas fillRectangle: (anOrigin extent: self extent) color: self color.
	font := self labelFont.
	frames do: [:f | | node r screenR isAnc fill isSel |
		node := f at: 1. r := f at: 2. isAnc := f at: 4.
		screenR := r translateBy: anOrigin.
		isAnc
			ifTrue: [
				"Collapsed ancestor strip: thin dark bar with a 'zoom out' hint + path."
				aCanvas fillRectangle: screenR color: (Color gray: 0.28).
				aCanvas frameRectangle: screenR width: 1 color: (Color gray: 0.12).
				self
					drawLabelString: ('zoom out  -  ',
						(focusNode ifNil: [''] ifNotNil: [:n | n pathString]))
					in: screenR on: aCanvas font: font color: (Color gray: 0.85)]
			ifFalse: [
				isSel := selectedNode notNil and: [selectedNode == node].
				fill := self colorForNode: node.
				isSel ifTrue: [fill := fill lighter lighter].
				aCanvas fillRectangle: (screenR insetBy: (0.5 @ 0.5)) color: fill.
				isSel
					ifTrue: [aCanvas frameRectangle: screenR width: 2 color: Color white]
					ifFalse: [aCanvas frameRectangle: screenR width: 1 color: (Color gray: 0.12)].
				self drawLabelFor: node in: screenR on: aCanvas font: font]]
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
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:52'
}
SWAStSpyFlamegraphMorph >> selectedSourceString [
	"Source text for the Show pane: the selected frame's method source, or a
	placeholder for native/VM frames. (SWANavPanel content protocol.)"
	selectedNode ifNil: [^ ''].
	^ selectedNode sourceString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWAStSpyFlamegraphMorph >> selectionPathString [
	"Detail line for the SELECTED frame: name, time, percent of the whole tree, and
	self time. Empty when nothing is selected. (SWANavPanel content protocol.)"
	| rootTotal pct |
	selectedNode ifNil: [^ ''].
	rootTotal := rootNode totalSize max: 1.
	pct := (selectedNode totalSize * 100.0 / rootTotal) roundTo: 0.1.
	^ selectedNode name,
		'   ', (rootNode formatMicros: selectedNode totalSize),
		' (', pct printString, '%)',
		'   self ', (rootNode formatMicros: selectedNode selfSize)
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:52'
}
SWAStSpyFlamegraphMorph >> zoomInto: aNode [
	"Make aNode the new focus, if it has children. Push the current focus onto the
	history so Back can return, and clear the selection."
	| kids |
	(aNode isNil or: [aNode == focusNode]) ifTrue: [^ self].
	kids := aNode children.
	(kids isNil or: [kids isEmpty]) ifTrue: [^ self].
	history addLast: focusNode.
	selectedNode := nil.
	self focusNode: aNode.
	self refreshChrome
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:52'
}
SWAStSpyFlamegraphMorph >> zoomOut [
	"Go back to the previous focus from history, clearing the selection."
	history isEmpty ifTrue: [^ self].
	selectedNode := nil.
	self focusNode: history removeLast.
	self refreshChrome
]
