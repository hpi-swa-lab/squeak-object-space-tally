Class {
	#name : #SWASnapshotOrganizer,
	#superclass : #Object,
	#instVars : [
		'behavior'
	],
	#category : #'SWA-GitRange'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer class >> on: aSnapshotBehavior [
	^ self new setBehavior: aSnapshotBehavior
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer >> categories [
	^ (behavior methodDictionary values collect: [:each | each category asSymbol]) asSet
		asSortedCollection asArray
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer >> categoryOfElement: aSelector [
	^ (behavior methodDictionary at: aSelector ifAbsent: [nil])
		ifNotNil: [:method | method category asSymbol]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer >> classComment [
	^ behavior theNonMetaClass comment
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer >> commentStamp [
	^ behavior theNonMetaClass commentStamp
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer >> listAtCategoryNamed: aCategory [
	^ ((behavior methodDictionary values select: [:each | each category asString = aCategory asString])
		collect: [:each | each selector]) asSortedCollection asArray
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotOrganizer >> setBehavior: aSnapshotBehavior [
	behavior := aSnapshotBehavior.
]
