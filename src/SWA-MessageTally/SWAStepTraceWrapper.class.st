"
A SWATraceWrapper that MEASURES the Morphic cycle as well as recording it.

It is installed on exactly one method -- SWACoverage class>>stepProbeMethods, the cycle -- on every trace run, whether or not Morphic is in the traced package set, and it is never evicted. Its span goes into the running process's own lane like any other traced call, so if Morphic IS captured the trace looks exactly as it would have; the wrapper takes the ordinary wrapper's place rather than adding anything.

WHAT IT ADDS, on the way out, is the two things that need a once-per-frame moment to happen in:

  * a memory sample (SWATraceSeries), which becomes the continuous bands above the lanes;
  * a drain of the VM's GC counters into SWATraceMarker spans in the 'GC' lane.

An earlier version also wrapped #runStepMethods and #displayWorldSafely: and put all three in a synthetic lane of their own. That was wrong twice: those methods are already in the call graph when Morphic is traced, and the lane duplicated rows the trace already had. The step time is a measurement, and a measurement belongs in a band, not in a row of boxes.

Attribution caveat on the GC marks: the counters are global, so a collection triggered by another process is credited to the cycle that happens to read the counters next. Over a Morphic-driven run that is nearly always the honest answer; a mark means 'a GC completed by the end of this cycle', not 'this cycle caused it'.
"
Class {
	#name : #SWAStepTraceWrapper,
	#superclass : #SWATraceWrapper,
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:17'
}
SWAStepTraceWrapper >> recordIn: lane start: t0 stop: t1 depth: d [
	"Take the once-per-frame measurements, then record the cycle's span exactly as the
	ordinary wrapper would.

	The GC marks go into a LANE OF THEIR OWN at depth 0, not underneath this span.
	Nesting them here was the first design and it was wrong: a span is drawn only if
	every one of its ancestors was wide enough to draw, and the cycle that lost 100 ms
	to a full GC is frequently the narrowest thing on screen -- so the marks existed in
	the data and were never laid out. They are still CLAMPED to this cycle, which is all
	the VM's millisecond counters justify: the GC finished inside it, and where inside
	is not knowable."
	SWATraceWrapper gcLane ifNotNil: [:gcl |
		SWATraceMarker recordGcMarkersIn: gcl endingAt: t1 notBefore: t0 depth: 0].
	SWATraceSeries sampleAt: t1 duration: t1 - t0.
	super recordIn: lane start: t0 stop: t1 depth: d
]
