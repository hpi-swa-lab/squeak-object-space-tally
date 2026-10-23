Class {
	#name : #SWACodeLinearViewTest,
	#superclass : #TestCase,
	#instVars : [
		'view'
	],
	#category : #'SWA-Tests'
}

{
	#category : #support,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> codeRowNames [
	^ ((view instVarNamed: 'content') allMorphs
		select: [:each | each isKindOf: SWALinearCodeMorph])
		collect: [:each | each node name]
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> setUp [
	view := SWACodeLinearView new.
	view setRoot: (SWACodeRootNode new addPackages: 'SWA-Widgets'; yourself).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> testANodeTheTreeNoLongerHoldsGetsNoRowAndNoLoop [
	| stale |
	stale := view keyIndex at: 'SWASplitter>>resizeAction:'.
	stale parent forgetChildren.
	view codeChanged.
	view selectedNode: stale.
	self assert: (view instVarNamed: 'selectedRow') isNil.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> testDepthMShowsNoSource [
	view leafKind: #method.
	self assert: self codeRowNames isEmpty.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> testDepthSShowsEverySource [
	self assert: (self codeRowNames includes: 'resizeAction:').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> testSelectingInsideACollapsedNodeExpandsToIt [
	view leafKind: #class.
	self deny: (self codeRowNames includes: 'resizeAction:').
	view leafKind: #source.
	view toggle: (view keyIndex at: 'SWASplitter') event: nil from: nil.
	self deny: (self codeRowNames includes: 'resizeAction:').
	view selectNodeForKey: 'SWASplitter>>resizeAction:'.
	self assert: (self codeRowNames includes: 'resizeAction:').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:31'
}
SWACodeLinearViewTest >> testZoomIsAClassOrPackage [
	view zoomInto: (view keyIndex at: 'SWASplitter>>resizeAction:').
	self assert: #class -> 'SWASplitter' equals: view currentFocus.
	view zoomOut.
	self assert: view currentFocus ~= (#class -> 'SWASplitter').
]
