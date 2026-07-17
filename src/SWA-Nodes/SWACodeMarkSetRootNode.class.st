"
A code-tree root whose class children are exactly the CLASSES currently marked in a
SWAMarkSet (marks whose recorded nodeKind is #class), rather than whole packages. Used
to build a class diagram scoped to an interactively-gathered set of marks. The children
are flat SWACodeClassNodes (one per resolvable marked class name), so a class diagram
walking withAllChildrenDo: sees only those classes; inheritance edges to unmarked
superclasses render as external (lightgray) placeholders. Rebuilds from the live mark
set each time #children is (re)requested after #invalidate.
"
Class {
	#name : #SWACodeMarkSetRootNode,
	#superclass : #SWACodeRootNode,
	#instVars : [
		'markSet'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> buildChildren [
	"One flat SWACodeClassNode per marked CLASS (marks whose recorded nodeKind is #class),
	resolving the markKey -- a bare class name -- to a live class. Marks that don't resolve
	to a class in this image are skipped. Sorted by name so the diagram layout is stable.
	Method marks ('Class>>sel') and package marks contribute their owning class too, so a
	diagram gathered from mixed marks still shows the relevant classes."
	| classes |
	classes := Set new.
	self markSet keys do: [:key | | cls |
		cls := self classForMarkKey: key.
		cls ifNotNil: [classes add: cls]].
	^ (classes asSortedCollection: [:a :b | a name <= b name])
		collect: [:cls | SWACodeClassNode on: cls parent: self]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> classForMarkKey: aKey [
	"The live class a markKey refers to, or nil. Uses the recorded node kind when present:
	 - #class    -> the class named aKey,
	 - #method   -> the class in 'ClassName>>selector',
	otherwise best-effort: if aKey parses as 'Class>>sel' take the class, else if it names
	a class take it, else nil (packages/categories have no single class). Metaclasses map
	to their instance side so the diagram groups class-side under the class."
	| kind name |
	aKey ifNil: [^ nil].
	kind := self markSet nodeKindAt: aKey.
	name := (aKey includesSubstring: '>>')
		ifTrue: [(aKey copyUpToLast: $>) copyReplaceAll: '>' with: '']
		ifFalse: [aKey].
	name := name withBlanksTrimmed.
	(kind == #package or: [kind == #category]) ifTrue: [^ nil].
	^ (Smalltalk classNamed: name) ifNotNil: [:c | c isBehavior ifTrue: [c theNonMetaClass] ifFalse: [nil]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> displayName [
	"Marks-scoped roots have no package glob; identify them by a stable token so mark
	provenance and pane-matching don't confuse them with a package root."
	^ '<marks>'
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> invalidate [
	"Drop the cached children so the next #children re-reads the live mark set."
	children := nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> markSet [
	"The SWAMarkSet backing this root (defaults to the global singleton)."
	^ markSet ifNil: [markSet := SWAMarkSet default]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> markSet: aMarkSet [
	"Set the SWAMarkSet whose #class marks define this root's classes. Returns self."
	markSet := aMarkSet.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:12'
}
SWACodeMarkSetRootNode >> name [
	"Label for the diagram: how many marked classes it currently contains."
	^ 'Marked classes (', self children size printString, ')'
]
