Class {
	#name : #SWASelectionContextTest,
	#superclass : #TestCase,
	#category : #'SWA-Tests'
}

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> contextOn: aSelector [
	^ (SWASelectionContext onAll: {self class name, '>>', aSelector} hops: 1 includesTests: true)
		scope: {self class name asString. 'SWAMarkSet'} asSet;
		compute;
		yourself
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> fixtureSendsThroughATemp [
	| marks |
	marks := SWAMarkSet new.
	^ marks keys
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> fixtureSendsToANewInstance [
	^ SWAMarkSet new keys
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> fixtureSendsToAnUntypedArgument: anObject [
	^ anObject keys
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> fixtureSendsToSelf [
	^ self fixtureSendsToANewInstance
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:44'
}
SWASelectionContextTest >> testAClassBringsItsMethodsAsAnchors [
	| keys |
	keys := SWASelectionContext withMembers: self class name asString.
	self assert: keys first = self class name asString.
	self assert: (keys includes: self class name, '>>fixtureSendsToSelf').
	self assert: (SWASelectionContext withMembers: self class name, '>>fixtureSendsToSelf') size = 1.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> testAClassOutsideTheScopeIsLeftOut [
	| context |
	context := (SWASelectionContext onAll: {self class name, '>>fixtureSendsToANewInstance'} hops: 1 includesTests: true)
		scope: {self class name asString} asSet;
		compute;
		yourself.
	self deny: (context includesClassNamed: 'SWAMarkSet').
	self assert: context classEdges isEmpty.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> testASendToSelfGivesNoCallee [
	| callees |
	callees := (self contextOn: #fixtureSendsToSelf)
		calleesOfMethod: self class >> #fixtureSendsToSelf.
	self assert: callees isEmpty.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> testATempIsTypedByWhatIsAssignedToIt [
	| callees |
	callees := (self contextOn: #fixtureSendsThroughATemp)
		calleesOfMethod: self class >> #fixtureSendsThroughATemp.
	self assert: (callees includesKey: 'SWAMarkSet>>keys').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> testAnInstanceCreationTypesTheReceiver [
	| callees |
	callees := (self contextOn: #fixtureSendsToANewInstance)
		calleesOfMethod: self class >> #fixtureSendsToANewInstance.
	self assert: (callees at: 'SWAMarkSet>>keys') = 'SWAMarkSet'.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:55'
}
SWASelectionContextTest >> testAnUntypedReceiverGivesNoCallee [
	| callees |
	callees := (self contextOn: #fixtureSendsToAnUntypedArgument:)
		calleesOfMethod: self class >> #fixtureSendsToAnUntypedArgument:.
	self assert: callees isEmpty.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:29'
}
SWASelectionContextTest >> testTheArrowRunsFromTheUserToWhatItUses [
	self
		assert: (self contextOn: #fixtureSendsToANewInstance) classEdges asArray
		equals: {{self class name asString. 'SWAMarkSet'. #callee. 'new, calls keys'}}.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:38'
}
SWASelectionContextTest >> testTheClassOfAnAnchorIsShownWhole [
	| context |
	context := self contextOn: #fixtureSendsToANewInstance.
	self assert: (context showsMember: self class name, '>>fixtureSendsToSelf').
	self assert: (context showsMember: 'SWAMarkSet>>keys').
	self deny: (context showsMember: 'SWAMarkSet>>add:').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:29'
}
SWASelectionContextTest >> testTheLabelSaysHowTheClassIsUsed [
	self
		assert: ((self contextOn: #fixtureSendsThroughATemp) classEdges detect: [:each | each second = 'SWAMarkSet']) fourth
		equals: 'new, calls keys'.
]
