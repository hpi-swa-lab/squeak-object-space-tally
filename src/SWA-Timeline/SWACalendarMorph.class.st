"
A GitHub-contribution-style calendar over any timestamped SWANode tree (see
SWATemporalView): one cell per DAY, columns are weeks, rows are weekdays, colour
intensity is the chosen measure.

Where the timeline answers ""what was the rhythm of this work"", the calendar answers
""which days were heavy"" -- and because weekday is the y axis, it shows habits the
timeline hides: which days of the week you actually work, how long a streak ran,
where the holidays were.

TWO LEVELS, drilled by clicking:

	#days   the whole span as day cells (the GitHub view)
	#hours  one day, 24 hourly columns, every change in it drawn as its own cell

Click a day to select it (its totals appear in the info line); click the selected
day again to drill into it -- the same click-again-to-zoom idiom the treemaps use.
At the hour level a click selects an individual change, so Show, marks and
cross-referencing work on real nodes. Right-click zooms back out.

Cell colour at day level is an aggregate intensity ramp; at hour level it is the
ordinary per-node colour, so a loaded dataset (coverage, churn, duplication) tints
the individual changes there.
"
Class {
	#name : #SWACalendarMorph,
	#superclass : #SWATemporalView,
	#instVars : [
		'cells',
		'level',
		'dayFocus',
		'eventsByDay',
		'maxDayValue',
		'gridBox',
		'monthBlocks',
		'daySlicing',
		'slotsByDay',
		'maxSlotValue',
		'showMessages',
		'dayGridBox'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:05'
}
SWACalendarMorph >> addMessageCellsFor: aList in: r grid: colsRows [
	"One little rectangle per message, placed in a mini-grid of the size given by
	colsRows -- the SAME for every slot of the day, so a box means one message
	wherever it appears.

	Sizing each slot's grid to its own count (which is what this did) made a box in
	a quiet slot four times the area of a box in a busy one, so the eye read size as
	importance when it only ever meant 'few neighbours'. With one grid for the whole
	day, a slot's fill fraction IS its message count."
	| cols rows |
	aList isEmpty ifTrue: [
		"The empty slot is still a cell, so the grid stays complete and a click
		anywhere in the day lands on a slot rather than on nothing."
		cells add: {#(). r. 0}.
		^ self].
	cols := colsRows first.
	rows := colsRows second.
	aList doWithIndex: [:node :i |
		| c rw x1 x2 y1 y2 |
		c := (i - 1) \\ cols.
		rw := (i - 1) // cols min: rows - 1.
		x1 := r left + (c * r width // cols).
		x2 := r left + ((c + 1) * r width // cols).
		y1 := r top + (rw * r height // rows).
		y2 := r top + ((rw + 1) * r height // rows).
		cells add: {node.
			x1 @ y1 corner: (x2 - 1 max: x1 + 1) @ (y2 - 1 max: y1 + 1).
			self valueForNode: node}]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:16'
}
SWACalendarMorph >> aggregateColorFor: aNodeCollection value: aValue max: aMax [
	"Colour for a cell that stands for MANY events -- a day, a five-minute slot.

	Under a quantity mode that is the plain intensity ramp. Under a CATEGORICAL mode
	it is the cell's DOMINANT category: hue from whichever session / model / package
	contributed most, brightness still from the ramp. Painting an aggregate with one
	member's colour would be a lie; painting it with the majority's, and saying so,
	is the reading you want -- 'this day belonged to that session'.

	Ties go to whichever came first, which is stable because #events is sorted."
	| m counts |
	m := self colorMode.
	(self isCategoricalColorMode: m) ifFalse: [^ self intensityColorFor: aValue max: aMax].
	aNodeCollection isEmpty ifTrue: [^ Color gray: 0.17].
	counts := Dictionary new.
	aNodeCollection do: [:n |
		(n eventCategoryFor: m) ifNotNil: [:k |
			counts at: k put: (counts at: k ifAbsent: [0]) + 1]].
	counts isEmpty ifTrue: [^ Color gray: 0.22].
	^ self categoryColorFor: (self winnerOf: counts) value: aValue max: aMax
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:51'
}
SWACalendarMorph >> breadcrumbString [
	| span |
	self ensureLayout.
	level == #day ifTrue: [
		| dayEvents |
		dayEvents := self eventsOnDay: dayFocus.
		^ dayFocus printString, '   ', dayFocus weekday,
			'   ', dayEvents size printString, ' messages, ',
			(self valueForNodes: dayEvents) printString, ' ', self measureLabel,
			'   24h x 5min grid',
			(showMessages
				ifTrue: ['   one box = one message']
				ifFalse: ['   colour = slot total'])].
	span := self timeSpan ifNil: [^ 'no timestamped events'].
	^ String streamContents: [:s |
		s nextPutAll: (TimeStamp fromSeconds: span first) asDate printString;
			nextPutAll: '  ->  ';
			nextPutAll: (TimeStamp fromSeconds: span second) asDate printString.
		s nextPutAll: '   '; print: self eventsByDay size; nextPutAll: ' active days, ';
			print: self events size; nextPutAll: ' changes'.
		s nextPutAll: '   colour: '; nextPutAll: self measureLabel.
		daySlicing ifNotNil: [:m |
			s nextPutAll: ' per '; print: m; nextPutAll: ' min slot'].
		dayFocus ifNotNil: [:d |
			s nextPutAll: '   [', d printString, ' selected -- click again to drill in]']]
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:01'
}
SWACalendarMorph >> canZoomOut [
	"The pane's Back button asks THIS, and it is what makes Back work after drilling
	into a day.

	The old answer came from overriding #history, which could never be seen:
	SWAView>>canZoomOut reads `history` as its own INSTANCE VARIABLE, so the method
	override was shadowed in the only scope that consulted it and Back was dead at
	day level. Answering the question directly is both correct and honest -- this
	view's navigation state is `level`, not a history stack."
	^ level ~~ #days
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:15'
}
SWACalendarMorph >> categoryColorFor: aKey value: aValue max: aMax [
	"Hue from the category, brightness still from the volume ramp -- so a cell says
	BOTH which session/model/package owned it and how much happened, instead of
	trading one reading for the other.

	nil is 'this cell has no category' (an hour of file reads under 'by package'),
	which must read as neutral rather than as cold."
	| t |
	aValue <= 0 ifTrue: [^ Color gray: 0.17].
	aKey ifNil: [^ Color gray: 0.28].
	t := aMax <= 1
		ifTrue: [1.0]
		ifFalse: [(((aValue max: 1) ln / aMax ln) min: 1.0) max: 0.0].
	^ Color h: aKey asString hash \\ 360 s: 0.45 v: 0.34 + (t * 0.56)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:52'
}
SWACalendarMorph >> cellAt: aLocalPoint [
	cells ifNil: [^ nil].
	^ cells detect: [:c | c second containsPoint: aLocalPoint] ifNone: [nil]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:35'
}
SWACalendarMorph >> cellExtentForColumns: columnCount [
	"Square cells sized to fit both axes: 7 rows must fit the height, columnCount
	columns the width (month gaps already counted in columnCount).

	Clamped to 8..40px: below 8 the grid is mush -- and with the month gaps and the
	2px cell gap there is less room than before, so the floor has to be higher than
	the old 6. Above 40 a three-week history turns into absurd slabs."
	| byWidth byHeight side |
	byWidth := ((self width - self gridOrigin x - 8) / (columnCount max: 1)) truncated.
	byHeight := ((self height - self gridOrigin y - 30) / 7) truncated.
	"A SLICED cell has to hold a sub-grid, so it needs a bigger floor and a bigger
	ceiling: at 15 minutes there are 12 slot columns inside one day, and below about
	24px across they are sub-pixel and the slicing shows nothing. The grid may then
	overflow the pane -- which is the honest trade, since the alternative is drawing
	detail too small to see."
	side := daySlicing
		ifNil: [((byWidth min: byHeight) max: 8) min: 40]
		ifNotNil: [((byWidth min: byHeight) max: self minSlicedCellSide) min: 90].
	^ side @ side
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:30'
}
SWACalendarMorph >> cellGap [
	"Blank pixels between adjacent day cells. Two, not one: at one pixel two
	same-coloured neighbours merge and a week of steady work reads as a single bar,
	which is exactly the mush the grid is supposed to resolve into days."
	^ 2
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:47'
}
SWACalendarMorph >> dayGridColumns [
	"Five-minute slots across one hour. The day view is 24 rows of these, so the
	whole day is a labelled 12 x 24 grid: the same slots the sliced month cell packs
	into 40 pixels, given a whole window and an axis you can read."
	^ 12
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:47'
}
SWACalendarMorph >> dayGridOrigin [
	"Room on the left for hour labels and on top for the minute scale."
	^ 52 @ 34
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:34'
}
SWACalendarMorph >> daySlicing [
	"How finely a day cell is subdivided, in MINUTES per slot, or nil for one solid
	cell per day.

	The unsliced cell answers 'how much happened that day' and throws away the rest:
	four hours in the morning and four spread over eighteen give the same square. A
	sliced cell keeps the shape of the day -- when you started, where the breaks
	were, whether an evening got eaten -- inside the same amount of screen, in the
	way a treemap tile keeps the shape of what is inside it.

	nil by default: at a year's zoom the slots are sub-pixel and the extra detail is
	noise."
	^ daySlicing
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:34'
}
SWACalendarMorph >> daySlicing: minutesOrNil [
	daySlicing := minutesOrNil.
	self flushLayout.
	self refreshChrome
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:36'
}
SWACalendarMorph >> daySlicingOptions [
	"{ minutesPerSlot. label }. nil means one solid cell per day."
	^ {
		{nil. 'Day: one cell'}.
		{60.  'Day: hourly (24 slots)'}.
		{30.  'Day: half-hourly (48 slots)'}.
		{15.  'Day: 15 minutes (96 slots)'}.
		{5.   'Day: 5 minutes (288 slots)'}
	}
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:15'
}
SWACalendarMorph >> dominantCategories [
	"{ byDay . bySlot } for the current colour mode, or nil when it is not
	categorical.

	byDay   jdn -> the category key that contributed most that day
	bySlot  jdn -> Array of the same, one per time slot (nil while unsliced)

	Both in ONE pass over the events, and cached against the mode AND the slicing
	that produced them, because both change what the answer is.

	This exists because the sliced cells could not be coloured by category at all:
	#slotsByDay stores only the per-slot NUMBERS, so a slot had no way to say which
	session it belonged to and the new colour modes silently fell back to the
	intensity ramp as soon as you sliced a day."
	| mode entry byDay bySlot n cache |
	mode := self colorMode.
	(self isCategoricalColorMode: mode) ifFalse: [^ nil].
	entry := self valueOfProperty: #dominantCategories.
	(entry notNil and: [entry first == mode and: [entry second = daySlicing]])
		ifTrue: [^ entry third].
	n := self slotsPerDay.
	byDay := Dictionary new.
	bySlot := Dictionary new.
	self events do: [:e |
		| k t jdn |
		k := e eventCategoryFor: mode.
		k ifNotNil: [
			t := e eventTimeStamp.
			jdn := t asDate julianDayNumber.
			cache := byDay at: jdn ifAbsentPut: [Dictionary new].
			cache at: k put: (cache at: k ifAbsent: [0]) + 1.
			daySlicing ifNotNil: [
				| arr idx d |
				arr := bySlot at: jdn ifAbsentPut: [Array new: n].
				idx := ((t asTime hour * 60 + t asTime minute) // daySlicing) + 1 min: n.
				d := (arr at: idx) ifNil: [arr at: idx put: Dictionary new].
				d at: k put: (d at: k ifAbsent: [0]) + 1]]].
	"Reduce the counts to a single winner, so drawing is a lookup."
	byDay := byDay collect: [:d | self winnerOf: d].
	bySlot := bySlot collect: [:arr |
		arr collect: [:d | d ifNil: [nil] ifNotNil: [self winnerOf: d]]].
	entry := {mode. daySlicing. {byDay. bySlot}}.
	self setProperty: #dominantCategories toValue: entry.
	^ entry third
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:48'
}
SWACalendarMorph >> drawDayAxesOn: aCanvas at: anOrigin [
	"The labels the old hour view never had: every hour named down the left, the
	five-minute scale across the top, a rule every three hours, and the day itself
	spelled out at the bottom.

	Hour labels are drawn on every row where the row is tall enough for the font and
	on every second row where it is not, rather than at a fixed few -- reading a
	grid you cannot index is the problem this view exists to fix."
	| font org w h rowH step |
	dayGridBox ifNil: [^ self].
	font := Preferences standardSystemFont.
	org := dayGridBox first.
	w := dayGridBox second.
	h := dayGridBox third.
	rowH := h / 24.
	step := rowH >= (font height + 1) ifTrue: [1] ifFalse: [2].
	0 to: 23 by: step do: [:hr |
		| y |
		y := org y + (hr * h // 24).
		aCanvas
			drawString: (hr printString padded: #left to: 2 with: $0) , ':00'
			at: ((org x - 40) @ (y + ((rowH - font height) // 2 max: 0))) + anOrigin
			font: font
			color: (Color gray: 0.5)].
	"Rule every three hours, so the eye can jump rather than count."
	0 to: 24 by: 3 do: [:hr |
		| y |
		y := org y + (hr * h // 24).
		aCanvas
			fillRectangle: ((org x @ y extent: w @ 1) translateBy: anOrigin)
			color: (Color gray: 0.3)].
	"Five-minute scale across the top, labelled at the quarters."
	0 to: self dayGridColumns do: [:c |
		| x |
		x := org x + (c * w // self dayGridColumns).
		aCanvas
			fillRectangle: ((x @ (org y - 5) extent: 1 @ 5) translateBy: anOrigin)
			color: (Color gray: (c \\ 3 = 0 ifTrue: [0.45] ifFalse: [0.25])).
		(c \\ 3 = 0 and: [c < self dayGridColumns]) ifTrue: [
			aCanvas
				drawString: ':' , ((c * 5) printString padded: #left to: 2 with: $0)
				at: ((x + 2) @ (org y - 19)) + anOrigin
				font: font
				color: (Color gray: 0.5)]].
	aCanvas
		drawString: dayFocus printString , '   ' , dayFocus weekday
			, '   ' , (self eventsOnDay: dayFocus) size printString , ' messages'
			, (showMessages ifTrue: ['   (one box = one message)'] ifFalse: ['   (colour = ' , self measureLabel , ' per 5 min)'])
			, '   [right-click to go back]'
		at: (org x @ (self height - 18)) + anOrigin
		font: font
		color: (Color gray: 0.55)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:57'
}
SWACalendarMorph >> drawDaySelectionOn: aCanvas at: anOrigin [
	"Yellow frame on the selected day, and green frames on days containing a marked
	node -- the calendar's version of the shared mark feedback."
	| marked |
	"Days are compared by julianDayNumber throughout -- Date>>= is offset-sensitive
	(see #eventsByDay)."
	cells do: [:c |
		(dayFocus notNil and: [c first julianDayNumber = dayFocus julianDayNumber]) ifTrue: [
			aCanvas
				frameRectangle: ((c second expandBy: 1) translateBy: anOrigin)
				width: 1 color: Color yellow]].
	self markedNodes isEmpty ifTrue: [^ self].
	marked := Set new.
	self markedNodes do: [:n |
		n eventTimeStamp ifNotNil: [:t | marked add: t asDate julianDayNumber]].
	cells do: [:c |
		(marked includes: c first julianDayNumber) ifTrue: [
			aCanvas
				frameRectangle: (c second translateBy: anOrigin)
				width: 1 color: (Color green alpha: 0.8)]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:35'
}
SWACalendarMorph >> drawLegendOn: aCanvas at: anOrigin max: aMax [
	"'less [] [] [] [] more' swatch strip, so the intensity ramp is readable as a
	quantity and not just as 'darker/lighter'."
	| font y x |
	font := Preferences standardSystemFont.
	y := self height - 16.
	x := self gridOrigin x.
	aCanvas drawString: 'less' at: (x @ y) + anOrigin font: font color: (Color gray: 0.5).
	x := x + 28.
	0 to: 4 do: [:i |
		aCanvas
			fillRectangle: ((x @ y extent: 10 @ 10) translateBy: anOrigin)
			color: (self intensityColorFor: (aMax raisedTo: i / 4.0) max: aMax).
		x := x + 12].
	aCanvas drawString: 'more   max ', aMax printString, '  ', self measureLabel,
		(daySlicing ifNil: [' per day'] ifNotNil: [:m | ' per ', m printString, ' min'])
		at: (x + 4 @ y) + anOrigin font: font color: (Color gray: 0.5)
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:50'
}
SWACalendarMorph >> drawMessageSelectionOn: aCanvas at: anOrigin [
	"Selection and marks at DAY level, where the cells are messages.

	A separate method from #drawDaySelectionOn:at: because that one compares
	`c first julianDayNumber` -- cells there are Dates, here they are nodes, and
	sharing the method is how the day view came to send #eventTimeStamp to a Date."
	| marked |
	selectedNode ifNotNil: [
		cells do: [:c |
			(c first isCollection not and: [c first == selectedNode]) ifTrue: [
				aCanvas
					frameRectangle: ((c second expandBy: 1) translateBy: anOrigin)
					width: 1 color: Color yellow]]].
	marked := self markedNodes.
	marked isEmpty ifTrue: [^ self].
	cells do: [:c |
		(c first isCollection not and: [marked includes: c first]) ifTrue: [
			aCanvas
				frameRectangle: (c second translateBy: anOrigin)
				width: 1 color: (Color green alpha: 0.8)]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:30'
}
SWACalendarMorph >> drawMonthLabelsOn: aCanvas at: anOrigin [
	"One name CENTRED over each month block, with the year added whenever it changes
	so a multi-year history does not read as one endless run of Januaries.

	Centred over a block it owns, rather than hung at the x of the first cell that
	happened to belong to it: the old version placed labels by scanning cells and
	suppressing collisions, which meant a short month simply lost its name."
	| font org ext lastYear |
	(monthBlocks isNil or: [gridBox isNil]) ifTrue: [^ self].
	font := Preferences standardSystemFont.
	org := gridBox first.
	ext := gridBox second.
	lastYear := nil.
	monthBlocks do: [:b |
		| date label w |
		date := b first.
		label := date monthName copyFrom: 1 to: (3 min: date monthName size).
		date year = lastYear ifFalse: [
			label := label , ' ' , (date year \\ 100) printString.
			lastYear := date year].
		w := font widthOfString: label.
		"Never drawn narrower than it is: a one-week block gets a label that spills
		past its edge rather than being dropped."
		aCanvas
			drawString: label
			at: ((b second + ((b third - w) // 2) max: org x - 30) @ (org y - 16)) + anOrigin
			font: font
			color: (Color gray: 0.6)]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:16'
}
SWACalendarMorph >> drawSlicedDay: aDate in: r on: aCanvas at: anOrigin max: aMax [
	"One day cell as a sub-grid of time slots.

	The empty ground is painted ONCE for the whole cell and only the non-zero slots
	are drawn over it. Most slots of most days are empty -- nobody works 96 quarter
	hours -- so filling each of them individually would be an order of magnitude
	more rectangles for an identical picture.

	Slot boundaries are derived from the CELL EDGES (`left + (i * w // cols)`) rather
	than from a width added to an origin, so the slots tile the cell exactly instead
	of drifting and leaving a seam down one side."
	| arr cols rows cats |
	aCanvas fillRectangle: (r translateBy: anOrigin) color: (self intensityColorFor: 0 max: aMax).
	arr := self slotsByDay at: aDate julianDayNumber ifAbsent: [nil].
	arr ifNil: [^ self].
	"Per-slot dominant category, nil under a quantity mode -- see #dominantCategories.
	Looked up ONCE for the day rather than per slot."
	cats := self dominantCategories
		ifNil: [nil]
		ifNotNil: [:d | (d second at: aDate julianDayNumber ifAbsent: [nil])].
	cols := self slotColumns.
	rows := (arr size + cols - 1) // cols.
	arr doWithIndex: [:v :i |
		v > 0 ifTrue: [
			| c rr x1 x2 y1 y2 |
			c := (i - 1) \\ cols.
			rr := (i - 1) // cols.
			x1 := r left + (c * r width // cols).
			x2 := r left + ((c + 1) * r width // cols).
			y1 := r top + (rr * r height // rows).
			y2 := r top + ((rr + 1) * r height // rows).
			aCanvas
				fillRectangle: ((x1 @ y1 corner: (x2 max: x1 + 1) @ (y2 max: y1 + 1))
					translateBy: anOrigin)
				color: (cats
					ifNil: [self intensityColorFor: v max: aMax]
					ifNotNil: [self categoryColorFor: (cats at: i) value: v max: aMax])]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:30'
}
SWACalendarMorph >> drawWeekdayLabelsOn: aCanvas at: anOrigin [
	"ALL SEVEN weekday names when the rows are tall enough to hold them, every other
	one when they are not.

	Labelling only Mon/Wed/Fri (as this did) leaves you counting rows to find out
	whether a cell is a Tuesday or a Thursday -- on a chart whose entire reason for
	putting weekday on the y axis is that the weekday matters.

	Placed relative to the GRID, not to whichever cells exist: a span with no
	Wednesday in it must still label that row."
	| font org ext step |
	gridBox ifNil: [^ self].
	font := Preferences standardSystemFont.
	org := gridBox first.
	ext := gridBox second.
	step := ext y >= (font height + 2) ifTrue: [1] ifFalse: [2].
	1 to: 7 by: step do: [:row |
		aCanvas
			drawString: (#('Mon' 'Tue' 'Wed' 'Thu' 'Fri' 'Sat' 'Sun') at: row)
			at: ((org x - 34) @ (org y + ((row - 1) * ext y) + ((ext y - font height) // 2))) + anOrigin
			font: font
			color: (Color gray: 0.5)]
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:49'
}
SWACalendarMorph >> drillIntoDay: aDate [
	"Focus one day: the labelled 24 x 12 grid of five-minute slots (see #layoutDay).
	Refused when the day is empty -- there would be nothing to show and no obvious
	way back."
	(self eventsOnDay: aDate) isEmpty ifTrue: [^ self].
	dayFocus := aDate.
	level := #day.
	self flushLayout.
	self refreshChrome
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:49'
}
SWACalendarMorph >> ensureLayout [
	cells ifNotNil: [^ self].
	level == #day
		ifTrue: [self layoutDay]
		ifFalse: [self layoutDays]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:56'
}
SWACalendarMorph >> eventsByDay [
	"Dictionary of JULIAN DAY NUMBER -> OrderedCollection of events, built once.

	Keyed by the integer day number and NOT by Date, which looks like the obvious
	key and is a trap: Date is a Timespan, so Date>>= compares its `start`
	DateAndTime -- including the UTC OFFSET. A Date from `aTimeStamp asDate` carries
	+00:00 while one built by Date arithmetic carries the local offset, so two Dates
	for the same calendar day are unequal AND hash differently. Every lookup then
	silently misses and the whole calendar renders empty."
	eventsByDay ifNotNil: [^ eventsByDay].
	eventsByDay := Dictionary new.
	self events do: [:n |
		| jdn |
		jdn := n eventTimeStamp asDate julianDayNumber.
		(eventsByDay at: jdn ifAbsentPut: [OrderedCollection new]) add: n].
	^ eventsByDay
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:56'
}
SWACalendarMorph >> eventsOnDay: aDate [
	"The events on a calendar day. ALWAYS go through this rather than indexing
	#eventsByDay with a Date -- see the comment there for why Date is not a usable
	dictionary key."
	aDate ifNil: [^ #()].
	^ self eventsByDay at: aDate julianDayNumber ifAbsent: [#()]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:33'
}
SWACalendarMorph >> exploreSelected [
	selectedNode ifNotNil: [:n | ToolSet explore: n]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:16'
}
SWACalendarMorph >> flushLayout [
	cells := nil.
	monthBlocks := nil.
	gridBox := nil.
	eventsByDay := nil.
	maxDayValue := nil.
	slotsByDay := nil.
	maxSlotValue := nil.
	self removeProperty: #dominantCategories.
	super flushLayout
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:30'
}
SWACalendarMorph >> gridOffsetForColumns: columnCount extent: cellExtent [
	"Extra offset that CENTRES the grid in the pane. Cells are capped in size, so a
	short history would otherwise sit in the top-left corner with most of the window
	empty. Never negative, so a long history still starts at the left margin and
	simply overflows to the right."
	| org gridW gridH |
	org := self gridOrigin.
	gridW := (columnCount * cellExtent x) rounded.
	gridH := 7 * cellExtent y.
	^ (((self width - org x - 8 - gridW) // 2) max: 0)
		@ (((self height - org y - 34 - gridH) // 2) max: 0)
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:53'
}
SWACalendarMorph >> gridOrigin [
	"Top-left of the cell grid: room on the left for weekday labels (and clear of the
	panel's Marks flap tab, which floats over the left edge), and on top for month
	labels."
	^ 48 @ 22
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:49'
}
SWACalendarMorph >> initialize [
	super initialize.
	level := #days.
	"Boxes on by default: 'what happened in that five minutes' is why anyone drills
	into a day, and the aggregate ramp is the fallback for a day too crowded to read
	message by message."
	showMessages := true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:33'
}
SWACalendarMorph >> inspectSelection [
	"Open an inspector on EVERYTHING known about the selected message -- the same
	Dictionary the Flow view shows (SWAChatFlowMorph>>inspectSelection), because for
	a calendar event #details resolves to the real part and answers exactly that.

	Deliberately a Dictionary rather than the node itself: the interesting facts are
	spread across the part, its message (which is where cost and tokens live), its
	session and the raw stored document, and an inspector on the node would show
	only the first of those."
	| n |
	n := selectedNode ifNil: [^ self inform: 'Select a message first.'].
	((n respondsTo: #details) ifTrue: [n details] ifFalse: [n]) inspect
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:06'
}
SWACalendarMorph >> layoutDay [
	"ONE DAY as a labelled grid: 24 hour ROWS by 12 five-minute COLUMNS.

	This replaces the old hour view, which stacked each hour's events into a
	column of equal-height bars. That threw away WHEN inside the hour anything
	happened -- the one thing you drill into a day to find out -- and it had no
	scale on either axis, so a tall column told you a count and nothing else.

	Two renderings of the same grid, per #showMessages:

	  off  each 5-minute slot is one cell on the intensity ramp -- the shape of
	       the day, comparable slot to slot
	  on   each slot is subdivided into ONE LITTLE RECTANGLE PER MESSAGE, packed
	       into a mini-grid. Those rectangles are real nodes, so selection, marks
	       and the Show pane operate on individual messages here.

	Slot boundaries come from the grid EDGES rather than from a width added to an
	origin, so rows and columns tile exactly instead of drifting."
	| org w h dayEvents bySlot cols grid |
	cells := OrderedCollection new.
	dayFocus ifNil: [^ self].
	org := self dayGridOrigin.
	cols := self dayGridColumns.
	w := (self width - org x - 10) max: 60.
	h := (self height - org y - 26) max: 48.
	dayGridBox := {org. w. h}.
	dayEvents := self eventsOnDay: dayFocus.
	bySlot := Dictionary new.
	dayEvents do: [:n |
		| t idx |
		t := n eventTimeStamp.
		idx := (t asTime hour * 12) + (t asTime minute // 5).
		(bySlot at: idx ifAbsentPut: [OrderedCollection new]) add: n].
	"ONE grid shape for the whole day, from the fullest slot -- see
	#messageGridFor:in:. Computed before any cell is placed, because every slot has
	to use it."
	grid := showMessages
		ifTrue: [self
			messageGridFor: (bySlot inject: 1 into: [:m :list | m max: list size])
			in: (w // cols) @ (h // 24)]
		ifFalse: [#(1 1)].
	0 to: 23 do: [:hr |
		| y1 y2 |
		y1 := org y + (hr * h // 24).
		y2 := org y + ((hr + 1) * h // 24).
		0 to: cols - 1 do: [:c |
			| x1 x2 rect list |
			x1 := org x + (c * w // cols).
			x2 := org x + ((c + 1) * w // cols).
			rect := x1 @ y1 corner: (x2 - 1 max: x1 + 1) @ (y2 - 1 max: y1 + 1).
			list := bySlot at: (hr * 12) + c ifAbsent: [#()].
			showMessages
				ifTrue: [self addMessageCellsFor: list in: rect grid: grid]
				ifFalse: [cells add: {list. rect. self valueForNodes: list}]]]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:30'
}
SWACalendarMorph >> layoutDays [
	"One BLOCK PER MONTH, each a grid of week columns by weekday rows, separated by
	a gap. Rows are a fixed weekday across the whole calendar, which is the point of
	the layout and only works because each block starts on the Monday on or before
	its first day.

	Cells are inset by #cellGap rather than by one pixel, so days read as separate
	tiles instead of merging into a wall of colour."
	| plan ext org totalCols gapPx x gap |
	cells := OrderedCollection new.
	monthBlocks := OrderedCollection new.
	plan := self monthPlan.
	plan isEmpty ifTrue: [^ self].
	totalCols := (plan inject: 0 into: [:a :b | a + (b third)])
		+ ((plan size - 1) * self monthGapColumns).
	ext := self cellExtentForColumns: totalCols.
	gapPx := (ext x * self monthGapColumns) rounded.
	gap := self cellGap.
	org := self gridOrigin + (self gridOffsetForColumns: totalCols extent: ext).
	"Remember the grid geometry: the weekday labels must be placed from the GRID and
	not from whichever cells happen to exist -- a span with no Wednesday in it would
	otherwise silently lose that row's label."
	gridBox := {org. ext}.
	x := org x.
	plan do: [:block |
		| blockFirst blockLast aligned weeks d |
		blockFirst := block first.
		blockLast := block second.
		weeks := block third.
		aligned := blockFirst subtractDays: (self weekdayIndexOf: blockFirst) - 1.
		d := aligned.
		0 to: weeks - 1 do: [:wk |
			1 to: 7 do: [:row |
				(d julianDayNumber between: blockFirst julianDayNumber and: blockLast julianDayNumber)
					ifTrue: [
						cells add: {d.
							(x + (wk * ext x)) @ (org y + ((row - 1) * ext y))
								extent: (ext x - gap max: 1) @ (ext y - gap max: 1).
							self valueForDay: d}].
				d := d addDays: 1]].
		monthBlocks add: {blockFirst. x. weeks * ext x}.
		x := x + (weeks * ext x) + gapPx]
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:48'
}
SWACalendarMorph >> maxDayCellValue [
	"Largest single message of the focused day -- the scale for the empty-slot
	ground while message boxes are shown."
	^ cells inject: 1 into: [:m :c | c first isCollection ifTrue: [m] ifFalse: [m max: c third]]
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:48'
}
SWACalendarMorph >> maxDaySlotValue [
	"Busiest 5-minute slot of the focused day. Scoped to the DAY, not to the whole
	calendar: you drilled in to read this day's shape, and scaling it against the
	busiest slot of a three-month history would flatten a normal day to nothing."
	^ cells inject: 1 into: [:m :c | c first isCollection ifTrue: [m max: c third] ifFalse: [m]]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:56'
}
SWACalendarMorph >> maxDayValue [
	maxDayValue ifNotNil: [^ maxDayValue].
	maxDayValue := 1.
	self eventsByDay valuesDo: [:list |
		maxDayValue := maxDayValue max: (self valueForNodes: list)].
	^ maxDayValue
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:35'
}
SWACalendarMorph >> maxSlotValue [
	"Busiest single SLOT anywhere, which sets the ramp while slicing is on.

	Not #maxDayValue: a day's total is many times its busiest quarter hour, so
	scaling slots against it would paint the entire calendar at the cold end and the
	detail you turned slicing on for would be invisible."
	maxSlotValue ifNotNil: [^ maxSlotValue].
	maxSlotValue := 1.
	self slotsByDay valuesDo: [:arr |
		arr do: [:v | maxSlotValue := maxSlotValue max: v]].
	^ maxSlotValue
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:05'
}
SWACalendarMorph >> messageGridFor: maxCount in: slotExtent [
	"{ columns . rows } for the message mini-grid, sized once for the WHOLE day from
	the fullest five-minute slot, so every box in the day is the same size.

	Columns come from the slot's ASPECT RATIO -- sqrt(n * w / h) is the column count
	that makes the boxes square -- and rows are then whatever is needed to hold the
	fullest slot. A slot with three messages fills three of those boxes and leaves
	the rest as ground, which is exactly the reading wanted: fill fraction is
	message count."
	| cols rows |
	maxCount <= 1 ifTrue: [^ #(1 1)].
	cols := ((maxCount * slotExtent x / (slotExtent y max: 1)) sqrt rounded max: 1) min: maxCount.
	rows := (maxCount + cols - 1) // cols.
	^ {cols. rows}
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:35'
}
SWACalendarMorph >> minSlicedCellSide [
	"Smallest day cell worth slicing at the current granularity: two pixels per slot
	column, so a lit slot is at least visible. Finer slicing therefore forces bigger
	cells, and a year at 5-minute detail simply will not fit on screen -- correctly,
	because it could not be read if it did."
	^ (self slotColumns * 2) max: 16
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:29'
}
SWACalendarMorph >> monthGapColumns [
	"Width of the gap between two month blocks, in CELL WIDTHS. Wide enough to read
	as a break, narrow enough that a year still fits."
	^ 0.7
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:29'
}
SWACalendarMorph >> monthPlan [
	"One entry per month in the span: { firstDayShown . lastDayShown . weekColumns }.

	Laying the year out as ONE continuous run of weeks -- which is what this did, and
	what GitHub does -- gives a wall of cells with nothing to hold on to: you cannot
	tell June from July without counting, and the month labels float over column
	boundaries that mean nothing. A block per month, separated by a gap, gives the
	eye the unit it is actually looking for.

	Each block starts on the Monday ON OR BEFORE its first day, so the weekday rows
	still line up across the whole calendar."
	| span first last out d |
	span := self timeSpan ifNil: [^ #()].
	first := (TimeStamp fromSeconds: span first truncated) asDate.
	last := (TimeStamp fromSeconds: span second truncated) asDate.
	out := OrderedCollection new.
	d := first.
	[d julianDayNumber <= last julianDayNumber] whileTrue: [
		| mLast blockFirst blockLast aligned weeks |
		mLast := Date newDay: d daysInMonth month: d monthIndex year: d year.
		blockFirst := d.
		blockLast := mLast julianDayNumber <= last julianDayNumber ifTrue: [mLast] ifFalse: [last].
		aligned := blockFirst subtractDays: (self weekdayIndexOf: blockFirst) - 1.
		weeks := ((blockLast julianDayNumber - aligned julianDayNumber) // 7) + 1.
		out add: {blockFirst. blockLast. weeks}.
		d := blockLast addDays: 1].
	^ out asArray
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:49'
}
SWACalendarMorph >> mouseDown: evt [
	"Month level: click selects the day, clicking the SELECTED day again focuses it
	-- the treemap's click-again-to-zoom idiom, so a double click drills straight in.
	Day level: click selects the message under the cursor; shift+click marks it. A
	click on a SLOT (no message boxes, or an empty slot) selects the slot's biggest
	message, which is the one you almost certainly meant.
	Right-click: menu, which is also how you come back out."
	| local cell |
	self takeKeyboardFocusFrom: evt.
	local := evt position - self position.
	evt yellowButtonPressed ifTrue: [^ self showMenuAt: evt].
	cell := self cellAt: local.
	cell ifNil: [^ self].
	level == #day ifTrue: [
		| node |
		node := cell first isCollection
			ifTrue: [cell first isEmpty
				ifTrue: [nil]
				ifFalse: [cell first inject: cell first first into: [:best :n |
					(self valueForNode: n) > (self valueForNode: best) ifTrue: [n] ifFalse: [best]]]]
			ifFalse: [cell first].
		node ifNil: [^ self].
		evt shiftPressed
			ifTrue: [self toggleMark: node. ^ self flushCache].
		^ self selectNode: node].
	"Month level."
	(dayFocus notNil and: [dayFocus julianDayNumber = cell first julianDayNumber])
		ifTrue: [^ self drillIntoDay: cell first].
	dayFocus := cell first.
	selectedNode := nil.
	self flushCache.
	self refreshChrome
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:08'
}
SWACalendarMorph >> renderDayOn: aCanvas at: anOrigin [
	"One day: the 24 x 12 grid, hour labels down the left, a five-minute scale
	across the top, and hour rules so a row can be found without counting."
	| max |
	max := showMessages
		ifTrue: [self maxDayCellValue]
		ifFalse: [self maxDaySlotValue].
	cells do: [:c |
		c first isCollection
			ifTrue: ["a slot: aggregate colour, empty slots included"
				aCanvas
					fillRectangle: (c second translateBy: anOrigin)
					color: (self aggregateColorFor: c first value: c third max: max)]
			ifFalse: ["a message: the ordinary node colour, so a loaded dataset tints it"
				aCanvas
					fillRectangle: (c second translateBy: anOrigin)
					color: (self colorForNode: c first)]].
	self drawDayAxesOn: aCanvas at: anOrigin.
	self drawMessageSelectionOn: aCanvas at: anOrigin
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:16'
}
SWACalendarMorph >> renderDaysOn: aCanvas at: anOrigin [
	"Day cells, weekday labels down the left, a month name over each block, and a
	legend. A cell is one square when unsliced and a sub-grid of time slots when
	sliced; either way its colour comes from the volume ramp under a quantity mode
	and from its dominant category under a categorical one."
	| max byDay |
	daySlicing
		ifNil: [
			max := self maxDayValue.
			"Precomputed dominants, not a recount per cell: counting a day's events
			inside the draw loop is O(all events) per frame."
			byDay := self dominantCategories ifNil: [nil] ifNotNil: [:d | d first].
			cells do: [:c |
				aCanvas
					fillRectangle: (c second translateBy: anOrigin)
					color: (byDay
						ifNil: [self intensityColorFor: c third max: max]
						ifNotNil: [self
							categoryColorFor: (byDay at: c first julianDayNumber ifAbsent: [nil])
							value: c third max: max])]]
		ifNotNil: [
			"Scaled against the busiest SLOT, not the busiest day -- see #maxSlotValue."
			max := self maxSlotValue.
			cells do: [:c |
				self drawSlicedDay: c first in: c second on: aCanvas at: anOrigin max: max]].
	self drawWeekdayLabelsOn: aCanvas at: anOrigin.
	self drawMonthLabelsOn: aCanvas at: anOrigin.
	self drawLegendOn: aCanvas at: anOrigin max: max.
	self drawDaySelectionOn: aCanvas at: anOrigin
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:49'
}
SWACalendarMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	aCanvas fillRectangle: (anOrigin extent: self extent) color: (Color gray: 0.12).
	cells ifNil: [^ self].
	level == #day
		ifTrue: [self renderDayOn: aCanvas at: anOrigin]
		ifFalse: [self renderDaysOn: aCanvas at: anOrigin]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:49'
}
SWACalendarMorph >> selectionPathString [
	"At hour level the selection is a node, so defer to the shared version. At day
	level it is a DAY, which has no node -- report the day's totals and its busiest
	packages instead, which is the useful answer at that zoom."
	| dayEvents counts top |
	level == #day ifTrue: [^ super selectionPathString].
	dayFocus ifNil: [^ ''].
	dayEvents := self eventsOnDay: dayFocus.
	dayEvents isEmpty ifTrue: [^ dayFocus printString, '   (nothing)'].
	counts := Dictionary new.
	dayEvents do: [:n |
		| k |
		k := (n respondsTo: #packageName) ifTrue: [n packageName] ifFalse: [nil].
		k ifNil: [k := n parent ifNil: ['?'] ifNotNil: [:p | p name]].
		counts at: k put: (counts at: k ifAbsent: [0]) + (self valueForNode: n)].
	top := (counts associations asSortedCollection: [:a :b | a value >= b value])
		asOrderedCollection first: (3 min: counts size).
	^ String streamContents: [:s |
		s nextPutAll: dayFocus printString; nextPutAll: ' '; nextPutAll: dayFocus weekday;
			nextPutAll: '   '; print: dayEvents size; nextPutAll: ' changes, ';
			print: (self valueForNodes: dayEvents); nextPutAll: ' ', self measureLabel;
			nextPutAll: '   top: '.
		top do: [:a | s nextPutAll: a key asString; nextPutAll: ' ('; print: a value; nextPut: $)]
			separatedBy: [s nextPutAll: ', ']]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:33'
}
SWACalendarMorph >> showMenuAt: evt [
	| menu |
	menu := MenuMorph new defaultTarget: self.
	level == #day ifTrue: [
		menu add: 'back to calendar' selector: #zoomOut argument: nil.
		menu addLine].
	self measureOptions do: [:pair |
		menu
			add: (self measure == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #measure: argument: pair first].
	level == #days ifTrue: [
		menu addLine.
		self daySlicingOptions do: [:pair |
			menu
				add: (daySlicing = pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
				selector: #daySlicing: argument: pair first]].
	level == #day ifTrue: [
		menu addLine.
		menu add: (showMessages ifTrue: ['* '] ifFalse: ['   ']), 'One box per message'
			selector: #showMessages: argument: true.
		menu add: (showMessages ifFalse: ['* '] ifTrue: ['   ']), 'Colour the 5-minute slot'
			selector: #showMessages: argument: false].
	"Colour modes at BOTH levels. They used to appear only after drilling into a
	day, which is backwards: 'which sessions owned which days' is a question about
	the whole calendar, and an aggregate cell can answer it with its dominant
	category -- see #aggregateColorFor:value:max:."
	menu addLine.
	self colorModeOptions do: [:pair |
		menu
			add: (self colorMode == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #colorMode: argument: pair first].
	selectedNode ifNotNil: [
		menu addLine.
		menu add: 'inspect message (all data)' selector: #inspectSelection argument: nil.
		menu add: 'explore message' selector: #exploreSelected argument: nil].
	menu popUpEvent: evt in: self world
]

{
	#category : #'day view',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:50'
}
SWACalendarMorph >> showMessages: aBoolean [
	"Whether a focused day draws one little rectangle per MESSAGE inside each
	five-minute slot, or fills the slot with its aggregate colour. See #layoutDay."
	showMessages := aBoolean.
	selectedNode := nil.
	self flushLayout.
	self refreshChrome
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:34'
}
SWACalendarMorph >> slotColumns [
	"Columns in the sub-grid inside one day cell. Chosen so that each ROW is a whole
	number of hours and the slots come out roughly square:

		 24 slots (hourly)  -> 6 x 4, each row a 6-hour band
		 96 slots (15 min)  -> 12 x 8, each row 3 hours
		288 slots (5 min)   -> 24 x 12, each row 2 hours

	Slots run left to right then top to bottom, so the cell reads as a day: morning
	at the top, evening at the bottom."
	| n |
	n := self slotsPerDay.
	n <= 1 ifTrue: [^ 1].
	n <= 24 ifTrue: [^ 6].
	n <= 96 ifTrue: [^ 12].
	^ 24
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:35'
}
SWACalendarMorph >> slotsByDay [
	"JULIAN DAY NUMBER -> Array of per-slot measure values, built in ONE pass over
	the events. A per-cell scan would be 100 days x 42000 events.

	Keyed by day number, never by Date -- see #eventsByDay for why Date is not a
	usable dictionary key here."
	| n cols |
	slotsByDay ifNotNil: [^ slotsByDay].
	slotsByDay := Dictionary new.
	daySlicing ifNil: [^ slotsByDay].
	n := self slotsPerDay.
	cols := self slotColumns.
	self events do: [:e |
		| t jdn idx arr |
		t := e eventTimeStamp.
		t ifNotNil: [
			jdn := t asDate julianDayNumber.
			idx := ((t asTime hour * 60 + t asTime minute) // daySlicing) + 1 min: n.
			arr := slotsByDay at: jdn ifAbsentPut: [Array new: n withAll: 0].
			arr at: idx put: (arr at: idx) + (self valueForNode: e)]].
	^ slotsByDay
]

{
	#category : #slicing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:34'
}
SWACalendarMorph >> slotsPerDay [
	^ daySlicing ifNil: [1] ifNotNil: [:m | 1440 // m]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:56'
}
SWACalendarMorph >> valueForDay: aDate [
	^ self valueForNodes: (self eventsOnDay: aDate)
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:50'
}
SWACalendarMorph >> viewKind [
	^ #calendar
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:51'
}
SWACalendarMorph >> weekdayIndexOf: aDate [
	"1 = Monday .. 7 = Sunday. Squeak's #weekdayIndex is Sunday-based; the calendar
	reads better with the weekend at the bottom."
	^ (aDate weekdayIndex + 5) \\ 7 + 1
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:15'
}
SWACalendarMorph >> winnerOf: aCountDictionary [
	"The key with the most counts. Ties go to whichever the dictionary yields first
	-- arbitrary but stable within a build, which is all a colour needs."
	| best bestN |
	best := nil.
	bestN := 0.
	aCountDictionary keysAndValuesDo: [:k :v | v > bestN ifTrue: [best := k. bestN := v]].
	^ best
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:52'
}
SWACalendarMorph >> zoomOut [
	"Back to the day grid. Also what the panel's Back button reaches."
	level == #days ifTrue: [^ self].
	level := #days.
	selectedNode := nil.
	self flushLayout.
	self refreshChrome
]
