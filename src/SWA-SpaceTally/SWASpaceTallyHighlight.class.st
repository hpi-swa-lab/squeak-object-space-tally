"
A transient, half-transparent overlay placed over a Morph that is selected in a SWASpaceTallyExplorer. It mirrors the target morph's world bounds and prints the calculated (tally) size in its centre. It is purely decorative: it ignores mouse events (so clicks fall through to the morph beneath) and removes itself when the target goes away. Create via `SWASpaceTallyHighlight on: aMorph bytes: anInteger`.
"
Class {
	#name : #SWASpaceTallyHighlight,
	#superclass : #Morph,
	#instVars : [
		'target',
		'sizeLabel'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:47'
}
SWASpaceTallyHighlight class >> on: aMorph bytes: anInteger [
	"Create a highlight overlay for aMorph, labelled with anInteger bytes."

	^ self new setTarget: aMorph bytes: anInteger
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyHighlight >> followTarget [
	"Match the target's on-screen bounds and centre the size label. If the
	target is gone or no longer in a world, remove ourselves."

	(target isNil or: [target world isNil]) ifTrue: [^ self delete].
	self bounds: target boundsInWorld.
	sizeLabel
		fitContents;
		bounds: (sizeLabel bounds align: sizeLabel bounds center with: self bounds center)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyHighlight >> handlesMouseDown: anEvent [
	"Decorative only: let clicks fall through to the morph underneath."

	^ false
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:47'
}
SWASpaceTallyHighlight >> initialize [
	super initialize.
	self
		color: (Color yellow alpha: 0.35);
		borderWidth: 2;
		borderColor: (Color orange alpha: 0.9).
	sizeLabel := StringMorph new
		font: (TextStyle defaultFont emphasized: 1);
		color: Color black.
	self addMorph: sizeLabel
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyHighlight >> rejectsEvent: anEvent [
	"Pass every event through to whatever is beneath us."

	^ true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyHighlight >> setTarget: aMorph bytes: anInteger [
	"Point this overlay at aMorph, label it with anInteger bytes, and place
	it (in the same owner/world as the target, just above it in z-order)."

	target := aMorph.
	sizeLabel contents: (aMorph class name asString , ' -- '
		, (SWASpaceTally formatBytes: anInteger)
		, ' (' , anInteger asStringWithCommas , ' bytes)').
	self followTarget.
	aMorph world ifNotNil: [:w |
		w addMorphFront: self.
		self startStepping].
	^ self
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyHighlight >> step [
	self followTarget
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyHighlight >> stepTime [
	"Track the target a few times a second; cheap and smooth enough."

	^ 200
]
