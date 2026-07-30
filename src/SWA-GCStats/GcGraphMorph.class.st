Class {
	#name : #GcGraphMorph,
	#superclass : #Morph,
	#instVars : [
		'graph',
		'fullGraph'
	],
	#category : #'SWA-GCStats'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:44'
}
GcGraphMorph >> drawOn: aCanvas [

	| font |
	aCanvas paintImage: graph form at: self topLeft.
	aCanvas paintImage: fullGraph form at: self topLeft + (0 @ graph form height).

	font := TextStyle defaultFont.
	aCanvas
		drawString: graph labelString
		at: self topLeft + (2 @ 1) font: font color: Color black.
	aCanvas
		drawString: fullGraph labelString
		at: self topLeft + (2 @ (graph form height + 1)) font: font color: Color black
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2006 10:46'
}
GcGraphMorph >> extent: aPoint [
	super extent: aPoint.
	graph extent: aPoint // (1@2).
	fullGraph extent: aPoint // (1@2)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2006 10:33'
}
GcGraphMorph >> initialize [
	super initialize.
	graph := GcGraph new.
	fullGraph := GcFullGraph new.

	self extent: 400@400.
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2006 10:46'
}
GcGraphMorph >> position: aPoint [
	super position: aPoint.
	graph graph position: aPoint.
	fullGraph graph position: aPoint + (0@ graph form height)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2006 10:59'
}
GcGraphMorph >> step [
	self changed.
	graph updateTime.
	graph updateGraph.
	fullGraph updateGraph
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2006 10:20'
}
GcGraphMorph >> stepTime [
	^1
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2006 10:20'
}
GcGraphMorph >> wantsSteps [ 
	^true
]
