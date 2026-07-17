"
A GLOBAL, shared set of ""marks"" (bookmarks) across all SWAPane views. Rather than hold node objects -- which are per-view and lost when a view is rebuilt or morphed -- a mark is stored as a cross-view identity STRING (see SWANode>>markKey): a package name, a class name, or 'ClassName>>selector' for a method. Each open view resolves the shared keys back to its own nodes through its keyIndex, so the same mark lights up (green border) in every view that contains it, and the left ""Marks"" panel of every pane lists the same entries.

The set is ORDERED (insertion order, first-wins on re-add) so the copied clipboard text is stable. It is a process-wide singleton (Default) so all panes and views share it and it persists across window open/close. Mutating it (add/remove/toggle/clear) notifies every open SWAPane so panels and treemap borders refresh.
"
Class {
	#name : #SWAMarkSet,
	#superclass : #Object,
	#instVars : [
		'keys',
		'comments',
		'provenance'
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
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> add: aKey from: aProvenanceDict [
	"Mark aKey and record where it came from (a serializable String->String Dictionary,
	or nil). Provenance is only (re)recorded when the key is newly added, so an existing
	mark keeps the origin of its FIRST sighting. Notifies open panes once."
	| wasMarked |
	aKey ifNil: [^ self].
	wasMarked := keys includes: aKey.
	self add: aKey.
	wasMarked ifFalse: [self provenanceAt: aKey put: aProvenanceDict]
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> asJsonString [
	"Serialise the mark keys (in order), their comments, and their provenance to a JSON
	string. Only keys that actually have a non-empty comment / recorded provenance are
	written. Provenance values are plain String->String maps, so this round-trips."
	| dict commentsOut provOut |
	commentsOut := Dictionary new.
	keys do: [:k | | c |
		c := self commentAt: k.
		c isEmpty ifFalse: [commentsOut at: k put: c]].
	provOut := Dictionary new.
	keys do: [:k | | p |
		p := self provenanceAt: k.
		(p notNil and: [p notEmpty]) ifTrue: [provOut at: k put: p]].
	dict := Dictionary new.
	dict at: 'keys' put: keys asArray.
	dict at: 'comments' put: commentsOut.
	dict at: 'provenance' put: provOut.
	^ Json render: dict
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> clear [
	"Remove all marks (and their comments + provenance). Notifies open panes on change."
	keys isEmpty ifTrue: [^ self].
	keys := OrderedCollection new.
	comments := Dictionary new.
	provenance := Dictionary new.
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:38'
}
SWAMarkSet >> initialize [
	super initialize.
	keys := OrderedCollection new.
	comments := Dictionary new.
	provenance := Dictionary new
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
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:21'
}
SWAMarkSet >> loadFromFile: aFileName [
	"Replace the current marks + comments with those read from the JSON file
	aFileName. Answers the number of keys loaded."
	| stream contents |
	stream := FileStream readOnlyFileNamed: aFileName.
	contents := [stream contentsOfEntireFile] ensure: [stream close].
	self loadFromJsonString: contents.
	^ keys size
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:40'
}
SWAMarkSet >> loadFromJsonString: aString [
	"Replace the current marks + comments + provenance with those parsed from a JSON
	string produced by #asJsonString. Provenance is optional (older sidecars omit it).
	Notifies open panes once when done."
	| parsed newKeys newComments newProv |
	parsed := Json readFrom: aString readStream.
	newKeys := OrderedCollection new.
	(parsed at: 'keys' ifAbsent: [#()]) do: [:k | newKeys add: k asString].
	newComments := Dictionary new.
	(parsed at: 'comments' ifAbsent: [Dictionary new])
		keysAndValuesDo: [:k :v | newComments at: k asString put: v asString].
	newProv := Dictionary new.
	(parsed at: 'provenance' ifAbsent: [Dictionary new])
		keysAndValuesDo: [:k :v | | entry |
			entry := Dictionary new.
			v keysAndValuesDo: [:pk :pv | entry at: pk asString put: pv asString].
			newProv at: k asString put: entry].
	keys := newKeys.
	comments := newComments.
	provenance := newProv.
	self notifyPanes
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
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:38'
}
SWAMarkSet >> provenance [
	"markKey -> provenance Dictionary. Records WHERE a mark was made: the kind of
	visualization, the dataset (name/kind/source label) and the root scope. Values are
	Strings/Symbols only, so the whole thing round-trips through JSON. Lazily created
	so a singleton persisted before provenance existed still works."
	provenance ifNil: [provenance := Dictionary new].
	^ provenance
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:38'
}
SWAMarkSet >> provenanceAt: aKey [
	"The provenance Dictionary for aKey, or nil if none was recorded. Keys inside are
	Strings ('viewKind', 'viewLabel', 'datasetName', 'datasetKind', 'datasetSource',
	'rootScope'); all values are Strings."
	aKey ifNil: [^ nil].
	^ self provenance at: aKey ifAbsent: [nil]
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> provenanceAt: aKey put: aProvenanceDict [
	"Record provenance for aKey (only meaningful for a marked key). aProvenanceDict is a
	Dictionary of String->String; nil or empty clears it. Values MUST be serializable
	(Strings/Symbols) -- never object references. Does NOT notify panes on its own; it is
	set alongside #add: which already notifies."
	aKey ifNil: [^ self].
	(keys includes: aKey) ifFalse: [^ self].
	(aProvenanceDict isNil or: [aProvenanceDict isEmpty])
		ifTrue: [self provenance removeKey: aKey ifAbsent: []]
		ifFalse: [self provenance at: aKey put: aProvenanceDict]
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> remove: aKey [
	"Unmark aKey (and drop its comment + provenance). No-op if nil or not marked.
	Notifies open panes on change."
	aKey ifNil: [^ self].
	(keys includes: aKey) ifFalse: [^ self].
	keys remove: aKey ifAbsent: [].
	comments removeKey: aKey ifAbsent: [].
	self provenance removeKey: aKey ifAbsent: [].
	self notifyPanes
]

{
	#category : #mutating,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> removeAll: someKeys [
	"Unmark every key in someKeys (and drop their comments + provenance), then notify ONCE."
	| changed |
	changed := false.
	someKeys copy do: [:k |
		(keys includes: k) ifTrue: [
			keys remove: k ifAbsent: [].
			self comments removeKey: k ifAbsent: [].
			self provenance removeKey: k ifAbsent: [].
			changed := true]].
	changed ifTrue: [self notifyPanes]
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:21'
}
SWAMarkSet >> saveToFile: aFileName [
	"Write the marks as JSON to aFileName, overwriting any existing file."
	| stream |
	stream := FileStream forceNewFileNamed: aFileName.
	[stream nextPutAll: self asJsonString] ensure: [stream close]
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

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:39'
}
SWAMarkSet >> toggle: aKey from: aProvenanceDict [
	"Flip aKey's marked state, recording provenance (a serializable String->String
	Dictionary, or nil) when it becomes marked. No-op if nil."
	aKey ifNil: [^ self].
	(keys includes: aKey)
		ifTrue: [self remove: aKey]
		ifFalse: [self add: aKey from: aProvenanceDict]
]
