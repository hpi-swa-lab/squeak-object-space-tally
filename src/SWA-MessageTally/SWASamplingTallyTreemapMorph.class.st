"
Treemap morph specialised for st-spy sampled call trees. Tiles are sized by sample count (SWAStSpyNode>>totalSize). Color is a heat ramp by share of total samples (hot = red), label and balloon show sample counts and percentages.
"
Class {
	#name : #SWASamplingTallyTreemapMorph,
	#superclass : #SWATreemapMorph,
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:02'
}
SWASamplingTallyTreemapMorph >> balloonStringFor: aNode [
	"Hover balloon: name, wall time + percentage, self time, path."
	| rootTotal pct |
	rootTotal := rootNode totalSize max: 1.
	pct := (aNode totalSize * 100.0 / rootTotal) roundTo: 0.1.
	^ String streamContents: [:s |
		s nextPutAll: (aNode name ifNil: ['?']); cr.
		s nextPutAll: 'time: '; nextPutAll: (rootNode formatMicros: aNode totalSize);
			nextPutAll: ' ('; print: pct; nextPutAll: '%)'; cr.
		s nextPutAll: 'self: '; nextPutAll: (rootNode formatMicros: aNode selfSize); cr.
		s nextPutAll: 'path: '; nextPutAll: aNode pathString]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:36'
}
SWASamplingTallyTreemapMorph >> baseColorForNode: aNode [
	"Heat ramp by share of the root's total samples: cold blue -> hot red."
	| rootTotal frac |
	rootTotal := rootNode totalSize max: 1.
	frac := (aNode totalSize / rootTotal) asFloat.
	"sqrt to spread the low end where most frames live"
	frac := frac sqrt.
	^ Color h: (220.0 * (1.0 - frac)) s: 0.75 v: 0.85
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 16:57'
}
SWASamplingTallyTreemapMorph >> formatWeight: aNumber [
	"Sampling-tally treemap weights are microseconds of wall time (from st-spy)."
	^ rootNode formatMicros: aNumber
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:02'
}
SWASamplingTallyTreemapMorph >> labelFor: aNode inWidth: maxPixels [
	"Short tile label: frame name, plus wall time when there is room."
	| name |
	maxPixels < 16 ifTrue: [^ nil].
	name := aNode name ifNil: ['?'].
	maxPixels < 110 ifTrue: [^ name].
	^ name, '  ', (rootNode formatMicros: aNode totalSize)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWASamplingTallyTreemapMorph >> metaInfoString [
	"Meta line: focused subtree's total time + immediate child count.
	(SWAPane content protocol.)"
	| focus kids |
	focus := currentNode ifNil: [rootNode].
	focus ifNil: [^ ''].
	kids := focus children ifNil: [#()].
	^ focus name, '   ', (focus formatMicros: focus totalSize),
		'   ', kids size printString, ' children'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 15:02'
}
SWASamplingTallyTreemapMorph >> overlayClass [
	"The event/menu/hover overlay class this treemap uses -- a view-policy hook so the
	SWAPane can (re)wire an interaction overlay when morphing structures (e.g. the
	Tree-menu 'Grouped by class' projection of a call tally). Mirrors the manual wiring
	in SWASamplingTally>>openTreemap; without it #wireOverlayFor: DNUs on #overlayClass."
	^ SWASamplingTallyTreemapOverlay
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:01'
}
SWASamplingTallyTreemapMorph >> viewKind [
	^ #messageTallyTreemap
]
