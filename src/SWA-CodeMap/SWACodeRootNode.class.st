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
		'displayName',
		'categoryOwners',
		'packageParents'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 10:02'
}
SWACodeRootNode >> addPackages: aGlobOrName [
	"Add every package whose name matches aGlobOrName (a String>>match: glob, e.g.
	'Morphic*' or '*'). Returns self for chaining. Re-invalidates built children,
	the category-owner map, and the package-nesting map."
	| matches |
	matches := self allPackageInfos select: [:p | aGlobOrName match: p packageName].
	matches do: [:p | (packages includes: p) ifFalse: [packages add: p]].
	children := nil.
	categoryOwners := nil.
	packageParents := nil.
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 10:00'
}
SWACodeRootNode >> buildChildren [
	"One SWACodePackageNode per TOP-LEVEL selected package (those with no selected
	parent package). Sub-packages are nested under their parent by
	SWACodePackageNode>>buildChildren, so e.g. 'Graphics-Fonts' becomes a child of
	'Graphics' rather than a sibling. Sorted by name."
	^ ((self childPackageInfosOf: nil)
		collect: [:pkg | SWACodePackageNode on: pkg parent: self]) asOrderedCollection
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 10:00'
}
SWACodeRootNode >> childPackageInfosOf: aPackageInfoOrNil [
	"Answer the selected PackageInfos whose immediate selected parent is
	aPackageInfoOrNil. Pass nil for the top-level packages (the root's own
	children). Sorted by package name."
	^ (packages select: [:p |
		(self packageParents at: p ifAbsent: [nil]) == aPackageInfoOrNil])
		asSortedCollection: [:a :b | a packageName <= b packageName]
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 09:56'
}
SWACodeRootNode >> ownerOfSystemCategory: aCategory [
	"Answer the single selected package that owns aCategory, resolving the
	PackageInfo prefix-overlap problem (e.g. category 'Graphics-Fonts' matches
	BOTH the 'Graphics' and 'Graphics-Fonts' package prefixes). The most-specific
	package -- the one with the longest matching systemCategoryPrefix -- wins, so a
	class is attributed to exactly one package. Resolution is confined to the
	currently selected packages: if a more-specific sub-package is not part of this
	view, the broader parent legitimately keeps the class.

	Memoized in categoryOwners (category -> owning package), rebuilt lazily and
	invalidated by addPackages:/removePackages:."
	categoryOwners ifNil: [
		categoryOwners := Dictionary new.
		packages do: [:pkg |
			pkg systemCategories do: [:cat |
				| current |
				current := categoryOwners at: cat ifAbsent: [nil].
				(current isNil or: [pkg systemCategoryPrefix size > current systemCategoryPrefix size])
					ifTrue: [categoryOwners at: cat put: pkg]]]].
	^ categoryOwners at: aCategory ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:37'
}
SWACodeRootNode >> packageNames [
	"The names of the packages this code map is showing."
	^ packages collect: [:p | p packageName]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 10:00'
}
SWACodeRootNode >> packageParents [
	"Memoized map: selected PackageInfo -> its immediate selected PARENT PackageInfo
	(or nil when top-level). The parent is the selected package whose name is the
	longest proper prefix of this package's name on a '-' boundary -- e.g.
	'Graphics-Fonts' -> 'Graphics', 'GitS-Core-Rebase' -> 'GitS-Core' (NOT 'GitS',
	since the more-specific 'GitS-Core' is also selected). Packages with a '-' but no
	matching selected ancestor (e.g. 'FS-Core' with no 'FS' package) stay top-level.

	Invalidated by addPackages:/removePackages:."
	packageParents ifNil: [
		| byName |
		packageParents := Dictionary new.
		byName := Dictionary new.
		packages do: [:p | byName at: p packageName put: p].
		packages do: [:p |
			| name parent idx |
			name := p packageName.
			parent := nil.
			"Scan right-to-left for the longest selected prefix ending at a '-'."
			idx := name size.
			[parent isNil and: [idx > 1]] whileTrue: [
				(name at: idx) = $- ifTrue: [
					| cand |
					cand := name copyFrom: 1 to: idx - 1.
					parent := byName at: cand ifAbsent: [nil]].
				idx := idx - 1].
			parent ifNotNil: [packageParents at: p put: parent]]].
	^ packageParents
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 10:02'
}
SWACodeRootNode >> removePackages: aGlobOrName [
	"Remove every currently-selected package whose name matches aGlobOrName (a
	String>>match: glob, e.g. 'Kernel*'). Returns self for chaining."
	packages := packages reject: [:p | aGlobOrName match: p packageName].
	children := nil.
	categoryOwners := nil.
	packageParents := nil.
	^ self
]
