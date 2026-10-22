"
A text field with a drop-down of the likely answers beside it, for an input whose valid values are an open set but whose useful ones are a short list: a commit hash is usually one of the recent ones, but may be any hash, pasted from anywhere.

DropDownChoiceMorph is pick-only and a bare text field hides what the valid answers are; this is both. Picking and typing go down the same path, so the model sees one kind of change.

The model supplies three plugged selectors: a getter answering the current value, a setter taking the new one as a String, and a choices selector answering Associations of value -> menu label.
"
Class {
	#name : #SWAComboFieldMorph,
	#superclass : #Morph,
	#instVars : [
		'model',
		'getSelector',
		'setSelector',
		'choicesSelector',
		'field'
	],
	#classVars : [
		'DropDownMarker'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:23'
}
SWAComboFieldMorph class >> dropDownMarker [
	"A down-pointing triangle, drawn rather than typed: the default text font has no
	glyph for one."
	^ DropDownMarker ifNil: [
		| form |
		form := Form extent: 9 @ 5 depth: 1.
		form getCanvas
			drawPolygon: {0 @ 0. 9 @ 0. 4 @ 5}
			fillStyle: Color black.
		DropDownMarker := (ColorForm mappingWhiteToTransparentFrom: form)
			colors: {Color transparent. Color gray: 0.9};
			yourself]
]

{
	#category : #'model access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:40'
}
SWAComboFieldMorph >> acceptFieldText: aStringOrText [
	"Enter in the field, or a pick from the drop-down: one path to the model."
	model perform: setSelector with: aStringOrText asString withBlanksTrimmed
]

{
	#category : #'model access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:40'
}
SWAComboFieldMorph >> fieldText [
	"The model's current value, as a String."
	^ ((model perform: getSelector) ifNil: ['']) asString
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:23'
}
SWAComboFieldMorph >> initialize [
	super initialize.
	self
		color: Color transparent;
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 3;
		hResizing: #shrinkWrap;
		vResizing: #shrinkWrap.
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:25'
}
SWAComboFieldMorph >> on: aModel get: getSel set: setSel choices: choicesSel label: aLabelString width: anInteger [
	"Build the row: caption, editable field, drop-down button. The field edits through
	ME, not straight through to the model, so typing and picking normalise the same way.

	Sizing a TextMorph is fiddly: while it is auto-fit it sizes to its CONTENT and
	ignores #extent: (see SWAPane>>newSearchField, same dance). That is used here to
	MEASURE one line in the current font before the box is pinned -- a guessed height
	clips the descenders."
	| labelMorph button lineHeight |
	model := aModel.
	getSelector := getSel.
	setSelector := setSel.
	choicesSelector := choicesSel.
	labelMorph := StringMorph new
		contents: aLabelString;
		font: (TextStyle default fontOfPointSize: 10);
		color: (Color gray: 0.75);
		yourself.
	field := SWAComboTextMorph new
		combo: self;
		backgroundColor: Color white;
		textColor: Color black;
		yourself.
	field contents: 'Agjy'.
	lineHeight := field height.
	field hResizing: #rigid; vResizing: #rigid.
	field contents: '' wrappedTo: anInteger.
	field extent: anInteger @ (lineHeight + 4).
	field margins: (5 @ 2 corner: 3 @ 2).
	"One line, always: wrapped, a value too long for the box runs onto a second line
	that the pinned height then cuts off. Unwrapped it is simply clipped."
	field wrapFlag: false.
	button := IconicButton new
		labelGraphic: self class dropDownMarker;
		color: (Color gray: 0.3);
		borderWidth: 0;
		target: self;
		actionSelector: #popUpChoices;
		hResizing: #rigid;
		vResizing: #rigid;
		yourself.
	button setBalloonText: 'Choose ', aLabelString asString.
	self
		addMorphBack: labelMorph;
		addMorphBack: field;
		addMorphBack: button.
	self refresh.
	^ self
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:40'
}
SWAComboFieldMorph >> popUpChoices [
	"Offer the model's known values -- Associations of value -> menu label. Picking one
	goes through the same setter as typing one."
	| choices picked |
	choices := (model perform: choicesSelector) asArray.
	choices isEmpty ifTrue: [^ self].
	picked := UIManager default
		chooseFrom: (choices collect: [:each | each value])
		values: (choices collect: [:each | each key]).
	picked ifNil: [^ self].
	self acceptFieldText: picked.
	self refresh
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:40'
}
SWAComboFieldMorph >> refresh [
	"Reload the editor from the model, for when the value changed behind the field."
	field ifNil: [^ self].
	field contents: self fieldText
]
