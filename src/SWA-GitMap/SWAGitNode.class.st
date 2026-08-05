"
A node in a GIT history treemap (see SWAGitHistory).

Reuses the whole SWAChangeNode contract -- kinds, changeType, diff sizing, status
provenance, cross-ref keys -- so the git map inherits the Change Map's view,
inline-diff source pane, and dataset/mark machinery unchanged. What it adds is git
identity: the GitCommit a change came from, its abbreviated hash, the commit
message, the Monticello patch operation (#added/#modified/#removed), and the
Monticello package name (taken from the commit, not guessed from the image).

Tree shape built by SWAGitHistory:
	root -> month -> day -> commit -> package -> class -> change

One deliberate override: #baselineSource answers priorSource directly rather than
preferring #prevInScope. Git already hands us the EXACT parent-commit version of a
modified method (MCModification>>obsoletion), which is a better baseline than ""the
previous version that happens to be inside the scanned window"".
"
Class {
	#name : #SWAGitNode,
	#superclass : #SWAChangeNode,
	#instVars : [
		'commit',
		'hexHash',
		'commitMessage',
		'operationKind',
		'packageName'
	],
	#category : #'SWA-GitMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> baselineSource [
	"Git hands us the EXACT parent-commit version of a modified method
	(MCModification>>obsoletion), stored as #priorSource. That is a strictly better
	diff baseline than the superclass's 'nearest earlier change inside the scanned
	window', which is only correct when the two commits happen to be adjacent -- so
	we ignore #prevInScope here (it is still set, for supersede marking and
	navigation)."
	^ priorSource
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> commit [
	"The GitCommit this node belongs to (set on #commit nodes and on their leaves)."
	^ commit
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> commit: aGitCommit [
	commit := aGitCommit
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> commitCount [
	"Number of distinct commits touching this subtree. A #commit node is 1;
	below it everything belongs to that one commit, above it we sum."
	kind == #commit ifTrue: [^ 1].
	self isLeaf ifTrue: [^ 1].
	^ self children inject: 0 into: [:s :c | s + c commitCount]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> commitMessage [
	^ commitMessage
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> commitMessage: aString [
	commitMessage := aString
]

{
	#category : #status,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:05'
}
SWAGitNode >> computeStatusSymbol [
	"Same 'is what git says still what my image has?' question as the Change Map,
	with one case the changes file cannot pose: a REMOVAL. The superclass lumps every
	non-#method change into #doIt, but for git a removal is a real, checkable claim --
	so answer

		#gone   the method is absent from the image too: the deletion took
		#other  the method is STILL THERE: the image has drifted from the repository
			(a stale copy, or an unpushed revival)

	which makes 'red = agrees with git, purple = image disagrees' readable at a glance
	in the status colouring."
	changeType == #methodRemoval ifTrue: [
		| cls sel |
		cls := self resolvedClassOrNil ifNil: [^ #gone].
		sel := methodSelector ifNil: [^ #gone].
		^ (cls includesSelector: sel asSymbol) ifTrue: [#other] ifFalse: [#gone]].
	^ super computeStatusSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> dominantCommitNode [
	"The enclosing #commit node, or nil above that level."
	| n |
	n := self.
	[n notNil] whileTrue: [
		n kind == #commit ifTrue: [^ n].
		n := n parent].
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWAGitNode >> eventGroupKey [
	"The commit this change belongs to -- its hash, which is the exact identity the
	'commits' measure wants."
	| n |
	n := self dominantCommitNode.
	^ n ifNil: [super eventGroupKey] ifNotNil: [:c | c hexHash]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> hexHash [
	^ hexHash
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> hexHash: aString [
	hexHash := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> operationKind [
	"#added / #modified / #removed -- the Monticello patch operation behind this
	change. Finer than #changeType, which only distinguishes a definition from a
	removal."
	^ operationKind
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> operationKind: aSymbol [
	operationKind := aSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> packageName [
	"The Monticello package this change was committed in -- read from the commit,
	not guessed from the image's current class categories."
	^ packageName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> packageName: aString [
	packageName := aString
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> printOn: aStream [
	aStream nextPutAll: 'SWAGitNode('; nextPutAll: (kind ifNil: ['?']) asString;
		nextPutAll: ' '; nextPutAll: self name.
	self shortHash ifNotNil: [:h | aStream nextPutAll: ' @'; nextPutAll: h].
	aStream nextPut: $)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:53'
}
SWAGitNode >> shortHash [
	"The usual 7-character abbreviated commit hash, or nil."
	hexHash ifNil: [^ nil].
	^ hexHash size > 7 ifTrue: [hexHash copyFrom: 1 to: 7] ifFalse: [hexHash]
]
