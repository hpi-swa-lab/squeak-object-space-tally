"
A node in the time-bucketed view of a .changes file.

I represent one level of a temporal hierarchy built from a Squeak changes file:

  root -> year -> month -> week -> day -> save -> change(leaf)

My #kind is one of: #root #year #month #week #day #save #change.

Leaf nodes (#kind = #change) wrap a single ChangeRecord: a method definition,
a doIt, a class definition, a class comment, or a method removal. They carry the
change's source text (for the Show pane), its #changeType (#method/#doIt/
#classDefinition/#classComment/#methodRemoval/#misc), and its LOC.

Container nodes roll up LOC (the treemap weight, so busier days/saves get bigger
tiles) and change count from their descendants. #save nodes correspond to a
----SNAPSHOT----/----QUIT----/----STARTUP---- boundary in the changes file and
carry that boundary's timestamp.

See SWAChangeParser for construction and SWAChangeTreemapMorph for the view.
"
Class {
	#name : #SWAChangeNode,
	#superclass : #SWANode,
	#instVars : [
		'kind',
		'label',
		'timeStamp',
		'changeType',
		'methodClassName',
		'methodSelector',
		'sourceText',
		'loc',
		'totalLocCache',
		'childCountCache',
		'author',
		'statusCache',
		'statusFinal',
		'priorSource',
		'diffLinesCache',
		'prevInScope'
	],
	#category : #'SWA-ChangeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:37'
}
SWAChangeNode >> appearsInVersionHistoryOf: aClass selector: aSelector [
	"Does this change's exact source appear among the method's logged versions
	(sources + changes files)? Compared trimmed. Guarded against errors."
	| mySrc versions |
	mySrc := (sourceText ifNil: ['']) withBlanksTrimmed.
	mySrc isEmpty ifTrue: [^ false].
	versions := [(VersionsBrowser new
		scanVersionsOf: (aClass compiledMethodAt: aSelector ifAbsent: [^ false])
		class: aClass
		meta: aClass isMeta
		category: nil
		selector: aSelector) changeList]
		on: Error do: [:e | ^ false].
	versions ifNil: [^ false].
	^ versions anySatisfy: [:cr |
		([cr string asString withBlanksTrimmed = mySrc] on: Error do: [:e | false])]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:36'
}
SWAChangeNode >> author [
	"The author initials/name for this change (from its stamp), or nil."
	^ author
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:36'
}
SWAChangeNode >> author: aString [
	author := aString
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:05'
}
SWAChangeNode >> baselineSource [
	"The source to diff THIS change against: the previous version of the same
	method WITHIN the change set we are viewing, if one exists in scope; otherwise
	the last version in the image before this change (the #priorSource pointer).
	Answer nil when neither exists (a genuinely first-seen method)."
	prevInScope ifNotNil: [:p | ^ p sourceText ifNil: ['']].
	^ priorSource
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> changeCount [
	"Number of leaf changes in this subtree (a leaf counts as 1)."
	self isLeaf ifTrue: [^ 1].
	childCountCache ifNotNil: [^ childCountCache].
	^ childCountCache := self children
		inject: 0 into: [:s :c | s + c changeCount]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> changeType [
	"For leaves: #method #doIt #classDefinition #classComment #methodRemoval #misc."
	^ changeType
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> changeType: aSymbol [
	changeType := aSymbol
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> children: aCollection [
	children := aCollection asOrderedCollection.
	children do: [:c | c parent: self].
	totalLocCache := nil.
	childCountCache := nil
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:37'
}
SWAChangeNode >> computeStatusSymbol [
	"Intrinsic status ignoring the superseded flag. See #statusSymbol."
	| cls sel meta curSrc mySrc |
	(changeType == #method) ifFalse: [^ #doIt].
	cls := self resolvedClassOrNil.
	cls ifNil: [^ #gone].
	sel := methodSelector ifNil: [^ #gone].
	sel := sel asSymbol.
	(cls includesSelector: sel) ifFalse: [^ #gone].
	mySrc := (sourceText ifNil: ['']) withBlanksTrimmed.
	curSrc := ([(cls sourceCodeAt: sel) asString] on: Error do: [:e | nil]).
	(curSrc notNil and: [curSrc withBlanksTrimmed = mySrc]) ifTrue: [^ #current].
	(self appearsInVersionHistoryOf: cls selector: sel) ifTrue: [^ #inHistory].
	^ #other
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:38'
}
SWAChangeNode >> contentSignature [
	"A comparison key identifying this leaf's content, matching
	SWAChangeParser>>changeSignatureFor: exactly: for a method/removal the base
	'Class>>selector', otherwise the change type name; plus the trimmed source.
	Lets a node be tested against signatures collected from another changes file."
	| key base |
	self isLeaf ifFalse: [^ nil].
	(changeType == #method or: [changeType == #methodRemoval])
		ifTrue: [
			(methodClassName notNil and: [methodSelector notNil])
				ifTrue: [
					base := (methodClassName asString withBlanksTrimmed endsWith: ' class')
						ifTrue: [(methodClassName asString withBlanksTrimmed
							copyFrom: 1 to: methodClassName asString withBlanksTrimmed size - 6)
							withBlanksTrimmed]
						ifFalse: [methodClassName asString withBlanksTrimmed].
					key := base, '>>', methodSelector asString]
				ifFalse: [key := changeType asString]]
		ifFalse: [key := changeType asString].
	^ key, '||', (sourceText ifNil: ['']) withBlanksTrimmed
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:57'
}
SWAChangeNode >> countChangedLinesIn: aTextDiffBuilder [
	"Count inserted + removed lines in a built TextDiffBuilder, ignoring matched
	(unchanged) lines. Reuses the builder's own patch-sequence walk."
	| n |
	n := 0.
	aTextDiffBuilder
		patchSequenceDoIfMatch: [:line | ]
		ifInsert: [:line | n := n + 1]
		ifRemove: [:line | n := n + 1].
	^ n
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> crossRefKey [
	"Link to the Code Map / Space Tally: a method change answers
	'ClassName>>selector', a class-level change answers the class name."
	self isLeaf ifFalse: [^ nil].
	methodClassName ifNil: [^ nil].
	(changeType == #method or: [changeType == #methodRemoval]) ifTrue: [
		methodSelector ifNotNil: [
			^ methodClassName asString, '>>', methodSelector asString]].
	^ methodClassName asString
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:21'
}
SWAChangeNode >> diffFromSource [
	"The BEFORE side of this change's diff. For a definition, the baseline (previous
	in-scope, else image/prior) version. For a removal, the removed method body."
	changeType == #methodRemoval ifTrue: [^ priorSource ifNil: ['']].
	^ self baselineSource ifNil: ['']
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:21'
}
SWAChangeNode >> diffLines [
	"Number of CHANGED lines for this change -- the diff size (treemap weight),
	reusing TextDiffBuilder's line matcher.
	 - method definition: baseline (previous in-scope, else image) -> this source
	 - method removal:    removed body -> empty  (a big all-removed diff)
	With no baseline (genuinely first-seen), or a non-method change, fall back to
	own line count. Cached."
	| patch |
	diffLinesCache ifNotNil: [^ diffLinesCache].
	self isLeaf ifFalse: [^ diffLinesCache := 0].
	self hasDiffBaseline ifFalse: [^ diffLinesCache := self loc].
	patch := [TextDiffBuilder from: self diffFromSource to: self diffToSource]
		on: Error do: [:e | nil].
	patch ifNil: [^ diffLinesCache := self loc].
	^ diffLinesCache := (self countChangedLinesIn: patch) max: 1
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:21'
}
SWAChangeNode >> diffToSource [
	"The AFTER side of this change's diff. For a removal, empty (the method is
	gone). For a definition, this change's own source."
	changeType == #methodRemoval ifTrue: [^ ''].
	^ sourceText ifNil: ['']
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeNode >> dominantAuthor [
	"For a leaf: its author. For a container: the author responsible for the most
	leaf changes beneath it (nil authors ignored), or nil if none."
	| counts |
	self isLeaf ifTrue: [^ author].
	counts := Dictionary new.
	self withAllChildrenDo: [:n |
		(n isLeaf and: [n author notNil]) ifTrue: [
			counts at: n author put: (counts at: n author ifAbsent: [0]) + 1]].
	counts isEmpty ifTrue: [^ nil].
	^ (counts associations asSortedCollection: [:a :b | a value >= b value]) first key
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> estimatedNodeCount [
	"Cheap up-front node estimate for the progress bar. The tree is fully built
	eagerly by the parser, so just count it."
	^ 1 + (self children inject: 0 into: [:s :c | s + c estimatedNodeCount])
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:34'
}
SWAChangeNode >> flushRollups [
	"Invalidate cached rolled-up metrics after the child set changes."
	totalLocCache := nil.
	childCountCache := nil
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:21'
}
SWAChangeNode >> hasDiffBaseline [
	"True when this leaf is a method change (definition or removal) with a baseline
	to diff against. For a definition, the baseline is the previous version; for a
	removal, it is the removed body (diffed against empty)."
	self isLeaf ifFalse: [^ false].
	changeType == #method ifTrue: [^ self baselineSource notNil].
	changeType == #methodRemoval ifTrue: [^ priorSource notNil].
	^ false
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> isLeaf [
	^ kind == #change
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:33'
}
SWAChangeNode >> isMissingFromImage [
	"True when this change is NOT present in the running image: its exact source is
	neither the current in-image method NOR anywhere in the image's version history.
	Only method definitions are considered recoverable content; doIts, comments and
	class definitions are not part of the recovery diff.

	Reuses the intrinsic status: #other (exists but differs, not in history) and
	#gone (class/selector absent) are missing; #current and #inHistory are present."
	| st |
	self isLeaf ifFalse: [^ false].
	changeType == #method ifFalse: [^ false].
	st := self computeStatusSymbol.
	^ st == #other or: [st == #gone]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> kind [
	"One of #root #year #month #week #day #save #change."
	^ kind ifNil: [#node]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> kind: aSymbol [
	kind := aSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:50'
}
SWAChangeNode >> label [
	^ label
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> label: aString [
	label := aString
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> loc [
	"Lines of code for a leaf change (0 for empty). Containers answer their
	rolled-up descendant LOC via #totalLoc, not this."
	loc ifNotNil: [^ loc].
	sourceText ifNil: [^ loc := 0].
	^ loc := (sourceText occurrencesOf: Character lf)
		+ (sourceText occurrencesOf: Character cr) + 1
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:36'
}
SWAChangeNode >> markSuperseded [
	"Flag: a later change to the same Class>>selector exists in the changelog."
	statusCache := #superseded
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> methodClassName [
	^ methodClassName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> methodClassName: aString [
	methodClassName := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> methodSelector [
	^ methodSelector
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> methodSelector: aStringOrSymbol [
	methodSelector := aStringOrSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> name [
	^ label ifNil: ['?']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:05'
}
SWAChangeNode >> prevInScope [
	^ prevInScope
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:05'
}
SWAChangeNode >> prevInScope: aChangeNodeOrNil [
	"Set by the parser: the nearest earlier change to the SAME Class>>selector that
	is also within the parsed/scoped changelog, or nil if this is the first
	occurrence in scope."
	prevInScope := aChangeNodeOrNil.
	diffLinesCache := nil
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> prewarmDo: aBlock [
	"Depth-first walk forcing weight roll-ups, one aBlock value per node."
	self totalLoc.
	aBlock value: self.
	self children do: [:c | c prewarmDo: aBlock]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> printOn: aStream [
	aStream nextPutAll: 'SWAChangeNode('; nextPutAll: self kind asString;
		nextPutAll: ': '; nextPutAll: self name; nextPut: $)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:57'
}
SWAChangeNode >> priorSource [
	"Source of the immediately preceding version of this method, or nil if none
	(a brand-new method, or a non-method change)."
	^ priorSource
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:57'
}
SWAChangeNode >> priorSource: aStringOrNil [
	priorSource := aStringOrNil
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:33'
}
SWAChangeNode >> pruneKeepingLeavesSatisfying: aBlock [
	"Recursively remove branches that contain no leaf satisfying aBlock. Answer true
	if this node survives (it is a kept leaf, or a container with a surviving
	descendant). Prunes children in place and flushes rolled-up caches."
	| survivors |
	self isLeaf ifTrue: [^ aBlock value: self].
	survivors := self children select: [:c | c pruneKeepingLeavesSatisfying: aBlock].
	self children: survivors asOrderedCollection.
	self flushRollups.
	^ survivors notEmpty
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:37'
}
SWAChangeNode >> resolvedClassOrNil [
	"The image class (or metaclass) this change's method belongs to, or nil if it
	no longer exists. A trailing ' class' in methodClassName selects the metaclass."
	| name meta base |
	name := methodClassName ifNil: [^ nil].
	name := name asString withBlanksTrimmed.
	meta := name endsWith: ' class'.
	base := meta ifTrue: [(name copyFrom: 1 to: name size - 6) withBlanksTrimmed] ifFalse: [name].
	base := Smalltalk at: base asSymbol ifAbsent: [^ nil].
	^ meta ifTrue: [base class] ifFalse: [base]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> sourceString [
	"Text for the SWANavPanel Show pane. Leaves show their change source; a
	container shows a short summary of what it holds."
	self isLeaf ifTrue: [^ sourceText ifNil: ['']].
	^ String streamContents: [:s |
		s nextPutAll: self kind asString asUppercase; nextPutAll: ': '.
		s nextPutAll: self name; cr; cr.
		s nextPutAll: self changeCount printString; nextPutAll: ' changes, '.
		s print: self totalLoc; nextPutAll: ' lines.'; cr.
		timeStamp ifNotNil: [s cr; nextPutAll: timeStamp printString]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> sourceText [
	^ sourceText
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> sourceText: aString [
	sourceText := aString.
	loc := nil
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:37'
}
SWAChangeNode >> statusSymbol [
	"A mutually-exclusive provenance category for a leaf change, in priority order:
		#gone       - the class or selector no longer exists in the image
		#current    - source is identical to the current in-image method
		#superseded - a later change to the same method exists in the changelog
		#inHistory  - this exact source appears in the method's version history
		#other      - method exists in image but source differs / not in history
		#doIt       - a non-method change (doIt / misc / class-level)
	Containers answer nil. Cached (statusFinal) after first computation."
	| supersededFlag intrinsic |
	self isLeaf ifFalse: [^ nil].
	statusFinal ifNotNil: [^ statusFinal].
	supersededFlag := statusCache = #superseded.
	intrinsic := self computeStatusSymbol.
	"#gone and #current outrank superseded; everything else yields to it."
	(supersededFlag and: [intrinsic ~~ #gone and: [intrinsic ~~ #current]])
		ifTrue: [^ statusFinal := #superseded].
	^ statusFinal := intrinsic
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:57'
}
SWAChangeNode >> styleClassOrNil [
	"The change's class (or metaclass) so Shout highlights ivars/selectors in
	context when this leaf's source is shown. nil for containers / class-less."
	^ self resolvedClassOrNil
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:36'
}
SWAChangeNode >> supersededInChangelog [
	"Set by the parser: true if a LATER change to the same Class>>selector exists
	in the scanned changelog region."
	^ statusCache = #superseded
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> timeStamp [
	"A TimeStamp for this node (the change's stamp, or a save boundary's time)."
	^ timeStamp
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:48'
}
SWAChangeNode >> timeStamp: aTimeStamp [
	timeStamp := aTimeStamp
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:57'
}
SWAChangeNode >> totalLoc [
	"Rolled-up treemap weight across this subtree. A leaf weighs by its DIFF SIZE
	to the prior version (changed lines), so a small tweak makes a small tile and a
	big rewrite a big one -- floored at 1 so a tile never vanishes. Containers sum
	their children."
	self isLeaf ifTrue: [^ self diffLines max: 1].
	totalLocCache ifNotNil: [^ totalLocCache].
	^ totalLocCache := (self children
		inject: 0 into: [:s :c | s + c totalLoc]) max: 1
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:49'
}
SWAChangeNode >> totalSize [
	"Treemap weight: rolled-up lines of code, so busier days/saves and bigger
	methods get bigger tiles."
	^ self totalLoc
]
