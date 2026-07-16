"
A GLOBAL, shared set of ""marks"" (bookmarks) across all SWAPane views. Rather than hold node objects -- which are per-view and lost when a view is rebuilt or morphed -- a mark is stored as a cross-view identity STRING (see SWANode>>markKey): a package name, a class name, or 'ClassName>>selector' for a method. Each open view resolves the shared keys back to its own nodes through its keyIndex, so the same mark lights up (green border) in every view that contains it, and the left ""Marks"" panel of every pane lists the same entries.

The set is ORDERED (insertion order, first-wins on re-add) so the copied clipboard text is stable. It is a process-wide singleton (Default) so all panes and views share it and it persists across window open/close. Mutating it (add/remove/toggle/clear) notifies every open SWAPane so panels and treemap borders refresh.
"
Class {
	#name : #SWAMarkSet,
	#superclass : #Object,
	#instVars : [
		'keys',
		'comments'
	],
	#classVars : [
		'Default'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:55'
}
SWAMarkSet class >> default [
	"The process-wide singleton mark set shared by all SWAPane views."
	^ Default ifNil: [Default := self new]
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:56'
}
SWAMarkSet >> add: aKey [
	"Mark aKey (a markKey String). No-op if nil or already marked. Preserves
	insertion order. Notifies open panes on change."
	aKey ifNil: [^ self].
	(keys includes: aKey) ifTrue: [^ self].
	keys addLast: aKey.
	self notifyPanes
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> clear [
	"Remove all marks (and their comments). Notifies open panes on change."
	keys isEmpty ifTrue: [^ self].
	keys := OrderedCollection new.
	comments := Dictionary new.
	self notifyPanes
]

{
	#category : #clipboard,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> clipboardString [
	"All marks as newline-separated text (see #clipboardStringForKeys:)."
	^ self clipboardStringForKeys: keys
]

{
	#category : #clipboard,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:36'
}
SWAMarkSet >> clipboardStringForKeys: someKeys [
	"The given keys as newline-separated text, one per line, in the order given. A
	key that has a comment is emitted as 'key  --  comment'; keys without a comment
	are emitted bare. A markKey is a package name, a class name, or
	'ClassName>>selector'."
	^ String streamContents: [:s |
		someKeys
			do: [:k | | c |
				s nextPutAll: k.
				c := self commentAt: k.
				c isEmpty ifFalse: [s nextPutAll: '  --  '; nextPutAll: c]]
			separatedBy: [s cr]]
]

{
	#category : #comments,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> commentAt: aKey [
	"The comment for aKey, or '' if none."
	aKey ifNil: [^ ''].
	^ self comments at: aKey ifAbsent: ['']
]

{
	#category : #comments,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> commentAt: aKey put: aString [
	"Set (or, for empty text, clear) the comment for aKey. Only meaningful for a key
	that is actually marked. Notifies open panes so the editor/list refresh."
	aKey ifNil: [^ self].
	(keys includes: aKey) ifFalse: [^ self].
	(aString isNil or: [aString asString withBlanksTrimmed isEmpty])
		ifTrue: [self comments removeKey: aKey ifAbsent: []]
		ifFalse: [self comments at: aKey put: aString asString].
	self notifyPanes
]

{
	#category : #comments,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> comments [
	"markKey -> comment String. Lazily created so a singleton persisted before
	comments existed still works."
	comments ifNil: [comments := Dictionary new].
	^ comments
]

{
	#category : #clipboard,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:36'
}
SWAMarkSet >> copyKeysToClipboard: someKeys [
	"Put the given keys (with their comments) on the system clipboard for pasting."
	| str |
	str := self clipboardStringForKeys: someKeys.
	Clipboard clipboardText: str.
	^ str
]

{
	#category : #clipboard,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:36'
}
SWAMarkSet >> copyToClipboard [
	"Put ALL marks (with comments) on the system clipboard for pasting."
	^ self copyKeysToClipboard: keys
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:55'
}
SWAMarkSet >> includes: aKey [
	"Is aKey (a markKey String) currently marked?"
	^ aKey notNil and: [keys includes: aKey]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> initialize [
	super initialize.
	keys := OrderedCollection new.
	comments := Dictionary new
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:55'
}
SWAMarkSet >> isEmpty [
	^ keys isEmpty
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:55'
}
SWAMarkSet >> keys [
	"The mark keys in insertion order (a copy is not made; do not mutate)."
	^ keys
]

{
	#category : #notifying,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:56'
}
SWAMarkSet >> notifyPanes [
	"Tell every open SWAPane that the marks changed, so each refreshes its Marks
	list panel and repaints its view's green mark borders. Discovered live (not a
	registry) so closed panes drop out automatically."
	self changed.
	SWAPane openPanels do: [:p | p marksChanged]
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:35'
}
SWAMarkSet >> remove: aKey [
	"Unmark aKey (and drop its comment). No-op if nil or not marked. Notifies open
	panes on change."
	aKey ifNil: [^ self].
	(keys includes: aKey) ifFalse: [^ self].
	keys remove: aKey ifAbsent: [].
	comments removeKey: aKey ifAbsent: [].
	self notifyPanes
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:36'
}
SWAMarkSet >> removeAll: someKeys [
	"Unmark every key in someKeys (and drop their comments), then notify ONCE."
	| changed |
	changed := false.
	someKeys copy do: [:k |
		(keys includes: k) ifTrue: [
			keys remove: k ifAbsent: [].
			self comments removeKey: k ifAbsent: [].
			changed := true]].
	changed ifTrue: [self notifyPanes]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:55'
}
SWAMarkSet >> size [
	^ keys size
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:56'
}
SWAMarkSet >> toggle: aKey [
	"Flip aKey's marked state. No-op if nil."
	aKey ifNil: [^ self].
	(keys includes: aKey)
		ifTrue: [self remove: aKey]
		ifFalse: [self add: aKey]
]
