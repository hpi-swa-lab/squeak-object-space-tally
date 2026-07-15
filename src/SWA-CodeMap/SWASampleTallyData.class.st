"
Per-method SELF-sample counts collected by the external st-spy sampling profiler (SWASamplingTally), flattened into an image-independent 'Class>>selector' -> selfCount map so it can back a #sampleTally SWADataset that tints the Code Map by CPU self-time heat.

Build one with #fromSamplingTree: passing a SWASamplingTally rootNode: every Smalltalk frame in the call tree contributes its #selfCount to its #crossRefKey (summed across all stacks the method appeared in as the innermost frame). Native/unresolvable frames are ignored.

Query with #selfCountForKey: (raw self-sample count for a method, 0 if never sampled), #maxSelf (hottest method, for scaling), #methodNames, and #totalSamples.
"
Class {
	#name : #SWASampleTallyData,
	#superclass : #Object,
	#instVars : [
		'selfCounts',
		'total'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:30'
}
SWASampleTallyData class >> fromSamplingTree: aRootNode [
	"Build from a SWASamplingTally rootNode: walk the whole call tree and add each
	Smalltalk frame's #selfCount to its #crossRefKey. nil root yields empty data."
	^ self new buildFromSamplingTree: aRootNode
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:30'
}
SWASampleTallyData >> buildFromSamplingTree: aRootNode [
	"Walk the sampling call tree, summing each Smalltalk frame's #selfCount into its
	#crossRefKey. Native/unresolvable frames (nil crossRefKey) are skipped. Answers
	self."
	selfCounts := Dictionary new.
	total := 0.
	aRootNode ifNil: [^ self].
	aRootNode withAllChildrenDo: [:node |
		| key sc |
		sc := node selfCount ifNil: [0].
		sc > 0 ifTrue: [
			key := node crossRefKey.
			key ifNotNil: [
				selfCounts at: key put: (selfCounts at: key ifAbsent: [0]) + sc.
				total := total + sc]]].
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:30'
}
SWASampleTallyData >> maxSelf [
	"The hottest method's self-sample count, for scaling the heat ramp. 0 when empty."
	selfCounts isEmpty ifTrue: [^ 0].
	^ selfCounts values inject: 0 into: [:mx :v | mx max: v]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:30'
}
SWASampleTallyData >> methodNames [
	"The 'Class>>selector' keys that received at least one self-sample."
	^ selfCounts keys
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:31'
}
SWASampleTallyData >> selfCountForKey: aCrossRefKey [
	"Raw self-sample count for a method ('Class>>selector'). Answers nil when the key
	is absent (never the innermost frame) so the treemap rolls a container up from its
	children instead of pinning it to 0 -- matching how coverage/tally metrics behave."
	aCrossRefKey ifNil: [^ nil].
	^ selfCounts at: aCrossRefKey ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:31'
}
SWASampleTallyData >> totalSamples [
	"Total self-samples attributed to resolvable Smalltalk methods."
	^ total ifNil: [0]
]
