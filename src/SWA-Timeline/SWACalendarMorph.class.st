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
		'gridBox'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:57'
}
SWACalendarMorph >> breadcrumbString [
	| span |
	self ensureLayout.
	level == #hours ifTrue: [
		| dayEvents |
		dayEvents := self eventsOnDay: dayFocus.
		^ dayFocus printString, '   ', dayFocus weekday,
			'   ', dayEvents size printString, ' changes, ',
			(self valueForNodes: dayEvents) printString, ' ', self measureLabel].
	span := self timeSpan ifNil: [^ 'no timestamped events'].
	^ String streamContents: [:s |
		s nextPutAll: (TimeStamp fromSeconds: span first) asDate printString;
			nextPutAll: '  ->  ';
			nextPutAll: (TimeStamp fromSeconds: span second) asDate printString.
		s nextPutAll: '   '; print: self eventsByDay size; nextPutAll: ' active days, ';
			print: self events size; nextPutAll: ' changes'.
		s nextPutAll: '   colour: '; nextPutAll: self measureLabel.
		dayFocus ifNotNil: [:d |
			s nextPutAll: '   [', d printString, ' selected -- click again to drill in]']]
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
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:53'
}
SWACalendarMorph >> cellExtentForWeeks: weekCount [
	"Square cells sized to fit both axes: 7 rows must fit the height, weekCount
	columns the width. Clamped to a readable 6..26px -- below 6 the grid is mush,
	above 26 a short history turns into absurd slabs."
	| byWidth byHeight side |
	byWidth := ((self width - self gridOrigin x - 8) / (weekCount max: 1)) truncated.
	byHeight := ((self height - self gridOrigin y - 24) / 7) truncated.
	"Clamped to 6..40px: below 6 the grid is mush; above 40 a three-week history
	turns into absurd slabs. The grid is CENTRED (see #gridOffset) rather than
	stretched, so a short span stays calendar-shaped instead of filling the pane."
	side := ((byWidth min: byHeight) max: 6) min: 40.
	^ side @ side
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
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:51'
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
	aCanvas drawString: 'more   max ', aMax printString, '  ', self measureLabel
		at: (x + 4 @ y) + anOrigin font: font color: (Color gray: 0.5)
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:57'
}
SWACalendarMorph >> drillIntoDay: aDate [
	"Switch to the hour view for one day. Refused when the day is empty -- there
	would be nothing to show and no obvious way back."
	(self eventsOnDay: aDate) isEmpty ifTrue: [^ self].
	dayFocus := aDate.
	level := #hours.
	self flushLayout.
	self refreshChrome
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:51'
}
SWACalendarMorph >> ensureLayout [
	cells ifNotNil: [^ self].
	level == #hours
		ifTrue: [self layoutHours]
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:50'
}
SWACalendarMorph >> flushLayout [
	cells := nil.
	eventsByDay := nil.
	maxDayValue := nil.
	super flushLayout
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:53'
}
SWACalendarMorph >> gridOffsetForWeeks: weekCount extent: cellExtent [
	"Extra offset that CENTRES the grid in the pane. Cells are capped in size, so a
	short history would otherwise sit in the top-left corner with most of the window
	empty. Never negative, so a long history still starts at the left margin and
	simply overflows to the right."
	| org gridW gridH |
	org := self gridOrigin.
	gridW := weekCount * cellExtent x.
	gridH := 7 * cellExtent y.
	^ (((self width - org x - 8 - gridW) // 2) max: 0)
		@ (((self height - org y - 28 - gridH) // 2) max: 0)
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
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:52'
}
SWACalendarMorph >> history [
	"Non-empty only while drilled into a day, so the panel's Back button lights up
	exactly when there is something to go back to."
	^ level == #hours
		ifTrue: [OrderedCollection with: #days]
		ifFalse: [OrderedCollection new]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:50'
}
SWACalendarMorph >> initialize [
	super initialize.
	level := #days
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:58'
}
SWACalendarMorph >> layoutDays [
	"The GitHub grid: one column per week, one row per weekday.

	The first column is padded so that every row is a fixed weekday -- that is the
	whole point of the layout, and it only works if week 0 starts on the Monday on
	or before the first event, not on the first event itself."
	| span first last startDate weeks ext org d |
	cells := OrderedCollection new.
	span := self timeSpan ifNil: [^ self].
	first := (TimeStamp fromSeconds: span first) asDate.
	last := (TimeStamp fromSeconds: span second) asDate.
	startDate := first subtractDays: (self weekdayIndexOf: first) - 1.
	weeks := ((last julianDayNumber - startDate julianDayNumber) // 7) + 1.
	ext := self cellExtentForWeeks: weeks.
	org := self gridOrigin + (self gridOffsetForWeeks: weeks extent: ext).
	"Remember the grid geometry: the labels must be placed from the GRID, not from
	whichever cells happen to exist -- a span with no Wednesday in it would
	otherwise silently lose that row's label."
	gridBox := {org. ext}.
	d := startDate.
	0 to: weeks - 1 do: [:wk |
		1 to: 7 do: [:row |
			| rect |
			(d julianDayNumber between: first julianDayNumber and: last julianDayNumber)
				ifTrue: [
					rect := (org x + (wk * ext x)) @ (org y + ((row - 1) * ext y))
						extent: (ext x - 1) @ (ext y - 1).
					cells add: {d. rect. self valueForDay: d}].
			d := d addDays: 1]]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:57'
}
SWACalendarMorph >> layoutHours [
	"One day in detail: 24 hour columns, each stacking that hour's individual
	changes as their own cells. Unlike the day grid these cells ARE nodes, so
	selection, marks and the Show pane operate on real changes here."
	| org colW plotH byHour dayEvents |
	cells := OrderedCollection new.
	dayFocus ifNil: [^ self].
	org := self gridOrigin.
	colW := ((self width - org x - 8) / 24) truncated max: 4.
	plotH := (self height - org y - 24) max: 20.
	dayEvents := self eventsOnDay: dayFocus.
	byHour := Array new: 24.
	1 to: 24 do: [:i | byHour at: i put: OrderedCollection new].
	dayEvents do: [:n |
		| h |
		h := n eventTimeStamp asTime hour.
		(byHour at: h + 1) add: n].
	1 to: 24 do: [:i |
		| list y cellH |
		list := byHour at: i.
		list isEmpty ifFalse: [
			"Every change in the hour gets equal height: at this zoom the question is
			WHICH changes happened, and sizing by diff lines would hide the small ones."
			cellH := ((plotH / list size) truncated max: 2) min: 18.
			y := org y.
			list do: [:n |
				cells add: {n. (org x + ((i - 1) * colW)) @ y
					extent: (colW - 1) @ (cellH - 1). self valueForNode: n}.
				y := y + cellH]]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:54'
}
SWACalendarMorph >> leftCellX [
	"x of the leftmost column of cells, wherever centring put the grid."
	cells isEmpty ifTrue: [^ self gridOrigin x].
	^ cells inject: (cells first second left) into: [:m :c | m min: c second left]
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:57'
}
SWACalendarMorph >> mouseDown: evt [
	"Day level: click selects the day, clicking the SELECTED day again drills into
	it -- the treemap's click-again-to-zoom idiom.
	Hour level: click selects the individual change; shift+click marks it.
	Right-click: menu (which is also how you come back out)."
	| local cell |
	self takeKeyboardFocusFrom: evt.
	local := evt position - self position.
	evt yellowButtonPressed ifTrue: [^ self showMenuAt: evt].
	cell := self cellAt: local.
	cell ifNil: [^ self].
	level == #hours ifTrue: [
		evt shiftPressed
			ifTrue: [self toggleMark: cell first. ^ self flushCache].
		^ self selectNode: cell first].
	"Day level."
	(dayFocus notNil and: [dayFocus julianDayNumber = cell first julianDayNumber])
		ifTrue: [^ self drillIntoDay: cell first].
	dayFocus := cell first.
	selectedNode := nil.
	self flushCache.
	self refreshChrome
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:58'
}
SWACalendarMorph >> renderDaysOn: aCanvas at: anOrigin [
	"Day cells on the intensity ramp, weekday labels down the left, month labels
	along the top, and a legend."
	| font max lastMonth lastMonthX |
	font := Preferences standardSystemFont.
	max := self maxDayValue.
	cells do: [:c |
		aCanvas
			fillRectangle: (c second translateBy: anOrigin)
			color: (self intensityColorFor: c third max: max)].
	"Labels are placed relative to the ACTUAL cells, not to #gridOrigin, because the
	grid is centred and so its real position depends on the span and the pane size."
	gridBox ifNotNil: [
		#('Mon' 'Wed' 'Fri' 'Sun') doWithIndex: [:name :i |
			| row y |
			row := #(1 3 5 7) at: i.
			y := gridBox first y + ((row - 1) * gridBox second y).
			aCanvas
				drawString: name
				at: ((gridBox first x - 34) @ y) + anOrigin
				font: font
				color: (Color gray: 0.5)]].
	"Month labels, suppressed when they would collide: a span of a few weeks can
	cross a month boundary inside a single column, and two labels at the same x are
	unreadable mush."
	lastMonth := nil.
	lastMonthX := -999.
	cells do: [:c |
		| m |
		m := c first monthIndex.
		(m ~= lastMonth and: [c second left - lastMonthX >= 26]) ifTrue: [
			lastMonth := m.
			lastMonthX := c second left.
			aCanvas
				drawString: (c first monthName copyFrom: 1 to: (3 min: c first monthName size))
				at: (c second left @ (self topCellY - 14)) + anOrigin
				font: font
				color: (Color gray: 0.55)]].
	self drawLegendOn: aCanvas at: anOrigin max: max.
	self drawDaySelectionOn: aCanvas at: anOrigin
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:51'
}
SWACalendarMorph >> renderHoursOn: aCanvas at: anOrigin [
	"One day: hour columns with the individual changes as cells, coloured by the
	ordinary node colour (so a loaded dataset tints them), plus hour ticks."
	| font org colW |
	font := Preferences standardSystemFont.
	org := self gridOrigin.
	colW := ((self width - org x - 8) / 24) truncated max: 4.
	0 to: 23 do: [:h |
		h \\ 3 = 0 ifTrue: [
			aCanvas
				drawString: h printString
				at: ((org x + (h * colW)) @ 4) + anOrigin
				font: font
				color: (Color gray: 0.5)]].
	cells do: [:c |
		aCanvas
			fillRectangle: (c second translateBy: anOrigin)
			color: (self colorForNode: c first)].
	selectedNode ifNotNil: [
		cells do: [:c |
			c first == selectedNode ifTrue: [
				aCanvas
					frameRectangle: ((c second expandBy: 1) translateBy: anOrigin)
					width: 1 color: Color yellow]]].
	aCanvas
		drawString: dayFocus printString, '   (right-click to go back to the calendar)'
		at: (org x @ (self height - 16)) + anOrigin
		font: font
		color: (Color gray: 0.55)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:51'
}
SWACalendarMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	aCanvas fillRectangle: (anOrigin extent: self extent) color: (Color gray: 0.12).
	cells ifNil: [^ self].
	level == #hours
		ifTrue: [self renderHoursOn: aCanvas at: anOrigin]
		ifFalse: [self renderDaysOn: aCanvas at: anOrigin]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:57'
}
SWACalendarMorph >> selectionPathString [
	"At hour level the selection is a node, so defer to the shared version. At day
	level it is a DAY, which has no node -- report the day's totals and its busiest
	packages instead, which is the useful answer at that zoom."
	| dayEvents counts top |
	level == #hours ifTrue: [^ super selectionPathString].
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
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:52'
}
SWACalendarMorph >> showMenuAt: evt [
	| menu |
	menu := MenuMorph new defaultTarget: self.
	level == #hours ifTrue: [
		menu add: 'back to calendar' selector: #zoomOut argument: nil.
		menu addLine].
	self measureOptions do: [:pair |
		menu
			add: (self measure == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #measure: argument: pair first].
	level == #hours ifTrue: [
		menu addLine.
		self colorModeOptions do: [:pair |
			menu
				add: (self colorMode == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
				selector: #colorMode: argument: pair first]].
	menu popUpEvent: evt in: self world
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:53'
}
SWACalendarMorph >> topCellY [
	"y of the topmost row of cells, used to hang the month labels above the grid
	wherever centring put it."
	cells isEmpty ifTrue: [^ self gridOrigin y].
	^ cells inject: (cells first second top) into: [:m :c | m min: c second top]
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
