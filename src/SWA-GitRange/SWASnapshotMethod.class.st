Class {
	#name : #SWASnapshotMethod,
	#superclass : #Object,
	#instVars : [
		'behavior',
		'selector',
		'fromDefinition',
		'toDefinition'
	],
	#category : #'SWA-GitRange'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> actualClass [
	^ behavior
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> browse [
	behavior liveClass ifNotNil: [:class |
		(class includesSelector: selector) ifTrue: [^ ToolSet browse: class selector: selector]].
	(StringHolder new contents: self source)
		openLabel: behavior name, '>>', selector, ' (from git)'.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> category [
	^ self definition category
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> compiledMethod [
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> definition [
	^ toDefinition ifNil: [fromDefinition]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> definition: aMethodDefinition side: aSymbol [
	aSymbol == #from
		ifTrue: [fromDefinition := aMethodDefinition]
		ifFalse: [toDefinition := aMethodDefinition].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> methodNode [
	^ self error: 'a method from git is not compiled'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> methodReference [
	^ self
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> printOn: aStream [
	aStream nextPutAll: behavior name; nextPutAll: '>>'; nextPutAll: selector.
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> recordChangesInto: aSnapshot [
	| key old |
	key := behavior name, '>>', selector.
	fromDefinition isNil ifTrue: [^ aSnapshot record: key kind: #added prior: nil].
	old := fromDefinition source asString.
	toDefinition isNil ifTrue: [^ aSnapshot record: key kind: #removed prior: old].
	old = toDefinition source asString ifTrue: [^ self].
	aSnapshot record: key kind: #modified prior: old.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> selector [
	^ selector
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> setBehavior: aSnapshotBehavior selector: aSelector [
	behavior := aSnapshotBehavior.
	selector := aSelector.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> source [
	^ self definition source asString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotMethod >> timeStamp [
	^ self definition timeStamp
]
