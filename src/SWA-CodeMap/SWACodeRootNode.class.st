"
An aggregate code-map root whose children are SWACodePackageNodes for a chosen
set of packages. Lets you build a treemap spanning many packages (up to the whole
image) with a fluent, composable selection API based on glob patterns.

Examples:
	(SWACodeRootNode new addPackages: '*') openClassTreemap.
	((SWACodeRootNode new addPackages: '*') removePackages: 'Kernel*') openClassTreemap.
	(SWACodeRootNode new addPackages: 'Morphic*'; addPackages: 'Collections*')
		openClassTreemap.

Selection is order-independent: every #addPackages: / #removePackages: edits the
working set of PackageInfos. Glob patterns use String>>match: (e.g. 'Morphic*').

The subject is the sorted collection of selected PackageInfos; #buildChildren wraps
each in a SWACodePackageNode. As a SWACodeNode subclass it inherits LOC roll-up,
prewarming, and the treemap openers; combined with #leafKind: #class on the
treemap you get a packages -> classes view (no methods) sized by LOC.
"
Class {
	#name : #SWACodeRootNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'packages',
		'displayName'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> addPackages: aGlobOrName [
	"Add every package whose name matches aGlobOrName (a String>>match: glob, e.g.
	'Morphic*' or '*'). Returns self for chaining. Re-invalidates built children."
	| matches |
	matches := self allPackageInfos select: [:p | aGlobOrName match: p packageName].
	matches do: [:p | (packages includes: p) ifFalse: [packages add: p]].
	children := nil.
	^ self
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> allPackageInfos [
	"Every PackageInfo in the image."
	^ PackageInfo allPackages
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> buildChildren [
	"One SWACodePackageNode per selected package, sorted by name."
	| sorted |
	sorted := packages asSortedCollection: [:a :b | a packageName <= b packageName].
	^ (sorted collect: [:pkg | SWACodePackageNode on: pkg parent: self]) asOrderedCollection
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> estimatedNodeCount [
	"Cheap estimate: sum of selected packages' class counts (+1 per package + self),
	without forcing source/LOC."
	^ 1 + (packages inject: 0 into: [:s :p | s + 1 + p classes size])
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> initialize [
	super initialize.
	packages := OrderedCollection new.
	displayName := 'All Code'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> kind [
	^ #root
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> name [
	^ displayName, ' (', packages size printString, ' packages)'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> name: aString [
	"Set the display label for this aggregate root. Returns self for chaining."
	displayName := aString.
	^ self
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:08'
}
SWACodeRootNode >> removePackages: aGlobOrName [
	"Remove every currently-selected package whose name matches aGlobOrName (a
	String>>match: glob, e.g. 'Kernel*'). Returns self for chaining."
	packages := packages reject: [:p | aGlobOrName match: p packageName].
	children := nil.
	^ self
]
