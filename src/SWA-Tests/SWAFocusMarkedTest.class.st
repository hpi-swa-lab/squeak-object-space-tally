Class {
	#name : #SWAFocusMarkedTest,
	#superclass : #TestCase,
	#instVars : [
		'map'
	],
	#category : #'SWA-Tests'
}

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> classNode [

	map rootNode withAllChildrenDo: [:each | each kind == #class ifTrue: [^ each]].
	^ nil
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> mark: nodes [
	"Bypasses SWAMarkSet default, which holds the user's own marks."

	map instVarNamed: 'markedNodesCache' put: (IdentitySet withAll: nodes).
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> methodsOf: aClassNode [

	| methods |
	methods := OrderedCollection new.
	aClassNode withAllChildrenDo: [:each | each kind == #method ifTrue: [methods add: each]].
	^ methods
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> setUp [

	map := SWACodeTreemapMorph new.
	map setRoot: (SWACodeRootNode new addPackages: 'SWA-Widgets'; yourself).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testAMarkedClassKeepsAllItsMembers [

	self mark: {self classNode}.
	map toggleFocusMarked.
	(self methodsOf: self classNode) do: [:each | self deny: (map isFocusDimmed: each)].
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testAMarkedMethodKeepsItsAncestorsAndDimsItsSiblings [

	| methods |
	methods := self methodsOf: self classNode.
	self mark: {methods first}.
	map toggleFocusMarked.
	self deny: (map isFocusDimmed: methods first).
	self deny: (map isFocusDimmed: self classNode).
	self deny: (map isFocusDimmed: map rootNode).
	self assert: (map isFocusDimmed: methods second).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testAnotherViewTakesTheFocusOver [

	| browser |
	map toggleFocusMarked.
	browser := SWACodeBrowser new.
	browser takeOverFrom: map.
	self assert: browser focusMarked.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testChangingTheMarksRebuildsTheFocus [

	| methods |
	methods := self methodsOf: self classNode.
	self mark: {methods first}.
	map toggleFocusMarked.
	self assert: (map isFocusDimmed: methods second).
	map flushMarksCache.
	self mark: {methods second}.
	self deny: (map isFocusDimmed: methods second).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testFocusDimsTheTileColourRatherThanReplacingIt [

	| methods |
	methods := self methodsOf: self classNode.
	self mark: {methods first}.
	map toggleFocusMarked.
	self assert: (map intrinsicColorForNode: methods first) equals: (map colorForNode: methods first).
	self
		assert: ((map intrinsicColorForNode: methods second) alphaMixed: 0.22 with: (Color gray: 0.1))
		equals: (map colorForNode: methods second).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testMarkedMembersWinOverTheirMarkedClass [

	| methods |
	methods := self methodsOf: self classNode.
	self mark: {self classNode. methods first}.
	map toggleFocusMarked.
	self deny: (map isFocusDimmed: methods first).
	self assert: (map isFocusDimmed: methods second).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testNothingIsDimmedWhileFocusIsOff [

	self mark: {(self methodsOf: self classNode) first}.
	map rootNode withAllChildrenDo: [:each | self deny: (map isFocusDimmed: each)].
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:10'
}
SWAFocusMarkedTest >> testTheMarkFrameIsOutlined [

	| form |
	form := Form extent: 20 @ 20 depth: 32.
	form fillColor: Color green.
	SWASelectionPainter markFrameOn: form getCanvas rect: form boundingBox.
	self assert: Color black equals: (form colorAt: 0 @ 10).
	self assert: ((form colorAt: 1 @ 10) diff: SWASelectionPainter markColor) < 0.01.
	self assert: ((form colorAt: 2 @ 10) diff: SWASelectionPainter markColor) < 0.01.
	self assert: Color green equals: (form colorAt: 3 @ 10).
]
