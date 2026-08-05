"
The treemap view of a git history (a SWAGitNode tree built by SWAGitHistory).

Subclasses SWAChangeTreemapMorph because a git commit and an image save pose the
same question -- ""what changed, when, by whom, and is it still what I have?"" -- so
the inline-diff source pane, the status/author/recency colourings, the cross-ref
keys and the dataset machinery are all inherited verbatim.

What it adds is the git dimension:
 - Colour BY OPERATION: green added, amber modified, red removed (containers take
   their dominant operation), which is the reading most people want from a diff.
 - Colour BY COMMIT: a stable hue per commit hash, so you can see one commit's
   footprint spread across packages and classes.
 - Colour BY PACKAGE: a stable hue per Monticello package.
 - commit hash / subject / package in the tooltip and the Details box.
"
Class {
	#name : #SWAGitTreemapMorph,
	#superclass : #SWAChangeTreemapMorph,
	#instVars : [
		'workingCopy'
	],
	#category : #'SWA-GitMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapMorph >> balloonStringFor: aNode [
	"Change-map tooltip plus the git provenance: which commit, and what it said."
	| base |
	base := super balloonStringFor: aNode.
	(aNode isKindOf: SWAGitNode) ifFalse: [^ base].
	^ String streamContents: [:s |
		aNode shortHash ifNotNil: [:h |
			s nextPutAll: 'commit: '; nextPutAll: h.
			aNode commitMessage ifNotNil: [:m |
				m isEmpty ifFalse: [s nextPutAll: '  '; nextPutAll: (m truncateWithElipsisTo: 60)]].
			s cr].
		(aNode isLeaf and: [aNode packageName notNil]) ifTrue: [
			s nextPutAll: 'package: '; nextPutAll: aNode packageName; cr].
		aNode kind == #commit ifTrue: [
			s nextPutAll: 'commits: 1, '; print: aNode changeCount; nextPutAll: ' changes'; cr]
		ifFalse: [
			aNode isLeaf ifFalse: [
				s print: aNode commitCount; nextPutAll: ' commits'; cr]].
		s nextPutAll: base]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitTreemapMorph >> baseColorForNode: aNode [
	"Dataset/cross-ref metrics win when active (handled by super); otherwise the
	git-specific modes first, then the inherited change-map ones."
	(self metricForMode: colorMode) ifNotNil: [:metric |
		^ (metric colorForNode: aNode) ifNil: [Color gray: 0.22]].
	colorMode == #operation ifTrue: [^ self colorByOperation: aNode].
	colorMode == #commit ifTrue: [^ self colorByCommit: aNode].
	colorMode == #package ifTrue: [^ self colorByPackage: aNode].
	^ super baseColorForNode: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:00'
}
SWAGitTreemapMorph >> baselineDescriptionFor: aNode [
	"Git's baseline is exact and always the same thing: the method as of the
	commit's FIRST PARENT (MCModification>>obsoletion). Name that, and name the
	parent commit if we can reach it -- 'image version' would be a lie here."
	| c parent |
	aNode changeType == #methodRemoval ifTrue: [^ 'body removed by this commit'].
	(aNode isKindOf: SWAGitNode) ifFalse: [^ super baselineDescriptionFor: aNode].
	c := aNode commit ifNil: [^ 'parent commit'].
	parent := [c parents isEmpty ifTrue: [nil] ifFalse: [c firstParent]]
		on: Error do: [:e | nil].
	parent ifNil: [^ 'parent commit'].
	^ 'parent commit ', ([parent hexHash copyFrom: 1 to: 7] on: Error do: [:e | '?'])
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapMorph >> colorByCommit: aNode [
	"A stable hue per commit hash, so one commit's footprint is recognisable
	wherever it landed. Time containers (month/day) hold many commits and stay
	neutral."
	| n hash |
	n := (aNode isKindOf: SWAGitNode) ifTrue: [aNode dominantCommitNode] ifFalse: [nil].
	n ifNil: [^ Color gray: 0.28].
	hash := n hexHash ifNil: [^ Color gray: 0.28].
	^ Color h: hash hash \\ 360 s: 0.55 v: 0.84
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitTreemapMorph >> colorByOperation: aNode [
	"The diff reading: green added, amber modified, red removed. Non-method
	definitions get their own hues. A container takes the operation that accounts
	for the MOST CHANGED LINES beneath it, so a tile's colour answers 'what did
	this mostly do', weighted the same way its area is."
	| op |
	op := aNode isLeaf
		ifTrue: [aNode operationKind]
		ifFalse: [self dominantOperationOf: aNode].
	aNode isLeaf ifTrue: [
		aNode changeType == #classDefinition ifTrue: [
			^ op == #removed
				ifTrue: [Color h: 320 s: 0.55 v: 0.78]
				ifFalse: [Color h: 280 s: 0.45 v: 0.84]].
		aNode changeType == #organization ifTrue: [^ Color gray: 0.55]].
	^ op caseOf: {
		[#added]    -> [Color h: 135 s: 0.55 v: 0.80].
		[#modified] -> [Color h: 42 s: 0.65 v: 0.88].
		[#removed]  -> [Color h: 2 s: 0.60 v: 0.82].
	} otherwise: [Color gray: 0.35]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapMorph >> colorByPackage: aNode [
	"A stable hue per Monticello package (as recorded in the commit). Nodes above
	the package level answer the package of their heaviest descendant."
	| name weights best bestW |
	name := (aNode isKindOf: SWAGitNode)
		ifTrue: [aNode kind == #package ifTrue: [aNode name] ifFalse: [aNode packageName]]
		ifFalse: [nil].
	name ifNil: [
		weights := Dictionary new.
		aNode withAllChildrenDo: [:n |
			(n isLeaf and: [(n isKindOf: SWAGitNode) and: [n packageName notNil]]) ifTrue: [
				weights at: n packageName
					put: (weights at: n packageName ifAbsent: [0]) + n diffLines]].
		best := nil. bestW := -1.
		weights keysAndValuesDo: [:k :w | w > bestW ifTrue: [bestW := w. best := k]].
		name := best].
	name ifNil: [^ Color gray: 0.28].
	^ Color h: name hash \\ 360 s: 0.45 v: 0.82
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapMorph >> detailContainerInfo: n on: s [
	"Change-map container details plus how many commits it spans (and, for a
	commit tile, its own hash and full subject)."
	(n isKindOf: SWAGitNode) ifTrue: [
		n kind == #commit
			ifTrue: [
				n hexHash ifNotNil: [:h | s nextPutAll: 'commit: '; nextPutAll: h; cr].
				n commitMessage ifNotNil: [:m |
					m isEmpty ifFalse: [s nextPutAll: 'subject: '; nextPutAll: m; cr]]]
			ifFalse: [s nextPutAll: 'commits: '; print: n commitCount; cr]].
	super detailContainerInfo: n on: s
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapMorph >> detailLeafInfo: n on: s [
	"Change-map leaf details plus operation, package and originating commit."
	(n isKindOf: SWAGitNode) ifTrue: [
		s nextPutAll: 'operation: '; nextPutAll: (n operationKind ifNil: ['-']) asString; cr.
		n packageName ifNotNil: [:p | s nextPutAll: 'package: '; nextPutAll: p; cr].
		n shortHash ifNotNil: [:h |
			s nextPutAll: 'commit: '; nextPutAll: h; cr.
			n commitMessage ifNotNil: [:m |
				m isEmpty ifFalse: [s nextPutAll: 'subject: '; nextPutAll: m; cr]]]].
	super detailLeafInfo: n on: s
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitTreemapMorph >> dominantOperationOf: aNode [
	"The operation accounting for the most CHANGED LINES under aNode (not the most
	leaves: one rewritten 200-line method should outweigh ten renamed accessors,
	exactly as it outweighs them in tile area)."
	| weights best bestW |
	weights := Dictionary new.
	aNode withAllChildrenDo: [:n |
		(n isLeaf and: [n operationKind notNil]) ifTrue: [
			weights at: n operationKind
				put: (weights at: n operationKind ifAbsent: [0]) + n diffLines]].
	best := nil. bestW := -1.
	weights keysAndValuesDo: [:k :w | w > bestW ifTrue: [bestW := w. best := k]].
	^ best
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapMorph >> formatWeight: aNumber [
	^ aNumber printString, ' changed lines'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitTreemapMorph >> initialize [
	super initialize.
	colorMode := #operation
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitTreemapMorph >> overlayClass [
	^ SWAGitTreemapOverlay
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitTreemapMorph >> viewKind [
	^ #gitMap
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitTreemapMorph >> workingCopy [
	"The GSGitWorkingCopy this map was built from, so tile actions can talk back to
	GitS (browse a commit, diff it against its parent)."
	^ workingCopy
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitTreemapMorph >> workingCopy: aGSGitWorkingCopy [
	workingCopy := aGSGitWorkingCopy
]
