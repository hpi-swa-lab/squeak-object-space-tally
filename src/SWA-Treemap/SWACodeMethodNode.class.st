"
A leaf SWACodeNode whose subject is a MethodReference. Computes metrics (loc, commentLines, lastChanged, lastAuthor, changeCount) from the MethodReference, delegating source access to its owning class node. 'isStatic' is true for class-side methods (UML 'static').
"
Class {
	#name : #SWACodeMethodNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'isStatic',
		'cachedSource',
		'cachedLoc',
		'cachedTimeStamp',
		'cachedChangeCount'
	],
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeMethodNode >> browse [
	^ ToolSet browse: subject actualClass selector: subject selector
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> buildChildren [
	"Methods are leaves."
	^ OrderedCollection new
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:37'
}
SWACodeMethodNode >> changeCount [
	"Number of recorded versions of this method in the .changes/.sources history.
	Scanning the version history is expensive, so the result is cached (the 'versions'
	color mode colours every node, which would otherwise re-scan the whole package)."
	^ cachedChangeCount ifNil: [cachedChangeCount := self computeChangeCount]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> commentLines [
	"Heuristic: source lines whose first non-blank character starts a comment.
	Good enough for a quick metric; full lexing can come later."
	^ (self source lines count: [:l | l withBlanksTrimmed beginsWith: '"'])
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:37'
}
SWACodeMethodNode >> computeChangeCount [
	"Scan the .changes/.sources version history for this method and count versions.
	Slow; call once and cache via #changeCount."
	| cls sel meta vb |
	cls := subject actualClass.
	cls ifNil: [^ 0].
	meta := cls isMeta.
	cls := cls theNonMetaClass.
	sel := subject selector.
	vb := VersionsBrowser new.
	^ [vb
		scanVersionsOf: (subject actualClass >> sel)
		class: cls
		meta: meta
		category: subject category
		selector: sel.
	   vb changeList size]
		on: Error do: [:e | 0]
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:17'
}
SWACodeMethodNode >> coverageWeight [
	"Leaf coverage weight: covering-test count (#tests) or raw call count
	(#invocations); 0 if uncovered or no coverage data. Test methods aren't in the
	coverage map, so a covered-weight of 0 on a known test key is floored to
	#testWeightFloor to keep tests visible."
	| key cov w |
	cov := self coverageData ifNil: [^ 0].
	key := self crossRefKey.
	w := self coverageWeightMode == #invocations
		ifTrue: [cov invocationCountFor: key]
		ifFalse: [cov coveringTestCountFor: key].
	(w = 0 and: [cov isTestKey: key]) ifTrue: [^ self testWeightFloor].
	^ w
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:56'
}
SWACodeMethodNode >> crossRefKey [
	"Methods are identified across views by 'ClassName>>selector'
	('ClassName class>>selector' for class-side methods). subject is a
	MethodReference; actualClass already yields the metaclass for class-side."
	^ subject actualClass name asString, '>>', subject selector
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> isStatic [
	^ isStatic == true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> isStatic: aBoolean [
	isStatic := aBoolean
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> kind [
	^ #method
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:44'
}
SWACodeMethodNode >> lastAuthor [
	"Author initials parsed from the cached method timeStamp ('<initials> <date> <time>'),
	or nil if unavailable."
	| ts tokens |
	ts := self timeStamp.
	ts isEmpty ifTrue: [^ nil].
	tokens := ts findTokens: ' '.
	tokens size >= 3 ifFalse: [^ nil].
	^ tokens first
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:44'
}
SWACodeMethodNode >> lastChanged [
	"DateAndTime parsed from the cached method timeStamp ('<initials> <m/d/yyyy> <hh:mm>'),
	or nil if unavailable/unparseable."
	| ts tokens |
	ts := self timeStamp.
	ts isEmpty ifTrue: [^ nil].
	tokens := ts findTokens: ' '.
	tokens size >= 3 ifFalse: [^ nil].
	^ [DateAndTime date: (Date fromString: (tokens at: 2))
		time: (Time fromString: (tokens at: 3))]
		on: Error do: [:e | nil]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:44'
}
SWACodeMethodNode >> loc [
	"Lines of code: non-blank source lines. Cached, since the treemap squarifies by
	loc and would otherwise re-read source from disk on every layout pass."
	^ cachedLoc ifNil: [
		cachedLoc := (self source lines reject: [:l | l withBlanksTrimmed isEmpty]) size]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:37'
}
SWACodeMethodNode >> methodCount [
	"A method leaf counts as one method."
	^ 1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> name [
	^ subject selector asString
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:44'
}
SWACodeMethodNode >> source [
	"The method source string, fetched once from the .changes/.sources file via the
	MethodReference and then held in the image. Source does not live in the image
	otherwise, so caching it here avoids a disk read on every loc/relayout/Show."
	^ cachedSource ifNil: [
		cachedSource := [subject source asString] on: Error do: [:e | '']]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:43'
}
SWACodeMethodNode >> sourceString [
	"The method source string for display in the source pane."
	^ self source
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:43'
}
SWACodeMethodNode >> styleClassOrNil [
	"The method's class (or metaclass) so Shout highlights ivars/selectors in context."
	^ [subject actualClass] on: Error do: [:e | nil]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:44'
}
SWACodeMethodNode >> timeStamp [
	"Raw method timeStamp string ('<initials> <date> <time>'), fetched once from the
	MethodReference and cached. Feeds lastAuthor and lastChanged. Empty string means
	'looked up, nothing there' so we don't retry the disk read."
	^ cachedTimeStamp ifNil: [
		cachedTimeStamp := ([subject timeStamp] on: Error do: [:e | nil]) ifNil: ['']]
]
