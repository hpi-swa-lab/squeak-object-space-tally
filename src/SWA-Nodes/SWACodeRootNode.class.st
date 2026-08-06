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
		'packageParents',
		'classFilter'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #scope,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:45'
}
SWACodeRootNode class >> globsFrom: aGlobOrList [
	"Normalize a package scope into an Array of individual String>>match: globs.
	Accepts a single glob String ('Morphic*', '*'), a COMMA-SEPARATED list of globs
	in one String ('Raylib, SqueakXR, SWAGame' -- the working-set form stored in
	SWAPane class>>codeMapWorkingSet), or an already-split collection of globs.
	Blank entries are dropped, so a trailing comma is harmless.

	(SWACodeRootNode globsFrom: 'Raylib, SqueakXR') --> #('Raylib' 'SqueakXR')"
	aGlobOrList isString ifFalse: [^ aGlobOrList asArray].
	^ (((aGlobOrList findTokens: ',') collect: [:s | s withBlanksTrimmed])
		reject: [:s | s isEmpty]) asArray
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:45'
}
SWACodeRootNode >> addPackages: aGlobOrList [
	"Add every package whose name matches aGlobOrList. That is a String>>match: glob
	(e.g. 'Morphic*' or '*'), a COMMA-SEPARATED list of such globs ('Raylib, SqueakXR,
	SWAGame' -- the working-set form stored in SWAPane class>>codeMapWorkingSet), or an
	already-split collection of globs. Returns self for chaining. Re-invalidates built
	children, the category-owner map, and the package-nesting map."
	| matches globs |
	globs := self class globsFrom: aGlobOrList.
	matches := self allPackageInfos select: [:p |
		globs anySatisfy: [:g | g match: p packageName]].
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:31'
}
SWACodeRootNode >> buildChildren [
	"One SWACodePackageNode per TOP-LEVEL selected package (those with no selected
	parent package). Sub-packages are nested under their parent by
	SWACodePackageNode>>buildChildren, so e.g. 'Graphics-Fonts' becomes a child of
	'Graphics' rather than a sibling. Sorted by name."
	| nodes |
	nodes := ((self childPackageInfosOf: nil)
		collect: [:pkg | SWACodePackageNode on: pkg parent: self]) asOrderedCollection.
	"See #classFilter:: a selected package none of whose classes survive the filter
	is dropped rather than tiled as an empty header."
	self hasClassFilter ifTrue: [nodes := nodes select: [:n | n children notEmpty]].
	^ nodes
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:30'
}
SWACodeRootNode >> classFilter: aBlockOrCollectionOrNil [
	"Narrow the map to a SUBSET OF CLASSES inside the selected packages. Selecting
	whole packages is too coarse when the interesting set is 'what one session
	touched': one edited method drags in its entire package, so the reading you came
	for is a handful of tiles lost in thousands of neighbours.

	The filter takes a class and answers whether to tile it -- pass a one-arg block,
	or any collection of classes (turned into a Set membership test), or nil for no
	filtering. TOUCHED CLASSES ARE ADMITTED WHOLE: every method of an included class
	is tiled, so the untouched siblings of an edited method still read as its
	context. It is only the classes nobody touched that disappear."
	classFilter := aBlockOrCollectionOrNil isNil
		ifTrue: [nil]
		ifFalse: [aBlockOrCollectionOrNil isCollection
			ifTrue: [[:cls | aBlockOrCollectionOrNil includes: cls]]
			ifFalse: [aBlockOrCollectionOrNil]].
	children := nil.
	categoryOwners := nil.
	packageParents := nil.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:44'
}
SWACodeRootNode >> displayName [
	"The raw scope label this aggregate root was built from -- for code roots this is the
	package GLOB passed to SWAPane open* ('Kernel', 'Morphic*', '*'). Distinct from #name,
	which decorates it with the package count. Used to record a respawnable scope in mark
	provenance."
	^ displayName
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:31'
}
SWACodeRootNode >> estimatedNodeCount [
	"Cheap estimate: sum of selected packages' class counts (+1 per package + self),
	without forcing source/LOC."
	^ 1 + (packages inject: 0 into: [:s :p |
		s + 1 + (p classes count: [:cls | self includesClass: cls])])
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:31'
}
SWACodeRootNode >> hasClassFilter [
	"Is a subset-of-classes filter active? Package nodes prune themselves when empty
	only in that case -- without a filter no package can be empty, and the pruning
	check would force every package's children to be built up front."
	^ classFilter notNil
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:30'
}
SWACodeRootNode >> includesClass: aClass [
	"Should aClass be tiled? See #classFilter: -- no filter means every class in the
	selected packages."
	^ classFilter isNil or: [classFilter value: aClass]
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:45'
}
SWACodeRootNode >> removePackages: aGlobOrList [
	"Remove every currently-selected package whose name matches aGlobOrList: a
	String>>match: glob (e.g. 'Kernel*'), a COMMA-SEPARATED list of such globs, or a
	collection of globs. 'removePackages: ''*''' empties the scope. Returns self for
	chaining."
	| globs |
	globs := self class globsFrom: aGlobOrList.
	packages := packages reject: [:p |
		globs anySatisfy: [:g | g match: p packageName]].
	children := nil.
	categoryOwners := nil.
	packageParents := nil.
	^ self
]
