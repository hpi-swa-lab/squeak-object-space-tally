Class {
	#name : #SWASnapshotMetaclass,
	#superclass : #SWASnapshotBehavior,
	#instVars : [
		'instanceSide'
	],
	#category : #'SWA-GitRange'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> allInstVarNames [
	^ self instVarNames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> category [
	^ instanceSide category
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> classSide [
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> comment [
	^ instanceSide comment
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> commentStamp [
	^ instanceSide commentStamp
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> instVarNames [
	^ instanceSide definition classInstVarNames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> isMeta [
	^ true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> liveClass [
	^ instanceSide liveClass ifNotNil: [:class | class classSide]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> name [
	^ instanceSide name, ' class'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> setInstanceSide: aSnapshotClass [
	instanceSide := aSnapshotClass.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:17'
}
SWASnapshotMetaclass >> snapshot [
	^ instanceSide snapshot
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> superclass [
	^ instanceSide superclass ifNotNil: [:class | class classSide]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMetaclass >> theNonMetaClass [
	^ instanceSide
]
