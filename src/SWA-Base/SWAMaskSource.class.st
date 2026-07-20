"
A composite (""arithmetic"") source that combines the key sets of two other datasets with a set operator, and is the `source` of a #masked SWADataset.

Unlike a raw capture (coverage, call tally), a mask source produces NO measurements of its own -- it MASKS which method keys survive. Boolean 1.0 weight: a surviving key is on, everything else is nil (neutral tint), so the treemap highlights exactly the masked methods.

This generalizes the Space Tally's ""Diff from this"" to the Code Map. But because call counts are not a controlled payload, it is a SET MASK over `crossRefKey`s, not an arithmetic subtraction of counts:

	operator #minus  ->  keys in `right` but NOT in `left`   (""B \ A"": new methods only)

It RETAINS its operands (`left`, `right` -- the actual SWADatasets, marked as an operation) so it can display as `B \ A`, be navigated to either operand, and RE-BAKE (`recompute`) if a live operand is re-collected. It also MATERIALIZES the survivor set into `resultKeys` for O(1) `weightForKey:` lookup. Both: baked for speed, refs for introspection.

Operands must expose `#coveredMethodKeys` (call/coverage datasets do). The algebra closes: a mask source's operand may itself be a #masked dataset.
"
Class {
	#name : #SWAMaskSource,
	#superclass : #Object,
	#instVars : [
		'left',
		'right',
		'operator',
		'resultKeys'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource class >> left: aBaseDataset minus: anOverlayDataset [
	"Answer a mask source for 'overlay \ base' -- keys touched in the OVERLAY (second
	capture) that the BASE (baseline) never touched. Note the argument order: `left`
	is the base A, the mask keeps `right` (B) minus `left` (A)."
	^ self new setLeft: aBaseDataset right: anOverlayDataset operator: #minus
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> coveredMethodKeys [
	"The mask's OWN touched set is its survivor set -- so a mask can itself be an
	operand of another mask (the algebra closes: (B \ A) \ C )."
	^ resultKeys copy
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:04'
}
SWAMaskSource >> expressionString [
	"Human-readable operation, e.g. 'SqueakXR-call \ Morphic-call'."
	^ (right ifNil: ['?'] ifNotNil: [:d | d name ifNil: ['?']]),
		' ', self operatorGlyph, ' ',
		(left ifNil: ['?'] ifNotNil: [:d | d name ifNil: ['?']])
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> keysOf: aDataset [
	"The touched-method key set of an operand dataset. Operands are call/coverage
	datasets whose source answers #coveredMethodKeys; be defensive so a bad operand
	yields an empty set rather than a walkback."
	| src |
	aDataset ifNil: [^ Set new].
	src := aDataset source.
	(src respondsTo: #coveredMethodKeys)
		ifTrue: [^ src coveredMethodKeys asSet]
		ifFalse: [^ Set new]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> left [
	"The base operand A (its keys are SUBTRACTED)."
	^ left
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> maxWeight [
	"Boolean mask -- the only nonzero weight is 1.0."
	^ 1.0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> operator [
	"The set operator symbol (currently #minus)."
	^ operator
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> operatorGlyph [
	"A short infix glyph for display: 'B \ A'."
	operator == #minus ifTrue: [^ '\'].
	^ operator asString
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:04'
}
SWAMaskSource >> printOn: aStream [
	aStream nextPutAll: 'SWAMaskSource('; nextPutAll: self expressionString;
		nextPutAll: ' = '; print: self survivorCount; nextPutAll: ' keys)'
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> recompute [
	"(Re-)materialize the survivor key set from the current operands. Call after a live
	operand is re-collected. #minus keeps right's keys that are absent from left."
	| leftKeys rightKeys |
	leftKeys := self keysOf: left.
	rightKeys := self keysOf: right.
	operator == #minus
		ifTrue: [resultKeys := rightKeys reject: [:k | leftKeys includes: k]]
		ifFalse: [self error: 'unsupported mask operator: ', operator printString].
	^ resultKeys
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> right [
	"The overlay operand B (its keys are KEPT, minus A's)."
	^ right
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> setLeft: aLeftDataset right: aRightDataset operator: aSymbol [
	"Set the two operand datasets and the set operator, then bake the survivor set."
	left := aLeftDataset.
	right := aRightDataset.
	operator := aSymbol.
	self recompute
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> survivorCount [
	"How many method keys survived the mask (for status/report)."
	^ resultKeys size
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:03'
}
SWAMaskSource >> weightForKey: aCrossRefKey [
	"Boolean mask: 1.0 for a surviving key, nil otherwise (nil -> neutral tint, so
	only the masked-in methods light up)."
	aCrossRefKey ifNil: [^ nil].
	^ (resultKeys includes: aCrossRefKey) ifTrue: [1.0] ifFalse: [nil]
]
