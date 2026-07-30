Class {
	#name : #FormGraph,
	#superclass : #Object,
	#instVars : [
		'position',
		'form',
		'width',
		'height'
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
	#'squeak_changestamp' : 'jl 7/14/2006 10:56'
}
FormGraph >> addValue: aValue color: aColor bgColor: bgColor [
	| formBounds drawValue |
	drawValue := aValue min: self height.
	formBounds := form boundingBox.

	form copy: formBounds
		from: form 
		to: -2@0 rule: Form over.

	form 
			fill: (self width-2@0  corner: (self width@ (self height)))
			rule: Form over 
			fillColor: bgColor.

	form 
			fill: (((self width-1) @ (self height - drawValue)) 
					corner: (self width@self height))
			rule: Form over 
			fillColor: aColor.
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
	#'squeak_changestamp' : 'jl 11/8/2005 21:04'
}
FormGraph >> drawFrom: fromValue to: toValue color: aColor width: aWidth [
	| drawToValue |
	drawToValue := toValue min: self height.
	
	form 
			fill: (((self width-aWidth) @ (self height - drawToValue)) 
					corner: (self width@(self height - fromValue)))
			rule: Form over 
			fillColor: aColor.


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
	#'squeak_changestamp' : 'jl 11/8/2005 17:06'
}
FormGraph >> shiftBy: aStep [

	form copy:  form boundingBox
		from: form 
		to: (-1 * aStep)@0 rule: Form over.

]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 11/8/2005 21:02'
}
FormGraph >> updateForm [
	form := Form extent: width@height depth: 8.	
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
