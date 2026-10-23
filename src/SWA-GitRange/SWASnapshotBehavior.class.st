"
Answers the part of the Behavior protocol the SWACode nodes use, so they can tile code that is not in the image. Not a Behavior: tools that need a real class (Shout, the browser) go through #liveClass.
"
Class {
	#name : #SWASnapshotBehavior,
	#superclass : #Object,
	#instVars : [
		'methods'
	],
	#category : #'SWA-GitRange',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> >> aSelector [
	^ self methodDictionary at: aSelector
]

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> addDefinition: aMethodDefinition side: aSymbol [
	(self methodDictionary
		at: aMethodDefinition selector
		ifAbsentPut: [SWASnapshotMethod new setBehavior: self selector: aMethodDefinition selector])
			definition: aMethodDefinition side: aSymbol.
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> browse [
	self liveClass
		ifNil: [self inform: self name, ' is not in the image']
		ifNotNil: [:cls | ToolSet browseClass: cls].
]

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> includesSelector: aSelector [
	^ self methodDictionary includesKey: aSelector
]

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> methodDictionary [
	^ methods ifNil: [methods := Dictionary new]
]

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> organization [
	^ SWASnapshotOrganizer on: self
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> printOn: aStream [
	aStream nextPutAll: self name.
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> recordMethodChangesInto: aSnapshot [
	self methodDictionary do: [:each | each recordChangesInto: aSnapshot].
]

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotBehavior >> selectors [
	^ self methodDictionary keys
]

{
	#category : #methods,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:17'
}
SWASnapshotBehavior >> sourceCodeAt: aSelector [
	^ (self >> aSelector) source
]
