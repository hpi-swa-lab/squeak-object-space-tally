"
Interaction layer over a SWAGitTreemapMorph: adds the git colour modes to the
Color menu and git actions (browse the method as it is in the image now, show the
commit in the Git Browser, copy the hash) to the tile context menu.
"
Class {
	#name : #SWAGitTreemapOverlay,
	#superclass : #SWAChangeTreemapOverlay,
	#category : #'SWA-GitMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapOverlay >> addMenuItems: aMenu for: aNode [
	"Browse the change's method as it stands in the image now (inherited), plus
	git-side actions on the commit this tile belongs to."
	super addMenuItems: aMenu for: aNode.
	(aNode isKindOf: SWAGitNode) ifFalse: [^ self].
	aNode dominantCommitNode ifNotNil: [:c |
		aMenu add: 'browse commit ', (c shortHash ifNil: ['?']), ' in Git Browser'
			target: self selector: #browseCommitOf: argument: aNode.
		aMenu add: 'copy commit hash' target: self selector: #copyHashOf: argument: aNode]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapOverlay >> browseCommitOf: aNode [
	"Open the GitS diff of this tile's commit against its first parent -- the same
	changes dialog the Git Browser shows, scoped to the one commit."
	| commitNode commit wc |
	commitNode := aNode dominantCommitNode ifNil: [^ self].
	commit := commitNode commit ifNil: [^ self].
	wc := self treemapMorph workingCopy ifNil: [^ self inform: 'no working copy on this map'].
	[wc actionCompareCommitToParent: commit]
		on: Error do: [:e | self inform: 'GitS: ', e messageText]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapOverlay >> browseNode: aNode [
	"Browse the change's class/selector as it exists NOW in the image. Overrides the
	change-map version, which looks the name up with `Smalltalk at:` and therefore
	cannot find a CLASS-SIDE method -- our leaves are keyed 'Foo class>>bar', so we
	go through SWAChangeNode>>resolvedClassOrNil, which understands the metaclass."
	| cls sel |
	cls := aNode resolvedClassOrNil
		ifNil: [^ self inform: (aNode methodClassName ifNil: ['?']), ' no longer exists in this image'].
	sel := aNode methodSelector.
	(sel notNil and: [aNode changeType == #method])
		ifTrue: [ToolSet browse: cls selector: sel asSymbol]
		ifFalse: [ToolSet browse: cls selector: nil]
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapOverlay >> colorModeOptions [
	^ #(
		(#operation  'By operation (added / modified / removed)')
		(#commit     'By commit (a hue per commit)')
		(#package    'By package')
		(#author     'By author')
		(#recency    'By recency (blue old -> red new)')
		(#status     'By status vs image (current / superseded / gone)')
		(#changeKind 'By change kind (method / class / organization)')
	)
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:57'
}
SWAGitTreemapOverlay >> copyHashOf: aNode [
	| commitNode hash |
	commitNode := aNode dominantCommitNode ifNil: [^ self].
	hash := commitNode hexHash ifNil: [^ self].
	Clipboard clipboardText: hash.
	Transcript cr; show: 'git hash: ', hash
]
