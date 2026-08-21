Class {
	#name : #FormGraph,
	#superclass : #Object,
	#instVars : [
		'position',
		'form',
		'width',
		'height',
		'blt'
	],
	#category : #'SWA-GCStats'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'jl 10/28/2005 16:05'
}
FormGraph class >> new [
	^super new initialize
]

{
	#category : #adding,
	#'squeak_changestamp' : 'jl 10/25/2005 17:06'
}
FormGraph >> addValue: aValue [ 
	^self addValue: aValue color: Color black.
]

{
	#category : #adding,
	#'squeak_changestamp' : 'jl 10/25/2005 17:06'
}
FormGraph >> addValue: aValue color: aColor [
	^self addValue: aValue color: aColor bgColor: Color white.
]

{
	#category : #adding,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:12'
}
FormGraph >> addValue: aValue color: aColor bgColor: bgColor [
	"Scroll left 2px, clear the new 2px background column, then draw a 1px bar of height aValue
	up from the bottom -- all via the retained BitBlt + cached halftones, no allocation."
	| drawValue |
	drawValue := aValue min: height.
	self shiftBy: 2.
	blt sourceForm: nil; fillColor: bgColor.
	blt destX: width - 2 destY: 0 width: 2 height: height.
	blt copyBits.
	blt fillColor: aColor.
	blt destX: width - 1 destY: height - drawValue width: 1 height: drawValue.
	blt copyBits
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 10/25/2005 17:40'
}
FormGraph >> defaultHeight [
	^60
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 10/25/2005 17:02'
}
FormGraph >> defaultWidth [
	^480
]

{
	#category : #adding,
	#'squeak_changestamp' : 'jl 11/8/2005 16:48'
}
FormGraph >> display [
	form displayAt: position.
]

{
	#category : #adding,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:12'
}
FormGraph >> drawFrom: fromValue to: toValue color: aColor width: aWidth [
	"Fill the rightmost aWidth-pixel column between fromValue and toValue (measured up from the
	bottom) with aColor, reusing the retained BitBlt and a cached halftone -- no allocation."
	| drawToValue h |
	drawToValue := toValue min: height.
	h := drawToValue - fromValue.
	h <= 0 ifTrue: [^ self].
	blt sourceForm: nil; fillColor: aColor.
	blt destX: width - aWidth destY: height - drawToValue width: aWidth height: h.
	blt copyBits

]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 7/14/2006 10:31'
}
FormGraph >> form [
	"Answer the form of the receiver"
	^form
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 11/8/2005 21:04'
}
FormGraph >> height [
	^height
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 11/8/2005 21:06'
}
FormGraph >> height: aValue [
	height := aValue.
	self updateForm.
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 11/8/2005 21:07'
}
FormGraph >> initialize [
	position := 0@0.
	self width: 480 height: 50.
	
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:43'
}
FormGraph >> position [
	^position ifNil: [position := 0@0]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 11/8/2005 16:44'
}
FormGraph >> position: aPosition [
	position := aPosition
]

{
	#category : #adding,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 12:57'
}
FormGraph >> shiftBy: aStep [
	"Scroll the whole form left by aStep pixels, in place, reusing the retained BitBlt so no
	BitBlt / Rectangle / Point is allocated. Source is the form itself, shifted left."
	blt sourceForm: form; halftoneForm: nil.
	blt sourceX: aStep; sourceY: 0.
	blt destX: 0 destY: 0 width: width height: height.
	blt copyBits
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:12'
}
FormGraph >> updateForm [
	"32 bit: at depth 8 every fill is quantized to the standard palette, which
	turns pale tints into plain grays."
	form := Form extent: width@height depth: 32.
	"One BitBlt retained for the whole graph lifetime and mutated in place by every draw,
	so the per-frame path (scroll + fills) allocates no BitBlt. Rebuilt with the form since
	it binds destForm. Fill colours are interned (GcGraph palette) and Color caches its own
	depth-32 bit pattern, so #fillColor: on a hit allocates nothing -- no halftone cache needed."
	blt := BitBlt toForm: form.
	blt sourceForm: nil; combinationRule: Form over.	
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 11/8/2005 21:04'
}
FormGraph >> width [
	^width
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 11/8/2005 21:06'
}
FormGraph >> width: aValue [
	width := aValue.
	self updateForm.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 11/8/2005 21:06'
}
FormGraph >> width: aWidth height: aHeight [
	width := aWidth.
	height := aHeight.
	self updateForm.
]
