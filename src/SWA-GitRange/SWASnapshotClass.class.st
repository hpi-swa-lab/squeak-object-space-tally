Class {
	#name : #SWASnapshotClass,
	#superclass : #SWASnapshotBehavior,
	#instVars : [
		'snapshot',
		'fromDefinition',
		'toDefinition',
		'metaclass'
	],
	#category : #'SWA-GitRange'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> allInstVarNames [
	^ (self superclass ifNil: [#()] ifNotNil: [:class | class allInstVarNames]), self instVarNames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> category [
	^ self definition category
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> classSide [
	^ metaclass
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> comment [
	"A comment the range removed is still answered, so its node has something to show."
	| new |
	new := toDefinition ifNotNil: [:d | d comment].
	(new notNil and: [new notEmpty]) ifTrue: [^ new].
	^ fromDefinition ifNotNil: [:d | d comment]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> commentStamp [
	^ self definition commentStamp
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> definition [
	^ toDefinition ifNil: [fromDefinition]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> definition: aClassDefinition side: aSymbol [
	aSymbol == #from
		ifTrue: [fromDefinition := aClassDefinition]
		ifFalse: [toDefinition := aClassDefinition].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> instVarNames [
	"Both sides' variables, so a removed one still has a row to show it on."
	| names |
	names := OrderedCollection new.
	toDefinition ifNotNil: [:d | names addAll: d instVarNames].
	fromDefinition ifNotNil: [:d |
		d instVarNames do: [:each | (names includes: each) ifFalse: [names add: each]]].
	^ names asArray
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> isMeta [
	^ false
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> liveClass [
	^ Smalltalk classNamed: self name
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> name [
	^ self definition className asString
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> recordChangesInto: aSnapshot [
	fromDefinition isNil ifTrue: [aSnapshot record: self name kind: #added prior: nil].
	toDefinition isNil ifTrue: [aSnapshot record: self name kind: #removed prior: nil].
	(fromDefinition notNil and: [toDefinition notNil
		and: [fromDefinition definitionString ~= toDefinition definitionString]])
			ifTrue: [aSnapshot record: self name kind: #modified prior: fromDefinition definitionString].
	self recordIvarChangesInto: aSnapshot.
	self recordCommentChangesInto: aSnapshot.
	self recordMethodChangesInto: aSnapshot.
	metaclass recordMethodChangesInto: aSnapshot.
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> recordCommentChangesInto: aSnapshot [
	| old new key |
	old := fromDefinition ifNotNil: [:d | d comment ifNotNil: [:text | text asString]].
	new := toDefinition ifNotNil: [:d | d comment ifNotNil: [:text | text asString]].
	(old ifNil: ['']) = (new ifNil: ['']) ifTrue: [^ self].
	key := self name, ' (comment)'.
	(old isNil or: [old isEmpty]) ifTrue: [^ aSnapshot record: key kind: #added prior: nil].
	(new isNil or: [new isEmpty]) ifTrue: [^ aSnapshot record: key kind: #removed prior: old].
	aSnapshot record: key kind: #modified prior: old.
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> recordIvarChangesInto: aSnapshot [
	| old new |
	old := fromDefinition ifNil: [#()] ifNotNil: [:d | d instVarNames].
	new := toDefinition ifNil: [#()] ifNotNil: [:d | d instVarNames].
	new do: [:each |
		(old includes: each) ifFalse: [aSnapshot record: self name, '>>#', each kind: #added prior: nil]].
	old do: [:each |
		(new includes: each) ifFalse: [aSnapshot record: self name, '>>#', each kind: #removed prior: nil]].
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> setSnapshot: aSnapshot [
	snapshot := aSnapshot.
	metaclass := SWASnapshotMetaclass new setInstanceSide: self.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:17'
}
SWASnapshotClass >> snapshot [
	^ snapshot
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> superclass [
	^ self superclassName ifNotNil: [:name |
		(snapshot classNamed: name) ifNil: [Smalltalk classNamed: name]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> superclassName [
	^ self definition superclassName ifNotNil: [:name | name asString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWASnapshotClass >> theNonMetaClass [
	^ self
]
