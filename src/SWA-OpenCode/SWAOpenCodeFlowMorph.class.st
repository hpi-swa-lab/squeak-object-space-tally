"
SWAChatFlowMorph specialised for opencode conversations: real chat lanes and a
designed palette instead of the generic hashed one.

LANES are user / assistant / reasoning / tool, in that order, so the shape of a
session is readable without reading a word -- a long unbroken tool column is an
agent grinding, an alternation is a conversation.

Adds two colour modes the base class cannot have, because only here do the
nodes know what they cost: #cost and #tokens, read off the owning session.
Note what they mean: opencode accounts cost and tokens PER SESSION, not per
part, so every part of one session carries the same value. That makes them
useful for comparing sessions in a whole-project flow and useless inside a
single session, which is exactly the trap worth naming rather than hiding.
"
Class {
	#name : #SWAOpenCodeFlowMorph,
	#superclass : #SWAChatFlowMorph,
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:50'
}
SWAOpenCodeFlowMorph >> baseColorForNode: aNode [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:49'
}
SWAOpenCodeFlowMorph >> colorModeOptions [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAOpenCodeFlowMorph >> intrinsicKindColorFor: aNode [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAOpenCodeFlowMorph >> laneKeyFor: aNode [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAOpenCodeFlowMorph >> laneKeys [
	"FIXED order, unlike the base class's first-appearance ordering: the columns
	must not move between sessions, or comparing two flows side by side is
	impossible."
	^ #(#user #assistant #reasoning #tool)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:50'
}
SWAOpenCodeFlowMorph >> maxMessageValue: aSymbol [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAOpenCodeFlowMorph >> maxSessionValue: aSymbol [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:49'
}
SWAOpenCodeFlowMorph >> messageValueFor: aNode kind: aSymbol [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:50'
}
SWAOpenCodeFlowMorph >> partCountOfMessageOf: aNode [
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAOpenCodeFlowMorph >> rampFor: aSession value: aSymbol [
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:50'
}
SWAOpenCodeFlowMorph >> rowHeightUnitFor: aNode [
	"Adds cost and context as HEIGHT axes. Worth having as size and not only as
	colour: money and context are the two budgets a session actually spends, and a
	tall row is a far more legible 'this was expensive' than a warm one.

	Divided by the number of parts in the message, unlike the colour ramp: colour
	can repeat the message's value on each of its parts harmlessly, but HEIGHT
	accumulates -- repeating it would multiply the message's cost by its part
	count and make the flow lie about the totals."
	| val |
	(#(#msgCost #msgContext) includes: yMode) ifFalse: [
		^ super rowHeightUnitFor: aNode].
	val := self messageValueFor: aNode kind: yMode.
	val ifNil: [^ 3.0].
	val := val / (self partCountOfMessageOf: aNode).
	yMode == #msgCost ifTrue: [^ 3.0 + (val * 1200.0)].
	^ 3.0 + (val / 400.0)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAOpenCodeFlowMorph >> sessionOf: aNode [
	| p |
	p := aNode payload.
	(p isKindOf: SWAOpenCodePart) ifTrue: [^ p session].
	(p isKindOf: SWAOpenCodeToolCall) ifTrue: [^ p session].
	(p isKindOf: SWAOpenCodeSession) ifTrue: [^ p].
	^ nil
]
