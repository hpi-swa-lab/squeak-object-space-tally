"
A leaf node representing a CLASS COMMENT as a first-class element of the code map, sibling to the method-category nodes under a class. Its subject is the (non-meta) class; its source is the class comment text, so it participates in the same byte-composition / LOC metrics as methods -- its bytes are almost entirely DOCUMENTATION. Reuses SWACodeMethodNode's source/loc/byte caching by overriding only the few accessors that assume subject is a MethodReference.
"
Class {
	#name : #SWACodeCommentNode,
	#superclass : #SWACodeMethodNode,
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeCommentNode >> browse [
	"Open a browser on the class; its comment is shown in the comment pane."
	^ ToolSet browse: subject theNonMetaClass selector: nil
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:50'
}
SWACodeCommentNode >> byteAnalysis [
	"A class comment is pure prose -- it is documentation in its entirety, with no
	Smalltalk syntax to lex. So ALL of its bytes are charged to the documentation
	bucket (the lexical method-source classifier does not apply here)."
	^ { self source size. 0. 0 }
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeCommentNode >> computeChangeCount [
	"Class comments have no per-method version history we scan; report 1 (it exists)."
	^ 1
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeCommentNode >> crossRefKey [
	"Identified across views by the class name plus a comment marker, so it never
	collides with the class's own crossRefKey (the bare class name)."
	^ subject theNonMetaClass name asString, ' (comment)'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeCommentNode >> isStatic [
	^ false
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:48'
}
SWACodeCommentNode >> kind [
	^ #comment
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeCommentNode >> methodCount [
	"A class comment is not a method, so it does not inflate method counts."
	^ 0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:48'
}
SWACodeCommentNode >> name [
	^ 'class comment'
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:48'
}
SWACodeCommentNode >> source [
	"The class comment text as a String, cached. subject is the class itself."
	^ cachedSource ifNil: [
		cachedSource := [(subject theNonMetaClass organization classComment ifNil: ['']) asString]
			on: Error do: [:e | '']]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeCommentNode >> timeStamp [
	"The class comment's stamp ('<initials> <date> <time>'), cached. Empty when the
	comment was never stamped (e.g. '<historical>'), so author/date fall back to ?."
	^ cachedTimeStamp ifNil: [
		cachedTimeStamp := ([ | st |
			st := subject theNonMetaClass organization commentStamp.
			(st isNil or: [st = '<historical>']) ifTrue: [''] ifFalse: [st]]
			on: Error do: [:e | nil]) ifNil: ['']]
]
