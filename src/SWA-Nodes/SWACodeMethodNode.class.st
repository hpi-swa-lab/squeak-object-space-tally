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
	#classVars : [
		'ByteAnalysisCache'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:33'
}
SWACodeMethodNode class >> byteAnalysisCache [
	"A WeakIdentityKeyDictionary mapping a CompiledMethod to its cached byte
	analysis Array { docBytes. stringBytes. codeBytes }. Keyed on the method
	OBJECT so the entry survives tree rebuilds (every byte-mode reopen builds
	fresh transient nodes) yet is collected automatically when the method is
	recompiled or removed -- no manual flushing."
	^ ByteAnalysisCache ifNil: [ByteAnalysisCache := WeakIdentityKeyDictionary new]
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:32'
}
SWACodeMethodNode class >> classifyBytes: aSourceString [
	"Single left-to-right pass over Smalltalk method source, assigning EVERY
	character to exactly one bucket. Answer an Array { docBytes. stringBytes.
	codeBytes } whose sum equals aSourceString size.

	Three lexical states: code (selector / keywords / whitespace / char literals),
	inComment (between double quotes, doubled to escape), and inString (between
	single quotes, doubled to escape). A delimiter character is charged to the
	region it opens or closes, so doc and string fully account for their own
	syntax. A single quote inside a comment is ordinary comment text and vice
	versa. A dollar sign starts a character literal, so the next character is
	swallowed as code and a following quote does not open a string."
	| doc str code state i size ch dq sq |
	doc := str := code := 0.
	size := aSourceString size.
	dq := Character value: 34.   "double quote"
	sq := $'.
	state := #code.
	i := 1.
	[i <= size] whileTrue: [
		ch := aSourceString at: i.
		state == #code ifTrue: [
			ch == dq
				ifTrue: [doc := doc + 1. state := #inComment]
				ifFalse: [ch == sq
					ifTrue: [str := str + 1. state := #inString]
					ifFalse: [code := code + 1.
						(ch == $$ and: [i < size]) ifTrue: [
							i := i + 1. code := code + 1]]]]
		ifFalse: [state == #inComment
			ifTrue: [doc := doc + 1.
				ch == dq ifTrue: [
					(i < size and: [(aSourceString at: i + 1) == dq])
						ifTrue: [i := i + 1. doc := doc + 1]
						ifFalse: [state := #code]]]
			ifFalse: [
				str := str + 1.
				ch == sq ifTrue: [
					(i < size and: [(aSourceString at: i + 1) == sq])
						ifTrue: [i := i + 1. str := str + 1]
						ifFalse: [state := #code]]]].
		i := i + 1].
	^ { doc. str. code }
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:33'
}
SWACodeMethodNode class >> flushByteAnalysisCache [
	"Drop the whole byte-analysis cache. Normally unnecessary (the weak dictionary
	self-evicts as methods are collected), but handy when developing the classifier
	itself so changed logic re-runs over every method."
	ByteAnalysisCache := nil
]

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
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:51'
}
SWACodeMethodNode >> byteAnalysis [
	"Array { docBytes. stringBytes. codeBytes } for this method, fetched from (or
	computed into) the shared weak cache keyed on the CompiledMethod. Falls back to
	classifying this node's already-cached source when no live method is available
	(e.g. a stale reference), without polluting the cache.

	The cached entry is VALIDATED against the current source length: if they
	disagree (the method was recompiled and the entry is stale, or source could not
	be read when first cached) the analysis is recomputed and the entry refreshed.
	This guarantees doc+string+code always equals byteSize."
	| method cached src |
	src := self source.
	method := [subject compiledMethod] on: Error do: [:e | nil].
	method ifNil: [^ SWACodeMethodNode classifyBytes: src].
	cached := SWACodeMethodNode byteAnalysisCache at: method ifAbsent: [nil].
	(cached notNil and: [(cached first + (cached at: 2) + cached last) = src size])
		ifTrue: [^ cached].
	^ SWACodeMethodNode byteAnalysisCache
		at: method
		put: (SWACodeMethodNode classifyBytes: src)
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:35'
}
SWACodeMethodNode >> byteComposition [
	"Array { docBytes. stringBytes. codeBytes } for this leaf -- its own analysis."
	^ self byteAnalysis
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:33'
}
SWACodeMethodNode >> byteSize [
	"Total source-text byte size of this method (plain String size). Equals
	docBytes + stringBytes + codeBytes."
	^ self source size
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:34'
}
SWACodeMethodNode >> byteWeight [
	"Leaf treemap weight in byte-composition mode: this method's source byte size."
	^ self byteSize
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
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:33'
}
SWACodeMethodNode >> codeBytes [
	"Source-text bytes that are neither documentation nor string literals -- the
	actual code (selector, keywords, char literals, whitespace, etc.)."
	^ self byteAnalysis last
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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:02'
}
SWACodeMethodNode >> coverageWeight [
	"Leaf dynamic weight: covering-test count (#tests) or raw call count
	(#invocations); 0 if uncovered or no coverage data. The mode comes from
	#weightMetric when it is itself a dynamic metric (the live 'Size' menu), else
	from the legacy #coverageWeightMode. Test methods aren't in the coverage map, so
	a covered-weight of 0 on a known test key is floored to #testWeightFloor to keep
	tests visible."
	| key cov w mode |
	cov := self coverageData ifNil: [^ 0].
	key := self crossRefKey.
	mode := (self weightMetric == #invocations or: [self weightMetric == #tests])
		ifTrue: [self weightMetric]
		ifFalse: [self coverageWeightMode].
	w := mode == #invocations
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
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:33'
}
SWACodeMethodNode >> docBytes [
	"Source-text bytes that are method-comment documentation (the double-quoted
	regions, delimiters included)."
	^ self byteAnalysis first
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
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:33'
}
SWACodeMethodNode >> stringBytes [
	"Source-text bytes that are string literals (the single-quoted regions,
	delimiters included)."
	^ self byteAnalysis at: 2
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

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:41'
}
SWACodeMethodNode >> topicDistribution [
	"Leaf override: this method's own topic distribution from the inherited
	SWATopicData, as a Dictionary topicId -> weight. Empty if the method was pruned
	out of the model (too few surviving words) or no data is set."
	| td dist result |
	rollupTopic ifNotNil: [^ rollupTopic].
	td := self topicData.
	td ifNil: [^ rollupTopic := Dictionary new].
	result := Dictionary new.
	dist := td distributionFor: self crossRefKey.
	dist do: [:pair | result at: pair first put: pair last].
	^ rollupTopic := result
]
