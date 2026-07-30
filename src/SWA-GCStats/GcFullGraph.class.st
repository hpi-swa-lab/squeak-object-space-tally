"
GcFullGraph plots the composition of the committed object memory over time, one 2-pixel column per update, scrolling to the left.

Stacked from the bottom:
	gray	live old space			(vmParameterAt: 1 - vmParameterAt: 54)
	red	used young space		(vmParameterAt: 2), at least 1px when non-zero
	blue	free old space			(vmParameterAt: 54)

The top of the stack is therefore the total committed memory, old space + young space.

scale is in kilobytes per pixel and is derived from the committed memory so the whole stack fits the graph height. It is rounded to a 1-2-5 x 10^n value, grows as soon as the memory no longer fits, and shrinks again once less than half the range is used. A rescale is marked with a black column.

Note: on Spur, vmParameterAt: 1/2/3 are byte *sizes*; on the pre-Spur V3 memory manager they were *end addresses*, which is what the original version of this tool assumed.
"
Class {
	#name : #GcFullGraph,
	#superclass : #GcGraph,
	#instVars : [
		'scale'
	],
	#classVars : [
		'DefaultFullGraph'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 11/9/2005 12:21'
}
GcFullGraph class >> default [
	^DefaultFullGraph
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 11/9/2005 12:21'
}
GcFullGraph class >> disable [
	DefaultFullGraph := nil
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 11/9/2005 12:21'
}
GcFullGraph class >> enable [
	DefaultFullGraph := self new.
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 11/8/2005 16:17'
}
GcFullGraph >> graph [
	^graph ifNil: [graph := FormGraph new]
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:42'
}
GcFullGraph >> initialize [
	super initialize.
	
	graph := FormGraph new.
	graph position: 0@65.
	graph width: 480 height: 100.

	self updateScale
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:43'
}
GcFullGraph >> labelString [
	^String streamContents: [:s |
		s nextPutAll: 'old '; nextPutAll: (self mbString: self usedOldSpace);
		  nextPutAll: '  free '; nextPutAll: (self mbString: self freeSpace);
		  nextPutAll: '  young '; nextPutAll: (self mbString: self usedYoungSpace);
		  nextPut: $/; nextPutAll: (self mbString: self youngSpace);
		  nextPutAll: '  range '; nextPutAll: (self mbString: scale * graph height)]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcFullGraph >> niceScaleFor: kbPerPixel [
	"Round kbPerPixel up to the next 1-2-5 x 10^n value, so that the scale
	changes in recognizable steps instead of on every allocation."
	| magnitude |
	kbPerPixel <= 1 ifTrue: [^1].
	magnitude := 10 raisedTo: (kbPerPixel log: 10) floor.
	#(1 2 5 10) do: [:mantissa |
		mantissa * magnitude >= kbPerPixel ifTrue: [^mantissa * magnitude]].
	^10 * magnitude
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcFullGraph >> scale [
	"Kilobytes per pixel currently used by the graph."
	^scale
]

{
	#category : #update,
	#'squeak_changestamp' : 'jl 7/14/2006 10:55'
}
GcFullGraph >> update [

	self updateGraph.
	self graph display.

]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:42'
}
GcFullGraph >> updateGraph [

	"Draw one column showing the composition of the committed object memory:
	live old space (gray), used young space (red), free old space (blue)."
	| rescaled height top used free |
	rescaled := self updateScale.
	height := graph height.

	self graph shiftBy: 2.
	self graph
		drawFrom: 0 to: height
		color: (rescaled ifTrue: [Color black] ifFalse: [Color white])
		width: 2.

	top := (self usedOldSpace // scale) min: height.
	self graph drawFrom: 0 to: top color: Color gray width: 2.

	"young space is tiny compared to a large image, so make it at least one pixel"
	used := self usedYoungSpace.
	used := used isZero ifTrue: [0] ifFalse: [(used // scale) max: 1].
	self graph drawFrom: top to: (top := (top + used) min: height) color: Color red width: 2.

	free := self freeSpace // scale.
	self graph drawFrom: top to: ((top + free) min: height) color: Color blue width: 2.

]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:42'
}
GcFullGraph >> updateScale [
	"Answer true if the scale had to be changed. The scale is chosen so the whole
	committed object memory fits into the graph height. It grows as soon as it no
	longer fits, and shrinks again once the memory uses less than half the range."
	| needed |
	needed := self niceScaleFor: self committedSpace // (graph height max: 1) + 1.
	scale = needed ifTrue: [^false].
	(scale notNil and: [needed < scale and: [needed * 2 > scale]])
		ifTrue: [^false].	"hysteresis: don't shrink for small drops"
	scale := needed.
	^true
]
