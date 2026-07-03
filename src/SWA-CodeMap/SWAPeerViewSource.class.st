"
Adapts another open SWA view (a peer treemap/flamegraph) as a #peer SWADataset
source, so cross-referencing is just another dataset in the Data menu rather than
a bespoke X-ref overlay.

Answers per-crossRefKey values from the peer view's keyIndex (crossRefKey -> node),
weighted by the peer node's totalSize -- the same weighting the old
crossReferenceFrom: used, now flowing through the normal dataset color path so it
mixes and matches like any loaded file.

Because it reads the LIVE peer keyIndex on each query, the coloring reflects the
peer's current state. Holds the peer weakly-ish by reference only; if the peer
window is closed its keyIndex still answers what it last had (harmless).
"
Class {
	#name : #SWAPeerViewSource,
	#superclass : #Object,
	#instVars : [
		'peerView'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
}
SWAPeerViewSource >> maxWeight [
	"Largest peer weight, for log-normalizing the color scale. 1 if empty."
	| m |
	m := 0.
	peerView keyIndex valuesDo: [:node |
		node totalSize ifNotNil: [:w | m := m max: w]].
	^ m max: 1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
}
SWAPeerViewSource >> peerView [
	^ peerView
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
}
SWAPeerViewSource >> peerView: aSWAView [
	peerView := aSWAView
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
}
SWAPeerViewSource >> weightForKey: aCrossRefKey [
	"The peer's weight (totalSize: samples/bytes/loc) for aCrossRefKey, or nil if the
	peer has no node under that key. Read live from the peer's keyIndex."
	| node |
	aCrossRefKey ifNil: [^ nil].
	node := peerView keyIndex at: aCrossRefKey ifAbsent: [nil].
	^ node ifNotNil: [node totalSize]
]
