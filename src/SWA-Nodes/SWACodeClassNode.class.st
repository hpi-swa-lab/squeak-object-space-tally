"
A SWACodeNode whose subject is a Class. Children are SWACodeCategoryNodes (one per method category). Class-side (metaclass) categories are included and flagged as UML 'static'. Owns source access so method nodes can delegate to it. Knows its superclass for inheritance-graph edges.
"
Class {
	#name : #SWACodeClassNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'methodFilter',
		'ivarFilter',
		'hiddenIvarNames',
		'removedMembers',
		'memberKinds',
		'compositionData',
		'boxFill'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWACodeClassNode >> boxFill: aHexStringOrNil [
	"A fill the view chose for this box, overriding the colour mode's."
	boxFill := aHexStringOrNil
]

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:05'
}
SWACodeClassNode >> browse [
	(subject isKindOf: SWASnapshotBehavior) ifTrue: [^ subject browse].
	^ ToolSet browseClass: subject
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:05'
}
SWACodeClassNode >> buildChildren [
	"A SWACodeCommentNode for the class comment (when present), then one
	SWACodeCategoryNode per method category, instance side then class side.
	Class-side categories are flagged static (UML 'static')."
	| nodes comment |
	nodes := OrderedCollection new.
	comment := [subject organization classComment] on: Error do: [:e | nil].
	(comment notNil and: [comment asString withBlanksTrimmed notEmpty]) ifTrue: [
		nodes add: (SWACodeCommentNode on: subject parent: self)].
	subject organization categories do: [:cat |
		(subject organization listAtCategoryNamed: cat) isEmpty ifFalse: [
			nodes add: ((SWACodeCategoryNode on: cat parent: self)
				metaClass: subject;
				isStatic: false;
				yourself)]].
	subject classSide organization categories do: [:cat |
		(subject classSide organization listAtCategoryNamed: cat) isEmpty ifFalse: [
			nodes add: ((SWACodeCategoryNode on: cat parent: self)
				metaClass: subject classSide;
				isStatic: true;
				yourself)]].
	^ nodes
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> classNode [
	"I am the class node my method descendants delegate to."
	^ self
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:17'
}
SWACodeClassNode >> compositionAssociations [
	"ivarName -> { targetClassName. multiplicity }, see SWACompositionData."
	compositionData ifNotNil: [:data | ^ data associationsForClassNamed: self name].
	^ SWACompositionData associationsOf: self theClass
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:17'
}
SWACodeClassNode >> compositionData: aCompositionDataOrNil [
	compositionData := aCompositionDataOrNil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:33'
}
SWACodeClassNode >> crossRefKey [
	"Classes are identified across views by their (unique) class name."
	^ subject name asString
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:09'
}
SWACodeClassNode >> hiddenIvarNames: aCollection [
	"Ivars to leave out of the state compartment because they are drawn as association
	edges instead. Separate from #ivarFilter:, which belongs to the mark-set
	granularity and must keep working alongside this."

	hiddenIvarNames := aCollection asSet
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:25'
}
SWACodeClassNode >> instVarNames [
	"The receiver class's own instance-variable names (UML state / attributes),
	in definition order. Excludes inherited ivars."
	^ subject instVarNames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWACodeClassNode >> ivarFilter: aBlockOrNil [
	"Set an optional one-arg predicate (SWACodeInstVarNode -> Boolean) that restricts which
	instance variables this class renders in the diagram's state compartment. nil = show
	all. Used by the class diagram's '+Selected' granularity to show only marked ivars.
	Returns self."
	ivarFilter := aBlockOrNil.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> kind [
	^ #class
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:05'
}
SWACodeClassNode >> kindColorFor: aCrossRefKey [
	"Green added, orange modified, red removed, nil for anything we were told nothing about."

	| kind |
	memberKinds isNil ifTrue: [^ nil].
	kind := memberKinds at: aCrossRefKey ifAbsent: [nil].
	kind == #added ifTrue: [^ '#d8f0d8'].
	kind == #modified ifTrue: [^ '#ffe8cc'].
	kind == #removed ifTrue: [^ '#f8d7da'].
	^ nil
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:33'
}
SWACodeClassNode >> memberKinds: aDictionary [
	"crossRefKey -> #added or #modified, used to tint the member's row. Set alongside
	#removedMembers:, which covers the third case."

	memberKinds := aDictionary
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:05'
}
SWACodeClassNode >> methodCategoryFor: aMethodNode [
	"The browser protocol aMethodNode lives in. Class-side methods are organised by the
	METACLASS, which keeps categories of its own."
	| behavior category |
	behavior := aMethodNode isStatic
		ifTrue: [self theClass classSide]
		ifFalse: [self theClass].
	category := [behavior organization categoryOfElement: aMethodNode name asSymbol]
		on: Error do: [:e | nil].
	^ (category ifNil: [ClassOrganizer default]) asString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:37'
}
SWACodeClassNode >> methodFilter: aBlockOrNil [
	"Set an optional one-arg predicate (SWACodeMethodNode -> Boolean) that restricts which
	methods this class renders in the diagram's methods compartment. nil = show all. Used
	by the class diagram's 'classes + marked methods' granularity to show only marked
	methods. Returns self."
	methodFilter := aBlockOrNil.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:08'
}
SWACodeClassNode >> methodNodes [
	"All SWACodeMethodNodes of this class, flattened across categories,
	instance-side first then class-side (static)."
	| out |
	out := OrderedCollection new.
	self children do: [:cat | out addAll: cat children].
	^ out
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> name [
	^ subject name asString
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:29'
}
SWACodeClassNode >> recordCategoryRowOn: ws text: aString [
	"A protocol heading inside the methods compartment: italic grey, and no port --
	it labels the rows under it rather than being a member itself, so its field maps
	back to the class.

	Same point size as the method rows on purpose: GraphvizJsonParser derives the row
	boundaries from a UNIFORM baseline pitch, so a smaller heading would skew every
	boundary beneath it."
	ws nextPutAll: '<tr><td align="text"><i><font color="#888888">'.
	ws nextPutAll: (SWACodeNode htmlEscape: aString).
	ws nextPutAll: '</font></i><br align="left"/></td></tr>'
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:38'
}
SWACodeClassNode >> recordDeadRowsOn: ws ivars: wantIvars [
	"Emit the struck-through rows for removed members, ivars or methods per wantIvars.
	No port is written: the field-click map is built from the nodes that actually exist,
	so a port here would shift every later row's index out of step with it.
	Answers whether anything was emitted."

	| any |
	removedMembers isNil ifTrue: [^ false].
	any := false.
	removedMembers do: [:each |
		(each third) = wantIvars ifTrue: [
			any := true.
			ws nextPutAll: '<tr><td align="text" bgcolor="#f8d7da"><font color="#9a4a52">'.
			(each second) ifTrue: [ws nextPutAll: '<u>'].
			ws nextPutAll: '<s>'; nextPutAll: (SWACodeNode htmlEscape: each first); nextPutAll: '</s>'.
			(each second) ifTrue: [ws nextPutAll: '</u>'].
			ws nextPutAll: '</font><br align="left"/></td></tr>']].
	^ any
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:52'
}
SWACodeClassNode >> recordEmptyRowOn: ws [
	"Emit a single borderless spacer row so an EMPTY but enabled compartment still renders
	as a (blank) UML section below its separator. Uses a non-breaking space so Graphviz
	lays out (and gives us a text baseline for) exactly one row -- keeping the field-rect /
	#recordFieldNodesShowState:showMethods: index alignment. No port -- it is not clickable
	as a member (its field maps back to the class)."
	ws nextPutAll: '<tr><td align="text">&nbsp;<br align="left"/></td></tr>'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:14'
}
SWACodeClassNode >> recordFieldNodes [
	"Full field-node list (name + ivars + methods). See #recordFieldNodesShowMethods:."
	^ self recordFieldNodesShowMethods: true
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:23'
}
SWACodeClassNode >> recordFieldNodesShowMethods: showMethods [
	"State-always-on variant. See #recordFieldNodesShowState:showMethods:."
	^ self recordFieldNodesShowState: true showMethods: showMethods
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:30'
}
SWACodeClassNode >> recordFieldNodesShowState: showState showMethods: showMethods [
	"The SWACodeNode for each record field, by field index, matching the ROW order emitted
	by #recordLabelColorMode:maxLoc:showState:showMethods: EXACTLY -- including the blank
	spacer row an enabled-but-empty compartment emits, and the protocol HEADING rows the
	methods compartment emits (both mapped to the class itself, since clicking a label or
	blank space should select the whole class). Index 0 = the class name row; then the
	state rows (one SWACodeInstVarNode per visible ivar, or ONE placeholder = self when
	empty); then, per protocol, one placeholder for the heading plus one node per method.

	Every emitted row is one text baseline and so one field rect: a row that is not
	counted here shifts every row below it, and clicks land on the wrong member."
	| out ivars deadIvars groups deadMethods |
	out := OrderedCollection new.
	out add: self.                        "0: name row"
	showState ifTrue: [
		ivars := self recordIvarNodes.
		deadIvars := self removedMemberCount: true.
		out addAll: ivars.
		deadIvars timesRepeat: [out add: self].   "struck-through row -> the class"
		(ivars isEmpty and: [deadIvars = 0])
			ifTrue: [out add: self]].     "blank spacer row -> the class"
	showMethods ifTrue: [
		groups := self recordMethodGroups.
		deadMethods := self removedMemberCount: false.
		groups do: [:group |
			out add: self.                "protocol heading row -> the class"
			out addAll: group value].
		deadMethods timesRepeat: [out add: self].
		(groups isEmpty and: [deadMethods = 0])
			ifTrue: [out add: self]].
	^ out asArray
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:09'
}
SWACodeClassNode >> recordIvarNodes [
	"The instance variables as SWACodeInstVarNodes, in definition order -- the state-row
	order for the class box. This is the markable/clickable counterpart to the raw
	#instVarNames strings. When an #ivarFilter is set (the '+Selected' granularity), only
	ivars satisfying it are returned, so the DOT label, the click field map, and the state
	compartment all agree (they all funnel through here)."
	| nodes shown |
	shown := hiddenIvarNames isNil
		ifTrue: [self instVarNames]
		ifFalse: [self instVarNames reject: [:v | hiddenIvarNames includes: v]].
	nodes := shown collect: [:v |
		(SWACodeInstVarNode on: subject parent: self) ivarName: v; yourself].
	ivarFilter isNil ifTrue: [^ nodes asArray].
	^ (nodes select: [:n | ivarFilter value: n]) asArray
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:40'
}
SWACodeClassNode >> recordLabel [
	"The default UML class box (flat fill by kind). See #recordLabelColorMode:maxLoc:."
	^ self recordLabelColorMode: #kind maxLoc: 0
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:14'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc [
	"The full UML class box (name + state + methods). See
	#recordLabelColorMode:maxLoc:showMethods: for the coarser (classes-only) variant."
	^ self recordLabelColorMode: aColorMode maxLoc: aMaxLoc showMethods: true
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:22'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc showMethods: showMethods [
	"State-always-on variant. See #recordLabelColorMode:maxLoc:showState:showMethods:
	for the three-way granularity (which can also hide the state compartment)."
	^ self
		recordLabelColorMode: aColorMode maxLoc: aMaxLoc
		showState: true showMethods: showMethods
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:51'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc showState: showState showMethods: showMethods [
	"A Graphviz HTML-like label (UML class box) as a <table>: class name (bold) on
	top, then -- when showState is true -- a STATE compartment (one row per ivar),
	then -- when showMethods is true -- a METHODS compartment (one row per method).
	Compartments are separated by <hr/> rules; rows are borderless and left-aligned.
	Row order matches #recordFieldNodesShowState:showMethods:.

	Per UML, an ENABLED compartment always draws its separator line even when it has no
	(visible) rows -- so an empty state/methods section shows as an empty box, and the
	'+Selected' depth (which may filter a compartment down to nothing) keeps the familiar
	three-section shape. The compartment methods emit rows only; the separator is drawn
	here.

	The two flags give the granularities:
	  showState=false, showMethods=false -- classes only (name box)
	  showState=true,  showMethods=false -- classes + state
	  showState=true,  showMethods=true  -- classes + state + methods

	aColorMode selects the fill: #kind (flat by-kind table background) or #loc
	(neutral background + per-method LOC heat tint, scaled to aMaxLoc). Meant to be
	emitted between < and > in the DOT node statement (an HTML label)."
	| ws idx |
	ws := WriteStream on: String new.
	ws nextPutAll: '<table border="1" cellborder="0" cellspacing="0" cellpadding="3" bgcolor="'.
	ws nextPutAll: (self recordTableBgColorMode: aColorMode); nextPutAll: '">'.
	self recordNameRowOn: ws.
	idx := 0.
	showState ifTrue: [
		ws nextPutAll: '<hr/>'.
		idx := self recordStateCompartmentOn: ws startingAt: idx].
	showMethods ifTrue: [
		ws nextPutAll: '<hr/>'.
		idx := self recordMethodCompartmentOn: ws startingAt: idx colorMode: aColorMode maxLoc: aMaxLoc].
	ws nextPutAll: '</table>'.
	^ ws contents
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:30'
}
SWACodeClassNode >> recordMethodCompartmentOn: ws startingAt: startIndex colorMode: aColorMode maxLoc: aMaxLoc [
	"Emit the METHODS compartment into ws: each browser protocol as an italic grey
	heading row (#recordCategoryRowOn:text:) followed by its methods, class-side ones
	underlined, then any removed methods struck through. Ports continue from startIndex.
	In #loc mode each cell is tinted by its LOC on a green->red ramp scaled to aMaxLoc.
	Answer the next free port index. When there is nothing at all to show, a single blank
	spacer row keeps the enabled-but-empty section rendering below its separator (drawn
	by the caller). Walks #recordMethodGroups, as the field-node list does."

	| idx locMode groups hadRemovals |
	idx := startIndex.
	locMode := aColorMode = #loc.
	groups := self recordMethodGroups.
	groups do: [:group |
		self recordCategoryRowOn: ws text: group key.
		group value do: [:m | | cellBg |
			idx := idx + 1.
			cellBg := locMode
				ifTrue: [SWACodeNode locHeatColor: m loc max: aMaxLoc]
				ifFalse: [self kindColorFor: m crossRefKey].
			self
				recordRowOn: ws port: idx bgColor: cellBg text: m pattern
				underline: m isStatic]].
	hadRemovals := self recordDeadRowsOn: ws ivars: false.
	(groups isEmpty and: [hadRemovals not]) ifTrue: [self recordEmptyRowOn: ws].
	^ idx
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:29'
}
SWACodeClassNode >> recordMethodGroups [
	"The visible methods grouped into their browser protocols, as category -> nodes:
	categories alphabetical, instance methods before class-side ones within each.

	THE one definition of method row order. #recordMethodNodes flattens it, the
	compartment emits a heading row per group, and #recordFieldNodesShowState:showMethods:
	counts those headings -- all three read this, so they cannot drift apart."
	| groups |
	groups := Dictionary new.
	self recordVisibleMethodNodes do: [:m |
		(groups at: (self methodCategoryFor: m) ifAbsentPut: [OrderedCollection new])
			add: m].
	^ (groups keys asSortedCollection: [:a :b | a <= b]) asArray collect: [:category |
		| members |
		members := groups at: category.
		category -> ((members reject: [:m | m isStatic]) , (members select: [:m | m isStatic])) asArray]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:29'
}
SWACodeClassNode >> recordMethodNodes [
	"The method nodes in rendered order, flattened out of #recordMethodGroups -- which
	is where the ordering is decided. Record field index = this index + 1 + the number
	of heading rows above it; #recordFieldNodesShowState:showMethods: is what resolves
	that, and both walk the same groups."
	| out |
	out := OrderedCollection new.
	self recordMethodGroups do: [:group | out addAll: group value].
	^ out asArray
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:05'
}
SWACodeClassNode >> recordNameRowOn: ws [
	"Emit the class-name compartment (bold, left-aligned) into ws."
	ws nextPutAll: '<tr><td align="text"'.
	(self kindColorFor: self crossRefKey) ifNotNil: [:color |
		ws nextPutAll: ' bgcolor="'; nextPutAll: color; nextPutAll: '"'].
	ws nextPutAll: '><b>'.
	ws nextPutAll: (SWACodeNode htmlEscape: self name).
	ws nextPutAll: '</b><br align="left"/></td></tr>'
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 15:47'
}
SWACodeClassNode >> recordRowOn: ws port: portIndex bgColor: bgColorOrNil text: aString [
	"Emit one borderless, left-aligned table row into ws: a named port (for click
	geometry), an optional cell background (LOC tint), and the escaped text."
	self recordRowOn: ws port: portIndex bgColor: bgColorOrNil text: aString underline: false
]

{
	#category : #record,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 15:47'
}
SWACodeClassNode >> recordRowOn: ws port: portIndex bgColor: bgColorOrNil text: aString underline: aBoolean [
	"As #recordRowOn:port:bgColor:text:, with the UML underline for a static member.
	The <u> has to be added here because the text itself is HTML-escaped."

	ws nextPutAll: '<tr><td align="text" port="m', portIndex printString, '"'.
	bgColorOrNil ifNotNil: [:c |
		ws nextPutAll: ' bgcolor="'; nextPutAll: c; nextPutAll: '"'].
	ws nextPutAll: '>'.
	aBoolean ifTrue: [ws nextPutAll: '<u>'].
	ws nextPutAll: (SWACodeNode htmlEscape: aString).
	aBoolean ifTrue: [ws nextPutAll: '</u>'].
	ws nextPutAll: '<br align="left"/></td></tr>'
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:37'
}
SWACodeClassNode >> recordStateCompartmentOn: ws startingAt: startIndex [
	"Emit the STATE compartment rows (one per instance variable) into ws. Ports continue
	from startIndex. Answer the next free port index. When there are no (visible) ivars a
	single blank spacer row is emitted so the enabled-but-empty section still renders below
	its separator (drawn by the caller). Honors #ivarFilter (via #recordIvarNodes)."
	| idx ivarNodes hadRemovals |
	idx := startIndex.
	ivarNodes := self recordIvarNodes.
	ivarNodes do: [:n |
		idx := idx + 1.
		self recordRowOn: ws port: idx bgColor: (self kindColorFor: n crossRefKey) text: n ivarName].
	hadRemovals := self recordDeadRowsOn: ws ivars: true.
	(ivarNodes isEmpty and: [hadRemovals not]) ifTrue: [self recordEmptyRowOn: ws].
	^ idx
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWACodeClassNode >> recordTableBgColorMode: aColorMode [
	"The <table> background color for a UML class box: a neutral gray in #loc mode
	(so per-method LOC tints read clearly), else the flat by-kind fill."
	boxFill ifNotNil: [^ boxFill].
	^ aColorMode = #loc
		ifTrue: ['#f4f4f4']
		ifFalse: [self dotFillColor]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:29'
}
SWACodeClassNode >> recordVisibleMethodNodes [
	"The method nodes this diagram shows, before grouping: everything passing
	#methodFilter (e.g. the 'marked methods only' granularity)."
	^ methodFilter isNil
		ifTrue: [self methodNodes]
		ifFalse: [self methodNodes select: [:m | methodFilter value: m]]
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:36'
}
SWACodeClassNode >> removedMemberCount: wantIvars [
	"How many struck-through rows the given compartment emits. Clicking resolves a row
	INDEX, so every emitted row must be counted here whether or not it is clickable."

	removedMembers isNil ifTrue: [^ 0].
	^ (removedMembers select: [:each | each third = wantIvars]) size
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:22'
}
SWACodeClassNode >> removedMembers: aCollection [
	"{ displayText. isStatic. isIvar } triples for members this class no longer has, to
	be drawn struck through. They exist only in the history, so there is no node behind
	them -- which is why they are rendered without a port and cannot be clicked."

	removedMembers := aCollection
]

{
	#category : #inheritance,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> superclassName [
	"Name of the superclass, or nil for root classes (Object's superclass etc.)."
	^ subject superclass ifNotNil: [:sc | sc name asString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> theClass [
	"The live (instance-side) class this node represents."
	^ subject
]
