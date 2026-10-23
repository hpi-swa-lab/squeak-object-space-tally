Class {
	#name : #SWACodeSnapshotRootNode,
	#superclass : #SWACodeRootNode,
	#instVars : [
		'snapshot'
	],
	#category : #'SWA-GitRange'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshotRootNode >> allPackageInfos [
	^ snapshot packages
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshotRootNode >> name [
	^ super name, ' @ ', snapshot rangeLabel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshotRootNode >> snapshot [
	^ snapshot
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshotRootNode >> snapshot: aCodeSnapshot [
	snapshot := aCodeSnapshot.
	children := nil.
]
