Class {
	#name : #SWASnapshotPackage,
	#superclass : #Object,
	#instVars : [
		'name',
		'classes'
	],
	#category : #'SWA-GitRange'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage class >> named: aString [
	^ self new setName: aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> addClass: aSnapshotClass [
	classes add: aSnapshotClass.
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> browse [
	(PackageInfo allPackages detect: [:each | each packageName = name] ifNone: [nil])
		ifNotNil: [:info | info browse].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> classes [
	^ classes
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> packageName [
	^ name
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> printOn: aStream [
	aStream nextPutAll: name; nextPutAll: ' (snapshot)'.
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> setName: aString [
	name := aString.
	classes := OrderedCollection new.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> systemCategories [
	^ (classes collect: [:each | each category asString]) asSet asSortedCollection asArray
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotPackage >> systemCategoryPrefix [
	^ name
]
