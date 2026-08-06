"
ABSTRACT. Everything a view of an opencode conversation knows about its DATA, with no commitment to how that data is laid out on screen.

Lives here because there are now two layouts over the same conversation -- SWAOpenCodeFlowMorph, the 1D strip in reading order, and SWAOpenCodeFlowMapMorph, the 2D grid of turns -- and every one of these methods is identical for both. Before the split they sat in the strip, which meant the map could only have them by inheriting a layout it does not want.

What is here: the lane classification (user / assistant / reasoning / tool), the designed colours for those kinds, the cost / token / context metrics that opencode accounts per MESSAGE, and the size axes derived from them.

What is NOT here: rectangles. The layout hooks (#computeLayout, #visibleIndicesDo:, #scrollOffset) are declared by SWAChatFlowMorph and answered by the concrete subclasses.
"
Class {
	#name : #SWAOpenCodeFlowView,
	#superclass : #SWAChatFlowMorph,
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> baseColorForNode: aNode [
	| p |
	p := aNode payload.
	colorMode == #tool ifTrue: [
		((p isKindOf: SWAOpenCodePart) and: [p tool notNil])
			ifTrue: [^ Color h: (p tool asString hash \\ 360) s: 0.5 v: 0.72].
		^ Color gray: 0.25].
	(#(#msgCost #msgTokens #msgContext) includes: colorMode) ifTrue: [
		| val max |
		val := self messageValueFor: aNode kind: colorMode.
		max := self maxMessageValue: colorMode.
		(val isNil or: [max <= 0]) ifTrue: [^ Color gray: 0.25].
		val <= 0 ifTrue: [^ Color gray: 0.3].
		"sqrt ramp: a handful of messages dominate the spend, and a linear ramp
		would paint every other message the same cold blue."
		^ Color h: 220 - ((val / max) sqrt * 190) s: 0.6 v: 0.78].
	colorMode == #cost ifTrue: [^ self rampFor: (self sessionOf: aNode) value: #cost].
	colorMode == #tokens ifTrue: [^ self rampFor: (self sessionOf: aNode) value: #tokens].
	^ super baseColorForNode: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> colorModeOptions [
	"Message-level first: cost and tokens are accounted PER MESSAGE, so those vary
	inside a session and are what you actually want to look at. The session-level
	pair is the same quantity rolled up, useful only in a whole-project flow where
	sessions sit side by side."
	^ super colorModeOptions , {
		{#tool. 'Tool'}.
		{#msgCost. 'Message cost'}.
		{#msgTokens. 'Message tokens'}.
		{#msgContext. 'Message context (input+cache)'}.
		{#cost. 'Session cost'}.
		{#tokens. 'Session tokens'}
	}
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> intrinsicKindColorFor: aNode [
	| k p |
	k := self laneKeyFor: aNode.
	k == #user ifTrue: [^ Color r: 0.25 g: 0.55 b: 0.35].
	k == #reasoning ifTrue: [^ Color r: 0.32 g: 0.3 b: 0.45].
	k == #assistant ifTrue: [^ Color r: 0.25 g: 0.4 b: 0.6].
	k == #tool ifTrue: [
		"An errored tool call is the one thing worth spotting from across the room."
		p := aNode payload.
		((p isKindOf: SWAOpenCodePart) and: [p status == #error])
			ifTrue: [^ Color r: 0.65 g: 0.25 b: 0.2].
		^ Color r: 0.55 g: 0.45 b: 0.25].
	^ super intrinsicKindColorFor: aNode
]

{
	#category : #lanes,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> laneKeyFor: aNode [
	"user / assistant / reasoning / tool. A tool call is given its own lane rather
	than sharing the assistant's: it is the assistant ACTING rather than speaking,
	and separating them is what makes a grinding stretch visible as a solid column."
	| p |
	p := aNode payload.
	(p isKindOf: SWAOpenCodePart) ifFalse: [^ aNode nodeKind].
	p type == #tool ifTrue: [^ #tool].
	p type == #reasoning ifTrue: [^ #reasoning].
	p role = 'user' ifTrue: [^ #user].
	^ #assistant
]

{
	#category : #lanes,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> laneKeys [
	"FIXED order, unlike the base class's first-appearance ordering: the columns
	must not move between sessions, or comparing two flows side by side is
	impossible."
	^ #(#user #assistant #reasoning #tool)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> maxMessageValue: aSymbol [
	"Ceiling for the ramp, over DISTINCT messages in this flow -- not over items.
	Taking a max needs no dedup, but doing it per message makes the intent explicit
	and keeps this parallel to #maxSessionValue:. Cached; #flushLayout drops it."
	^ self valueOfProperty: aSymbol ifAbsentPut: [
		| seen max |
		seen := Set new.
		max := 0.
		self items do: [:n |
			| p |
			p := n payload.
			(p isKindOf: SWAOpenCodePart) ifTrue: [
				(seen includes: p messageId) ifFalse: [
					seen add: p messageId.
					(self messageValueFor: n kind: aSymbol)
						ifNotNil: [:val | max := max max: val]]]].
		max]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> maxSessionValue: aSymbol [
	"Ceiling for the ramp, taken over the sessions PRESENT IN THIS FLOW. Cached
	per mode; #flushLayout drops it with everything else derived from the items."
	^ self valueOfProperty: (aSymbol == #cost ifTrue: [#maxCost] ifFalse: [#maxTokens])
		ifAbsentPut: [
			| seen max |
			seen := Set new.
			max := 0.
			self items do: [:n |
				(self sessionOf: n) ifNotNil: [:s |
					(seen includes: s id) ifFalse: [
						seen add: s id.
						max := max max: (aSymbol == #cost
							ifTrue: [s cost]
							ifFalse: [s tokensInput + s tokensOutput])]]].
			max]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> messageValueFor: aNode kind: aSymbol [
	"Cost or tokens of the MESSAGE this node belongs to, or nil when unavailable.

	Every part of one message answers the same number -- that is how opencode
	accounts it, and it is the honest reading: the cost bought the whole
	assistant turn, not one part of it. Visually this lights up a whole message
	block, which is the right granularity.

	nil for a whole-project flow: there the payloads are tool calls, which carry
	no message id, and inventing a per-call cost would be a fabrication."
	| p m tk |
	p := aNode payload.
	(p isKindOf: SWAOpenCodePart) ifFalse: [^ nil].
	m := p messageData ifNil: [^ nil].
	aSymbol == #msgCost ifTrue: [^ m at: 'cost' ifAbsent: [nil]].
	tk := m at: 'tokens' ifAbsent: [nil].
	tk ifNil: [^ nil].
	aSymbol == #msgTokens ifTrue: [^ tk at: 'total' ifAbsent: [nil]].
	"CONTEXT is what was sent TO the model: input plus everything read from or
	written to the prompt cache. Distinct from #msgTokens, which includes the
	output and so answers a different question."
	aSymbol == #msgContext ifTrue: [
		| cache |
		cache := tk at: 'cache' ifAbsent: [Dictionary new].
		^ (tk at: 'input' ifAbsent: [0])
			+ (cache at: 'read' ifAbsent: [0])
			+ (cache at: 'write' ifAbsent: [0])].
	^ nil
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> partCountOfMessageOf: aNode [
	"How many parts share this node's message. Cached in one pass over the items,
	because a per-row scan would make layout quadratic."
	| p counts |
	p := aNode payload.
	(p isKindOf: SWAOpenCodePart) ifFalse: [^ 1].
	counts := self valueOfProperty: #partsPerMessage ifAbsentPut: [
		| d |
		d := Dictionary new.
		self items do: [:n |
			| q |
			q := n payload.
			(q isKindOf: SWAOpenCodePart) ifTrue: [
				d at: q messageId put: (d at: q messageId ifAbsent: [0]) + 1]].
		d].
	^ (counts at: p messageId ifAbsent: [1]) max: 1
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> rampFor: aSession value: aSymbol [
	| v max |
	aSession ifNil: [^ Color gray: 0.25].
	v := aSymbol == #cost
		ifTrue: [aSession cost]
		ifFalse: [aSession tokensInput + aSession tokensOutput].
	max := self maxSessionValue: aSymbol.
	(v isNil or: [v <= 0 or: [max <= 0]]) ifTrue: [^ Color gray: 0.25].
	^ Color h: 220 - ((v / max) sqrt * 190) s: 0.6 v: 0.75
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:59'
}
SWAOpenCodeFlowView >> sessionOf: aNode [
	| p |
	p := aNode payload.
	(p isKindOf: SWAOpenCodePart) ifTrue: [^ p session].
	(p isKindOf: SWAOpenCodeToolCall) ifTrue: [^ p session].
	(p isKindOf: SWAOpenCodeSession) ifTrue: [^ p].
	^ nil
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:01'
}
SWAOpenCodeFlowView >> sizeUnitFor: aNode mode: aMode [
	"Adds cost and context as size axes. Worth having as size and not only as
	colour: money and context are the two budgets a session actually spends, and a
	big cell is a far more legible 'this was expensive' than a warm one.

	Divided by the number of parts in the message, unlike the colour ramp: colour
	can repeat the message's value on each of its parts harmlessly, but SIZE
	accumulates -- repeating it would multiply the message's cost by its part count
	and make the flow lie about the totals."
	| val |
	(#(#msgCost #msgContext) includes: aMode) ifFalse: [
		^ super sizeUnitFor: aNode mode: aMode].
	val := self messageValueFor: aNode kind: aMode.
	val ifNil: [^ 3.0].
	val := val / (self partCountOfMessageOf: aNode).
	aMode == #msgCost ifTrue: [^ 3.0 + (val * 1200.0)].
	^ 3.0 + (val / 400.0)
]
