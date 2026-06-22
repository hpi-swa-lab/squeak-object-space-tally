"
A leaf SWACodeNode whose subject is a MethodReference. Computes metrics (loc, commentLines, lastChanged, lastAuthor, changeCount) from the MethodReference, delegating source access to its owning class node. 'isStatic' is true for class-side methods (UML 'static').
"
Class {
	#name : #SWACodeMethodNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'isStatic'
	],
	#category : #'SWA-CodeMap',
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeMethodNode >> changeCount [
	"Number of recorded versions of this method in the .changes/.sources history.
	Computed on demand (can be slow for hot methods); not cached here yet."
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
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> commentLines [
	"Heuristic: source lines whose first non-blank character starts a comment.
	Good enough for a quick metric; full lexing can come later."
	^ (self source lines count: [:l | l withBlanksTrimmed beginsWith: '"'])
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeMethodNode >> lastAuthor [
	"Author initials parsed from the method timeStamp ('<initials> <date> <time>'),
	or nil if unavailable."
	| ts tokens |
	ts := [subject timeStamp] on: Error do: [:e | nil].
	(ts isNil or: [ts isEmpty]) ifTrue: [^ nil].
	tokens := ts findTokens: ' '.
	tokens size >= 3 ifFalse: [^ nil].
	^ tokens first
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeMethodNode >> lastChanged [
	"DateAndTime parsed from the method timeStamp ('<initials> <m/d/yyyy> <hh:mm>'),
	or nil if unavailable/unparseable."
	| ts tokens |
	ts := [subject timeStamp] on: Error do: [:e | nil].
	(ts isNil or: [ts isEmpty]) ifTrue: [^ nil].
	tokens := ts findTokens: ' '.
	tokens size >= 3 ifFalse: [^ nil].
	^ [DateAndTime date: (Date fromString: (tokens at: 2))
		time: (Time fromString: (tokens at: 3))]
		on: Error do: [:e | nil]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> loc [
	"Lines of code: non-blank source lines."
	^ (self source lines reject: [:l | l withBlanksTrimmed isEmpty]) size
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeMethodNode >> source [
	"The method source string. The MethodReference knows how to fetch it."
	^ [subject source asString] on: Error do: [:e | '']
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
