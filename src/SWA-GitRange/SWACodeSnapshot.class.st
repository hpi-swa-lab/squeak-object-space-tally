"
The code of a repository's packages at two commits, merged into one set of stand-in classes, so the code views can show what the image no longer has. Change kinds are worked out from the two sets of definitions alone.
"
Class {
	#name : #SWACodeSnapshot,
	#superclass : #Object,
	#instVars : [
		'repositoryName',
		'fromHex',
		'toHex',
		'packageNames',
		'packagesByName',
		'classesByName',
		'kinds',
		'priorSources',
		'marks',
		'packagePaths',
		'classPackages'
	],
	#category : #'SWA-GitRange',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot class >> repository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil packages: aCollectionOrNil [
	"A nil To means the head commit, a nil package list every code package in the repository."
	^ self new
		setRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil packages: aCollectionOrNil;
		load;
		yourself
]

{
	#category : #loading,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> addSnapshots: aDictionary side: aSymbol [
	"All classes before any method, since a method may come from another package than
	its class. Extension methods of classes outside the snapshot have no class here."
	aDictionary keysAndValuesDo: [:packageName :mcSnapshot |
		mcSnapshot definitions do: [:each |
			each isClassDefinition ifTrue: [
				(self classNamed: each className asString inPackage: packageName)
					definition: each side: aSymbol]]].
	aDictionary do: [:mcSnapshot |
		mcSnapshot definitions do: [:each |
			each isMethodDefinition ifTrue: [
				(classesByName at: each className asString ifAbsent: [nil]) ifNotNil: [:cls |
					(each classIsMeta ifTrue: [cls classSide] ifFalse: [cls])
						addDefinition: each side: aSymbol]]]].
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:06'
}
SWACodeSnapshot >> changes [
	"What SWAView>>loadGitRange hands to #showGitChanges:."
	^ Dictionary new
		at: #marks put: self marks;
		at: #kinds put: kinds;
		at: #priorSources put: priorSources;
		at: #snapshot put: self;
		yourself
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWACodeSnapshot >> classFilePathFor: aKey [
	"Where the class of a member key lives in the repository, as Tonel writes it."
	| class package |
	class := (self classNamed: (self classNameOfKey: aKey)) ifNil: [^ nil].
	package := classPackages at: class name ifAbsent: [^ nil].
	^ (packagePaths at: package ifAbsent: [^ nil]) / (class name, '.class.st')
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWACodeSnapshot >> classNameOfKey: aKey [
	"'Foo>>bar', 'Foo class>>bar', 'Foo>>#ivar', 'Foo (comment)' and 'Foo' all name Foo."
	| name |
	name := (aKey includesSubstring: '>>') ifTrue: [aKey copyUpTo: $>] ifFalse: [aKey].
	(name endsWith: ' (comment)') ifTrue: [name := name allButLast: 10].
	(name endsWith: ' class') ifTrue: [name := name allButLast: 6].
	^ name
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> classNamed: aString [
	"Also takes the class-side and comment forms of a key, 'Foo class' and 'Foo (comment)'."
	| name |
	name := aString asString.
	(name endsWith: ' class') ifTrue: [name := name allButLast: 6].
	(name endsWith: ' (comment)') ifTrue: [name := name allButLast: 10].
	^ classesByName at: name ifAbsent: [nil]
]

{
	#category : #loading,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWACodeSnapshot >> classNamed: aClassName inPackage: aPackageName [
	^ classesByName at: aClassName ifAbsent: [ | cls |
		cls := SWASnapshotClass new setSnapshot: self.
		classPackages at: aClassName put: aPackageName.
		(packagesByName at: aPackageName ifAbsentPut: [SWASnapshotPackage named: aPackageName])
			addClass: cls.
		classesByName at: aClassName put: cls]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> kinds [
	^ kinds
]

{
	#category : #loading,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWACodeSnapshot >> load [
	| history base head fromSnapshots toSnapshots |
	history := SWAGitHistory onWorkingCopyNamed: repositoryName.
	base := history commitNamed: fromHex.
	base ifNil: [^ self error: 'no commit or branch ', fromHex, ' in ', repositoryName].
	head := toHex
		ifNil: [history workingCopy headCommit]
		ifNotNil: [:prefix |
			(history commitNamed: prefix)
				ifNil: [^ self error: 'no commit or branch ', prefix, ' in ', repositoryName]].
	UIManager default
		informUser: 'Loading ', self rangeLabel
		during: [
			fromSnapshots := self snapshotsAt: base in: history workingCopy.
			toSnapshots := self snapshotsAt: head in: history workingCopy].
	"The To side first, so a class that moved package is filed where it is now."
	self addSnapshots: toSnapshots side: #to.
	self addSnapshots: fromSnapshots side: #from.
	classesByName do: [:each | each recordChangesInto: self].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:06'
}
SWACodeSnapshot >> marks [
	^ marks ifNil: [marks := SWAMarkSet new addAll: kinds keys; yourself]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> packages [
	^ packagesByName values asSortedCollection: [:a :b | a packageName <= b packageName]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> priorSources [
	^ priorSources
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> rangeLabel [
	^ repositoryName, ' ', (fromHex first: (fromHex size min: 7)), '..',
		(toHex ifNil: ['HEAD'] ifNotNil: [:hex | hex first: (hex size min: 7)])
]

{
	#category : #changes,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:06'
}
SWACodeSnapshot >> record: aKey kind: aSymbol prior: aStringOrNil [
	kinds at: aKey put: aSymbol.
	aStringOrNil ifNotNil: [priorSources at: aKey put: aStringOrNil].
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWACodeSnapshot >> setRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil packages: aCollectionOrNil [
	repositoryName := aRepositoryName.
	fromHex := aHexPrefix.
	toHex := aHexPrefixOrNil.
	packageNames := aCollectionOrNil ifNotNil: [:names | names asSet].
	packagesByName := Dictionary new.
	classesByName := Dictionary new.
	kinds := Dictionary new.
	priorSources := Dictionary new.
	packagePaths := Dictionary new.
	classPackages := Dictionary new.
]

{
	#category : #loading,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWACodeSnapshot >> snapshotsAt: aCommit in: aWorkingCopy [
	"packageName -> MCSnapshot of every wanted code package at aCommit."
	| fileSystem metadata result |
	fileSystem := (aWorkingCopy fsCommitFrom: aCommit) filesystem.
	metadata := aWorkingCopy metadataMapper loadMetadataFromFileSystem: fileSystem in: aWorkingCopy.
	result := Dictionary new.
	metadata mappers do: [:mapper |
		((mapper isKindOf: GSCodeMapper) and: [self wantsPackageNamed: mapper package name])
			ifTrue: [
				packagePaths at: mapper package name put: (mapper packageDirectoryIn: fileSystem) path.
				result at: mapper package name put: (mapper loadSnapshotFrom: fileSystem)]].
	^ result
]

{
	#category : #loading,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:04'
}
SWACodeSnapshot >> wantsPackageNamed: aString [
	^ packageNames isNil or: [packageNames includes: aString]
]
