"
GcFullGraph variant for SRGCStats: the free-space band (which barely moves) is replaced by young space, and young is plotted against its OWN eden capacity so the scavenge sawtooth is actually visible. The shared desktop GcFullGraph plots young at the global memory scale, where a few MB of eden is under one pixel and looks static.

Bands, bottom to top: used old space (deepOcean) at the global scale, then a young-space band (seafoam) whose height is usedYoungSpace/youngSpace of a fixed band, so a filling eden climbs and a scavenge drops it. No free-space band.
"
Class {
	#name : #SRGCMemGraph,
	#superclass : #GcFullGraph,
	#instVars : [
		'lastScavengeCount',
		'lastScavengeMs',
		'emaScavengeMs',
		'oldSpaceMax',
		'survivorYoung',
		'oldWindowMin',
		'oldWindowMax',
		'oldWindowSpan',
		'lastOldFullScale',
		'lastZoomFloor',
		'usedRing',
		'usedRingSize',
		'oldZoomOutMin',
		'oldZoomOutSpan',
		'ringHead'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 14:54'
}
SRGCMemGraph class >> scavengeEmaAlpha [
	"Smoothing factor for the exponential moving average of scavenge time. The sample
	cadence is one per scavenge (not per frame), so ~0.1 is about a 10-scavenge time
	constant: stable enough to read a sub-ms value, still tracks a changing load."
	^ 0.1
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:04'
}
SRGCMemGraph class >> survivorColor [
	"Deeper seafoam for the survivor baseline -- the young-space bytes still live right
	after the last scavenge, i.e. the floor the sawtooth drops to."
	^ self seafoamColor muchDarker
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:46'
}
SRGCMemGraph class >> youngBandHeight [
	"Pixels reserved above the old-space band for the young-space fill indicator.
	Full eden fills this whole band; a scavenge drops it toward the band's base."

	^ 40
]

{
	#category : #colors,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:48'
}
SRGCMemGraph class >> zoomMarkColor [
	"The red marker drawn in the zoom lane's newest column when its floor rebases (a GC or
	other lane movement), so the shift is visible as a vertical line."
	^ Color r: 0.9 g: 0.15 b: 0.15
]

{
	#category : #colors,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:23'
}
SRGCMemGraph class >> zoomOldColor [
	"Fill of the zoomed old-space lane. A saturated amber, distinct from the deep blue
	absolute-old lane and the teal young lane, and clearly visible on the white graph
	background (unlike the near-white paleOceanColor it replaced)."
	^ Color r: 0.90 g: 0.66 b: 0.20
]

{
	#category : #'scavenge timing',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 14:55'
}
SRGCMemGraph >> averageScavengeMs [
	"Mean milliseconds per scavenge over the window, or nil if no scavenge has been
	seen yet. A single scavenge is sub-millisecond, so only the average over many is
	meaningful -- per-frame p10 deltas read 0."

	^ emaScavengeMs
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:31'
}
SRGCMemGraph >> labelString [
	"old used, the zoomed-out window, young/eden, GC counts, and the mean scavenge time
	(the EMA -- a single scavenge is sub-ms, so only the average is meaningful)."
	^ String streamContents: [:s | | avg |
		s nextPutAll: 'old '; nextPutAll: (self mbString: self usedOldSpace);
		  nextPutAll: ' ['; nextPutAll: (self mbString: (oldZoomOutMin ifNil: [0]));
		  nextPut: $-; nextPutAll: (self mbString: ((oldZoomOutMin ifNil: [0]) + (oldZoomOutSpan ifNil: [0])));
		  nextPutAll: ']  Y '; nextPutAll: (self mbString: self usedYoungSpace);
		  nextPut: $/; nextPutAll: (self mbString: self youngSpace);
		  nextPutAll: '  gc '; print: (Smalltalk vmParameterAt: 7);
		  nextPut: $/; print: (Smalltalk vmParameterAt: 9).
		avg := self averageScavengeMs.
		avg ifNotNil: [s nextPutAll: '  scav '; nextPutAll: (avg asFloat printShowingDecimalPlaces: 2); nextPutAll: 'ms']]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:32'
}
SRGCMemGraph >> midLabelFraction [
	"Sit the second label just above the bottom (absolute-old) lane. That lane is 26% of
	the form height at the bottom, so its top divider is at 0.74 from the top; back off by
	roughly one label height so the caption rests on the divider rather than over the lane."
	^ 0.66
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:04'
}
SRGCMemGraph >> midLabelString [
	"The second label line, drawn at the divider BETWEEN the zoomed-in old lane (middle)
	and the zoomed-out old overview (bottom): the absolute old level, its running max, and
	the full-GC / scavenge counters."
	^ nil
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:43'
}
SRGCMemGraph >> oldLaneScaleFor: usedKb [
	"Full-scale of the bottom (zoomed-out) old lane, in kB: the smallest fixed step that
	contains usedKb, stepping 50, 100, 200, 400, 800 MB, ... (doubling). Fixed steps mean
	an allocation climbs the lane visibly and the scale only jumps at a boundary -- unlike
	scaling to committed old space, where used and committed grow together and the bar
	never moves."
	| step |
	step := 50 * 1024.   "50 MB in kB"
	[step < usedKb] whileTrue: [step := step * 2].
	^ step
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:46'
}
SRGCMemGraph >> pushUsed: usedKb [
	"Store the latest used-old value in a true circular buffer -- a fixed Array allocated
	ONCE (sized to the number of 2px columns the graph shows) with a write cursor. Steady
	state is a single SmallInteger slot store, ZERO allocation per frame, so the GC-stats
	path never itself allocates young garbage. ringHead is the next slot to write;
	usedRingSize is the fill count (<= cap until the ring wraps)."
	| cap |
	cap := (graph width // 2) max: 1.
	"Allocate/resize the backing Array only when the width changes (a resize), never per
	frame. On resize, start the history over -- the old columns no longer map to columns."
	(usedRing isNil or: [usedRing size ~= cap]) ifTrue: [
		usedRing := Array new: cap.
		ringHead := 1.
		usedRingSize := 0].
	usedRing at: ringHead put: usedKb.
	ringHead := ringHead \\ cap + 1.
	usedRingSize < cap ifTrue: [usedRingSize := usedRingSize + 1]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:46'
}
SRGCMemGraph >> repaintOldLaneBase: base height: laneH floor: floor step: step [
	"Clear the zoomed-out old lane band [base, base+laneH] and repaint every ring value at
	the given floor/step, oldest at the left, newest at the right (each a 2px column). Used
	after a rescale so history is preserved and correctly re-plotted rather than flushed.
	FormGraph value v maps to form row (formHeight - v), so the band's rows are
	(formHeight - (base+laneH)) .. (formHeight - base)."
	| formH top x cap idx |
	formH := graph height.
	top := formH - (base + laneH).
	"Blank the band across the full width."
	graph form
		fill: ((0 @ top) corner: (graph width @ (formH - base)))
		rule: Form over fillColor: self class backgroundColor.
	(usedRing isNil or: [usedRingSize = 0]) ifTrue: [^ self].
	cap := usedRing size.
	"Walk the circular buffer newest->oldest, drawing right->left. Newest is the slot just
	before ringHead."
	x := 2.
	idx := (ringHead - 2) \\ cap + 1.
	usedRingSize timesRepeat: [ | u fill |
		u := usedRing at: idx.
		fill := (((u - floor) max: 0) * laneH // step) min: laneH.
		graph form
			fill: (((graph width - x) @ (formH - base - fill)) corner: (graph width - x + 2) @ (formH - base))
			rule: Form over fillColor: self class deepOceanColor.
		x := x + 2.
		x > graph width ifTrue: [^ self].
		idx := (idx - 2) \\ cap + 1]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:08'
}
SRGCMemGraph >> repaintOldLaneFloor: floor step: step [
	"Clear the whole lane and repaint every ring value at the given floor/step, oldest at
	the left, newest at the right (each a 2px column). Used after a rescale so history is
	preserved and correctly re-plotted rather than flushed to white."
	| height n x |
	height := graph height.
	self graph drawFrom: 0 to: height color: self class backgroundColor width: graph width.
	usedRing isNil ifTrue: [^ self].
	n := usedRing size.
	"Rightmost column is the newest; walk back from the right so the newest lands at the edge."
	x := 2.
	usedRing reverseDo: [:u | | fill |
		fill := (((u - floor) max: 0) * height // step) min: height.
		"draw a 2px column at horizontal offset x from the right edge"
		graph form
			fill: (((graph width - x) @ (height - fill)) corner: (graph width - x + 2) @ height)
			rule: Form over fillColor: self class deepOceanColor.
		x := x + 2.
		x > graph width ifTrue: [^ self]]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:15'
}
SRGCMemGraph >> updateGraph [
	"Three lanes, TOP to bottom (FormGraph value 0 = form bottom, higher base = higher up):
	  1. young space -- scavenge sawtooth vs eden, survivor floor drawn deeper (top);
	  2. zoomed-in old -- usedOld at the young lane's kB/pixel over a whole-span floor, a
	     red mark when the floor rebases (middle);
	  3. zoomed-out old -- the dominant lane: a [floor, floor+step] window with strong
	     hysteresis (resizes rarely) and a used-value ring that repaints the whole lane at
	     the new scale on a rescale rather than flushing to white (bottom).

	p9 scavenge count / p10 cumulative scavenge ms fold into an EMA on a scavenge frame."
	| height youngLaneH zoomLaneH oldLaneH oldBase zoomBase youngBase used youngFill zoomFill zoomSpan rescale lo hi step floor scavenges scavengeMs countDelta |
	height := graph height.

	scavenges := Smalltalk vmParameterAt: 9.
	scavengeMs := Smalltalk vmParameterAt: 10.
	countDelta := lastScavengeCount ifNil: [0] ifNotNil: [scavenges - lastScavengeCount].
	countDelta > 0 ifTrue: [ | alpha sample |
		alpha := self class scavengeEmaAlpha.
		sample := (scavengeMs - lastScavengeMs) / countDelta.
		emaScavengeMs := emaScavengeMs ifNil: [sample] ifNotNil: [emaScavengeMs * (1 - alpha) + (sample * alpha)].
		survivorYoung := self usedYoungSpace].
	lastScavengeCount := scavenges.
	lastScavengeMs := scavengeMs.

	used := self usedOldSpace.
	self pushUsed: used.

	"Lane heights: zoomed-out old dominates (bottom), then zoomed-in old, then young (top)."
	oldLaneH := height * 60 // 100.
	youngLaneH := height * 16 // 100.
	zoomLaneH := height - oldLaneH - youngLaneH - 2.   "2 divider pixels"
	oldBase := 0.
	zoomBase := oldLaneH + 1.
	youngBase := zoomBase + zoomLaneH + 1.

	"Zoomed-in old lane: FIXED young resolution (eden per zoom-lane height); floor tracks in
	whole spans so used stays in view. Never rescales -- resolution is constant."
	zoomSpan := (self youngSpace max: 1) * zoomLaneH // (youngLaneH max: 1) max: 1.
	oldWindowSpan := zoomSpan.
	oldWindowMin ifNil: [oldWindowMin := used // zoomSpan * zoomSpan].
	[used >= (oldWindowMin + zoomSpan)] whileTrue: [oldWindowMin := oldWindowMin + zoomSpan].
	[used < oldWindowMin] whileTrue: [oldWindowMin := oldWindowMin - zoomSpan].

	"Zoomed-out old lane: decide whether to rescale (strong hysteresis, 15%..85% band)."
	rescale := oldZoomOutMin isNil or: [oldZoomOutSpan isNil].
	rescale ifFalse: [
		lo := oldZoomOutMin + (oldZoomOutSpan * 15 // 100).
		hi := oldZoomOutMin + (oldZoomOutSpan * 85 // 100).
		rescale := used < lo or: [used > hi]].
	rescale ifTrue: [
		step := 50 * 1024.
		[floor := ((used - (step // 2)) max: 0) // step * step.
		 (used - floor) >= step or: [(floor + step - used) < (step // 8)]]
			whileTrue: [step := step * 2].
		floor := ((used - (step // 2)) max: 0) // step * step.
		oldZoomOutSpan := step.
		oldZoomOutMin := floor].
	oldSpaceMax := oldZoomOutSpan.

	"--- draw ---"
	self graph shiftBy: 2.
	"Clear the newest column across young + zoomed-in lanes; the zoomed-out lane clears its
	own newest column here too (a full-lane repaint only happens on rescale, below)."
	self graph drawFrom: 0 to: height color: self class backgroundColor width: 2.

	"Zoomed-out old lane (bottom). On rescale repaint the whole lane from the ring."
	rescale
		ifTrue: [self repaintOldLaneBase: oldBase height: oldLaneH floor: oldZoomOutMin step: oldZoomOutSpan]
		ifFalse: [
			self graph
				drawFrom: oldBase
				to: oldBase + ((((used - oldZoomOutMin) max: 0) * oldLaneH // oldZoomOutSpan) min: oldLaneH)
				color: self class deepOceanColor width: 2].
	self graph drawFrom: oldLaneH to: zoomBase color: self class slateColor width: 2.

	"Zoomed-in old lane (middle)."
	zoomFill := zoomBase + ((((used - oldWindowMin) max: 0) * zoomLaneH // zoomSpan) min: zoomLaneH).
	self graph drawFrom: zoomBase to: zoomFill color: self class deepOceanColor width: 2.
	(lastZoomFloor notNil and: [lastZoomFloor ~= oldWindowMin]) ifTrue: [
		self graph drawFrom: zoomBase to: zoomBase + zoomLaneH color: self class zoomMarkColor width: 2].
	lastZoomFloor := oldWindowMin.
	self graph drawFrom: zoomBase + zoomLaneH to: youngBase color: self class slateColor width: 2.

	"Young lane (top): scavenge sawtooth vs eden, survivor floor drawn deeper."
	youngFill := self youngSpace isZero
		ifTrue: [0]
		ifFalse: [(self usedYoungSpace * youngLaneH // self youngSpace) min: youngLaneH].
	self graph drawFrom: youngBase to: youngBase + youngFill color: self class seafoamColor width: 2.
	survivorYoung ifNotNil: [ | survFill |
		survFill := self youngSpace isZero
			ifTrue: [0]
			ifFalse: [(survivorYoung * youngLaneH // self youngSpace) min: youngFill].
		self graph drawFrom: youngBase to: youngBase + survFill color: self class survivorColor width: 2]
]
