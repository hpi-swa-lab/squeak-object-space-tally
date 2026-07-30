"
GcGraph generates and updates a Form with timing and gc information.
It displays it directly.

to install it: insert ""GcGraph update."" into WorldState>>interCyclePause: milliSecs

then start it with: GcGraph enable
"
Class {
	#name : #GcGraph,
	#superclass : #Object,
	#instVars : [
		'lastTime',
		'lastGcCount',
		'lastTenurCount',
		'graph',
		'deltaTime'
	],
	#classVars : [
		'Default'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:57'
}
GcGraph class >> backgroundColor [
	"Background of the graph forms, and of the morph wherever the forms have
	not been painted yet."
	^ Color white
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:56'
}
GcGraph class >> coralColor [
	"Marker for a full GC. The one warm colour in the palette, muted so it
	stands out without shouting."
	^ Color r: 0.87 g: 0.55 b: 0.47
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:56'
}
GcGraph class >> deepOceanColor [
	"Live old space, and the frame time bars: the deep water at the bottom."
	^ Color r: 0.16 g: 0.36 b: 0.47
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 17:38'
}
GcGraph class >> default [
	^Default
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 19:17'
}
GcGraph class >> disable [
	Default := nil
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 19:17'
}
GcGraph class >> enable [
	Default := self new.
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 11/9/2005 22:44'
}
GcGraph class >> new [
	^super new
		initialize
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:57'
}
GcGraph class >> paleOceanColor [
	"The pale tint used for the window frame."
	^ Color r: 0.855 g: 0.925 b: 0.945
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:56'
}
GcGraph class >> seafoamColor [
	"Used young space, and the marker for a tenure."
	^ Color r: 0.35 g: 0.72 b: 0.66
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:56'
}
GcGraph class >> shallowOceanColor [
	"Free old space: shallow water above the live objects."
	^ Color r: 0.62 g: 0.80 b: 0.855
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:56'
}
GcGraph class >> slateColor [
	"Labels, and the marker column for a change of scale."
	^ Color r: 0.24 g: 0.32 b: 0.38
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 19:22'
}
GcGraph class >> update [
	self default ifNotNil: [ self default update].
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:57'
}
GcGraph class >> windowColor [
	"Border and title bar of the window. Only the frame is tinted; the graphs
	themselves keep a white background."
	^ self paleOceanColor
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> committedSpace [
	"All memory the object memory currently occupies, in kilobytes:
	live old space + free old space + used young space."
	^self oldSpace + self usedYoungSpace
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 7/14/2006 10:37'
}
GcGraph >> extent: aPoint [
	graph width: aPoint x height: aPoint y
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 7/14/2006 10:28'
}
GcGraph >> form [
	^graph form
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:44'
}
GcGraph >> fps [
	"Frames per second derived from the last update interval.
	Guard against two updates within the same millisecond."
	^(deltaTime isNil or: [deltaTime isZero])
		ifTrue: [0]
		ifFalse: [1000 // deltaTime]
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> freeSpace [
	"Free space inside the committed old space, in kilobytes.
	Spur only; answer 0 on VMs that do not report it."
	^((Smalltalk vmParameterAt: 54) ifNil: [0]) // 1024
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 10/28/2005 16:03'
}
GcGraph >> graph [
	^graph ifNil: [graph := FormGraph new]
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 11/9/2005 22:45'
}
GcGraph >> initialize [
	graph := FormGraph new.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:44'
}
GcGraph >> labelString [
	^String streamContents: [:s |
		s nextPutAll: 'fps '; print: self fps;
		  nextPutAll: '  fullGC '; print: (Smalltalk vmParameterAt: 7);
		  nextPutAll: '  scavenge '; print: (Smalltalk vmParameterAt: 9);
		  nextPutAll: '  rootTable '; print: self rootTableSize]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 10/28/2005 16:01'
}
GcGraph >> lastTime [
	^lastTime ifNil: [ lastTime := Time millisecondClockValue - 1]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:42'
}
GcGraph >> mbString: kb [
	"Print a kilobyte amount compactly."
	kb < 1024 ifTrue: [^kb printString, 'k'].
	^(kb / 1024.0 printShowingDecimalPlaces: 1), 'M'
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> oldSpace [
	"Total committed old space, in kilobytes. Includes the free old space."
	^(Smalltalk vmParameterAt: 1) // 1024
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'jl 11/8/2005 23:40'
}
GcGraph >> rootTableSize [
	^Smalltalk vmParameterAt: 21
]

{
	#category : #update,
	#'squeak_changestamp' : 'jl 7/14/2006 10:56'
}
GcGraph >> update [
	
	self updateTime.
	self updateGraph.
	graph form display.
	self updateText.

]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:57'
}
GcGraph >> updateGraph [
	| gcCount fps tenurCount |

	gcCount := Smalltalk vmParameterAt: 7.
	tenurCount := Smalltalk vmParameterAt: 11.
	
	fps := self fps.
	(lastGcCount = gcCount)
		ifTrue: [
			lastTenurCount = tenurCount
				ifTrue: [
					self graph
						addValue: fps
						color: self class deepOceanColor
						bgColor: self class backgroundColor]
				ifFalse: [
					self graph
						addValue: fps
						color: self class deepOceanColor
						bgColor: self class seafoamColor.
					lastTenurCount := tenurCount]]
		ifFalse: [
			self graph
				addValue: fps
				color: self class deepOceanColor
				bgColor: self class coralColor.
			lastTenurCount := tenurCount.
			lastGcCount := gcCount].

]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:43'
}
GcGraph >> updateText [
	(self labelString, '        ') displayAt: graph position + (0 @ graph height)
			

]

{
	#category : #update,
	#'squeak_changestamp' : 'jl 10/28/2005 16:00'
}
GcGraph >> updateTime [
	| newTime |
	newTime := Time millisecondClockValue.	
	deltaTime := newTime - self lastTime.
	lastTime := newTime.
	
	


]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> usedOldSpace [
	"Live (allocated) old space, in kilobytes."
	^self oldSpace - self freeSpace
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> usedYoungSpace [
	"Bytes in use in young space (eden + survivor spaces), in kilobytes.
	On Spur vmParameterAt: 2 is a size, not the end address it was on V3."
	^(Smalltalk vmParameterAt: 2) // 1024
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> youngSpace [
	"Capacity of eden, in kilobytes. Falls back to the used amount if the VM
	does not report the eden size (parameter 44 is Cog-only)."
	^((Smalltalk vmParameterAt: 44) ifNil: [Smalltalk vmParameterAt: 2]) // 1024
]
