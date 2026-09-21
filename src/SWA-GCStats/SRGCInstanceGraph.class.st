"
A lane counting live instances of one class, RlVector3 by default: the question
""are the FFI structs actually piling up, or are they dying"" answered directly
rather than inferred from allocation rates.

Expensive, and therefore off by default and sampled once a second rather than
once a paint. #allInstances on this image is 23 ms and 16 KB for ~1000
instances -- at the panel's 10 fps that would be a quarter of all wall time.
#instanceCount looks cheaper but measured 353 KB, so it is not used.

The bar is the count auto-scaled against the largest seen, so the shape is
about growth, not an absolute.
"
Class {
	#name : #SRGCInstanceGraph,
	#superclass : #SRGCSurvivorGraph,
	#instVars : [
		'instanceClass',
		'count',
		'maxCount',
		'lastSampleMillis',
		'samplePeriodMillis',
		'scanMillis'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:13'
}
SRGCInstanceGraph >> count [
	^ count.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:13'
}
SRGCInstanceGraph >> instanceClass [
	^ instanceClass ifNil: [instanceClass := RlVector3].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:13'
}
SRGCInstanceGraph >> instanceClass: aClass [
	instanceClass := aClass.
	count := nil.
	maxCount := 0.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:13'
}
SRGCInstanceGraph >> labelString [
	| s |
	s := self labelStreamReset.
	s nextPutAll: self instanceClass name; nextPutAll: ' '.
	count ifNil: [s nextPut: $?] ifNotNil: [s print: count].
	maxCount ifNotNil: [s nextPutAll: '  max '; print: maxCount].
	scanMillis ifNotNil: [s nextPutAll: '  scan '; print: scanMillis; nextPutAll: 'ms'].
	^ s contents.
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:26'
}
SRGCInstanceGraph >> sample [
	"#allInstances counts unreclaimed garbage as well as live objects, so this reads
	high between scavenges -- 14000 against 2 for RlVector3. It also pins everything it
	finds for ~26 ms, so a scavenge landing in that window copies that garbage into
	survivor space and inflates the survivor lane. Both are left alone on purpose: a
	lane must not collect, or every other lane is measuring the lane."

	| start |
	start := Time millisecondClockValue.
	count := self instanceClass allInstances size.
	scanMillis := Time millisecondClockValue - start.
	maxCount := (maxCount ifNil: [0]) max: count.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:14'
}
SRGCInstanceGraph >> samplePeriodMillis [
	"0 = every update, i.e. the same resolution as every other lane. A lane you turned
	on to watch something is useless at a different cadence from the lane next to it."

	^ samplePeriodMillis ifNil: [samplePeriodMillis := 0].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:14'
}
SRGCInstanceGraph >> samplePeriodMillis: anInteger [
	"0 samples every update. Raise it to trade resolution back for frame time."

	samplePeriodMillis := anInteger max: 0.
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:13'
}
SRGCInstanceGraph >> updateGraph [
	"Held between samples, so the lane keeps drawing the last count rather than gaps."

	| now height |
	now := Time millisecondClockValue.
	(lastSampleMillis isNil or: [now - lastSampleMillis >= self samplePeriodMillis])
		ifTrue: [self sample. lastSampleMillis := now].
	height := graph height.
	graph shiftBy: 2.
	graph drawFrom: 0 to: height color: self class backgroundColor width: 2.
	count ifNotNil: [
		self plotValue: count max: maxCount color: self class survivorColor].
]
