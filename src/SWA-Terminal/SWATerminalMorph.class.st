Class {
	#name : #SWATerminalMorph,
	#superclass : #Morph,
	#instVars : [
		'terminal',
		'font',
		'cellWidth',
		'cellHeight',
		'defaultFg',
		'defaultBg',
		'pty',
		'pumpProcess',
		'blinkState'
	],
	#classVars : [
		'DebugEvents'
	],
	#category : #'SWA-Terminal'
}

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:06'
}
SWATerminalMorph class >> debugEvents [
	"When on, SWATerminalMorph prints keyboard/mouse event routing to the
	 Transcript. Toggleable from the Preferences panel (category SWA-Terminal)."
	<preference: 'Debug terminal input events to Transcript' category: 'SWA-Terminal' description: 'Print keyboard and mouse event routing for SWATerminalMorph to the Transcript (for diagnosing input handling)' type: #Boolean>
	^ DebugEvents ifNil: [false]
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:06'
}
SWATerminalMorph class >> debugEvents: aBoolean [
	DebugEvents := aBoolean
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph class >> open [
	"Open a terminal in a SystemWindow and start a bash shell."
	| term window |
	term := self new.
	window := term openInWindowLabeled: 'Terminal' inWorld: self currentWorld.
	term startShell.
	^ window
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph >> addModelItemsToWindowMenu: aMenu [
	"Extend the SystemWindow title-bar menu with terminal options."
	aMenu addLine.
	aMenu add: 'restart shell' translated target: self selector: #restartShell.
	aMenu add: 'stop shell' translated target: self selector: #stopShell.
	aMenu addLine.
	aMenu addUpdating: #debugEventsMenuLabel target: self selector: #toggleDebugEvents argumentList: #().
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph >> debugEventsMenuLabel [
	"Checkmark toggle label: '<on>'/'<off>' prefix renders a check in the menu."
	^ (self class debugEvents ifTrue: [ '<on>' ] ifFalse: [ '<off>' ]),
		'log events to Transcript' translated
]

{
	#category : #'initialize-release',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:53'
}
SWATerminalMorph >> delete [
	"Clean up the shell and libvterm when the morph is removed."
	self stopShell.
	terminal ifNotNil: [ terminal free. terminal := nil ].
	super delete.
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> drawCell: cell row: row col: col origin: origin on: aCanvas [
	"Draw one cell: background fill (if non-default) then the glyph."
	| x y fg bg ch cellBounds |
	cell ifNil: [ ^ self ].
	x := origin x + (col * cellWidth).
	y := origin y + (row * cellHeight).
	fg := cell fgColor ifNil: [ defaultFg ].
	bg := cell bgColor ifNil: [ defaultBg ].
	cell reverse ifTrue: [ | t | t := fg. fg := bg. bg := t ].
	cellBounds := (x @ y) extent: (cellWidth @ cellHeight).
	bg = defaultBg ifFalse: [ aCanvas fillRectangle: cellBounds color: bg ].
	ch := cell character.
	ch = $  ifTrue: [ ^ self ].
	aCanvas
		drawString: (String with: ch)
		at: (x @ y)
		font: font
		color: fg.
	cell bold ifTrue: [
		aCanvas drawString: (String with: ch) at: (x + 1 @ y) font: font color: fg ].
	cell underline > 0 ifTrue: [
		aCanvas line: (x @ (y + cellHeight - 2)) to: (x + cellWidth @ (y + cellHeight - 2)) width: 1 color: fg ].
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> drawCursorOn: aCanvas origin: origin [
	"Draw a block cursor at the terminal cursor position."
	| pos x y cursorBounds cell |
	pos := terminal cursorPos.
	x := origin x + (pos x * cellWidth).
	y := origin y + (pos y * cellHeight).
	cursorBounds := (x @ y) extent: (cellWidth @ cellHeight).
	self hasFocus
		ifTrue: [
			"Solid block, reverse the glyph under it."
			aCanvas fillRectangle: cursorBounds color: defaultFg.
			cell := terminal cellAt: pos y at: pos x.
			(cell notNil and: [ cell character ~= $  ]) ifTrue: [
				aCanvas drawString: (String with: cell character)
					at: (x @ y) font: font color: defaultBg ] ]
		ifFalse: [
			aCanvas frameRectangle: cursorBounds width: 1 color: defaultFg ].
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> drawOn: aCanvas [
	"Draw the full terminal grid: background rectangle, then each cell's
	 background and glyph, then the cursor."
	| origin |
	origin := self topLeft.
	aCanvas fillRectangle: self bounds color: defaultBg.
	0 to: terminal rows - 1 do: [ :row |
		0 to: terminal cols - 1 do: [ :col |
			self drawCell: (terminal cellAt: row at: col)
				row: row col: col
				origin: origin on: aCanvas ] ].
	self drawCursorOn: aCanvas origin: origin.
]

{
	#category : #emulation,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> feed: bytesOrString [
	"Feed emulator output and request a redraw."
	terminal feed: bytesOrString.
	self changed.
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:54'
}
SWATerminalMorph >> forwardInput [
	"Drain libvterm's encoded keyboard output and write it to the PTY."
	| reply |
	reply := terminal drainOutput.
	reply isEmpty ifFalse: [ pty write: reply ].
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:54'
}
SWATerminalMorph >> handlesKeyboard: evt [
	^ true
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:54'
}
SWATerminalMorph >> handlesMouseDown: evt [
	^ true
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> hasFocus [
	^ self hasKeyboardFocus
]

{
	#category : #'initialize-release',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> initialize [
	super initialize.
	font := TextStyle defaultFixedFont.
	cellWidth := font widthOf: $m.
	cellHeight := font height.
	defaultFg := Color white.
	defaultBg := Color black.
	blinkState := true.
	terminal := SWATerminal rows: 24 cols: 80.
	self extent: self preferredExtent.
	self color: defaultBg.
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:17'
}
SWATerminalMorph >> keyStroke: evt [
	"Translate a Squeak keystroke into libvterm keyboard input, then forward the
	 encoded bytes to the PTY. VTermModifier: shift=1, alt=2, ctrl=4."
	| char code mod special |
	pty ifNil: [ ^ self ].
	char := evt keyCharacter.
	code := char asInteger.
	mod := 0.
	evt shiftPressed ifTrue: [ mod := mod bitOr: 1 ].
	"VTermModifier: shift=1, alt=2, ctrl=4.
	 On X11/WSL the VM reports Ctrl in BOTH the ctrl and command bits (Ctrl doubles
	 as the command key). So only treat command as Alt/Meta when Ctrl is NOT down,
	 otherwise Ctrl-X would wrongly become Ctrl-Alt-X."
	(evt commandKeyPressed and: [ evt controlKeyPressed not ])
		ifTrue: [ mod := mod bitOr: 2 ].
	evt controlKeyPressed ifTrue: [ mod := mod bitOr: 4 ].
	self logEvent: [ 'keyStroke: ', evt keyString, ' code=', code printString, ' mod=', mod printString ].
	special := self specialKeyFor: code.
	special notNil
		ifTrue: [ terminal keyCode: special mod: mod ]
		ifFalse: [
			"Ctrl combos: Squeak may deliver the raw control code (1-26); libvterm
			 wants the base letter + ctrl modifier. Recover it when ctrl is down."
			(evt controlKeyPressed and: [ code between: 1 and: 26 ])
				ifTrue: [ terminal keyChar: (Character value: code + 96) mod: mod ]
				ifFalse: [ terminal keyChar: char mod: mod ] ].
	self forwardInput.
	evt wasHandled: true.
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:06'
}
SWATerminalMorph >> keyboardFocusChange: aBoolean [
	"Redraw so the cursor style (solid vs outline) updates."
	self logEvent: [ 'keyboardFocusChange: ', aBoolean printString ].
	self changed.
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:06'
}
SWATerminalMorph >> logEvent: aStringBlock [
	"Print an event-routing diagnostic to the Transcript, but only when the
	 'Debug terminal input events' preference is on. Takes a block so the
	 (possibly costly) string is not built when logging is off."
	self class debugEvents ifTrue: [ Transcript showln: 'SWATerm ', aStringBlock value ]
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:06'
}
SWATerminalMorph >> mouseDown: evt [
	"Grab keyboard focus so typing goes to the shell."
	self logEvent: [ 'mouseDown: at ', evt position printString,
		' yellow=', evt yellowButtonChanged printString ].
	evt hand newKeyboardFocus: self.
	self changed.
]

{
	#category : #'initialize-release',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph >> openInWindowLabeled: aString inWorld: aWorld [
	"Open in a SystemWindow and register myself as its model so the title-bar
	 menu can be extended (see addModelItemsToWindowMenu:)."
	| window |
	window := super openInWindowLabeled: aString inWorld: aWorld.
	window model: self.
	"Size the window so the grid fits exactly, accounting for the title bar/borders."
	window extent: self preferredExtent + (window extent - window layoutBounds extent).
	^ window
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> preferredExtent [
	"Size that exactly fits the terminal grid."
	^ (terminal cols * cellWidth) @ (terminal rows * cellHeight)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:55'
}
SWATerminalMorph >> pty [
	^ pty
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:07'
}
SWATerminalMorph >> pumpOnce [
	"One iteration of the pump: drain PTY -> emulator, and emulator replies -> PTY."
	| input reply |
	pty ifNil: [ ^ self ].
	input := pty readAvailable.
	input isNil ifTrue: [ ^ self shellEnded ].	"EOF: child exited"
	input isEmpty ifFalse: [
		self logEvent: [ 'pty->emu ', input size printString, ' bytes: ',
			(input asString copyReplaceAll: (String with: (Character value: 27)) with: '<ESC>') ].
		terminal feed: input.
		self changed ].
	reply := terminal drainOutput.
	reply isEmpty ifFalse: [
		self logEvent: [ 'emu->pty ', reply size printString, ' bytes' ].
		pty write: reply ].
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph >> restartShell [
	"Stop any running shell and start a fresh bash."
	self startShell
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:53'
}
SWATerminalMorph >> shellEnded [
	"The child process closed the PTY. Tear down the pump."
	pty ifNotNil: [ pty close. pty := nil ].
	pumpProcess := nil.
	self changed.
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:54'
}
SWATerminalMorph >> specialKeyFor: code [
	"Map a Squeak key code to a VTermKey enum value, or nil if it is an ordinary char.
	 Squeak: 28=left 29=right 30=up 31=down 8=bs 9=tab 13=cr 27=esc."
	code = 30 ifTrue: [ ^ terminal keyUp ].
	code = 31 ifTrue: [ ^ terminal keyDown ].
	code = 28 ifTrue: [ ^ terminal keyLeft ].
	code = 29 ifTrue: [ ^ terminal keyRight ].
	code = 13 ifTrue: [ ^ terminal keyEnter ].
	code = 10 ifTrue: [ ^ terminal keyEnter ].
	code = 8 ifTrue: [ ^ terminal keyBackspace ].
	code = 127 ifTrue: [ ^ terminal keyBackspace ].
	code = 9 ifTrue: [ ^ terminal keyTab ].
	code = 27 ifTrue: [ ^ terminal keyEscape ].
	^ nil
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:53'
}
SWATerminalMorph >> startCommand: cmd args: argArray [
	"Spawn a command over a PTY sized to the terminal grid and start pumping."
	self stopShell.
	pty := SWATerminalPty command: cmd args: argArray.
	pty spawnRows: terminal rows cols: terminal cols.
	self startPump.
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:53'
}
SWATerminalMorph >> startPump [
	"Background process: read PTY output -> feed emulator -> forward emulator
	 replies -> PTY, redrawing when something changed. Runs until PTY closes."
	pumpProcess ifNotNil: [ pumpProcess terminate. pumpProcess := nil ].
	pumpProcess := [
		[ pty notNil and: [ pty masterFd >= 0 ] ] whileTrue: [
			self pumpOnce.
			(Delay forMilliseconds: 16) wait ]
	] newProcess.
	pumpProcess priority: Processor userBackgroundPriority.
	pumpProcess resume.
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:53'
}
SWATerminalMorph >> startShell [
	"Spawn /bin/bash over a PTY and start the pump loop."
	^ self startCommand: '/bin/bash' args: #('-i')
]

{
	#category : #shell,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:53'
}
SWATerminalMorph >> stopShell [
	"Stop the pump and close the PTY."
	pumpProcess ifNotNil: [ pumpProcess terminate. pumpProcess := nil ].
	pty ifNotNil: [ pty close. pty := nil ].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 12:49'
}
SWATerminalMorph >> terminal [
	^ terminal
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph >> toggleDebugEvents [
	self class debugEvents: self class debugEvents not
]

{
	#category : #'initialize-release',
	#'squeak_changestamp' : 'MCPServer 7/23/2026 13:11'
}
SWATerminalMorph >> windowIsClosing [
	"Sent by our hosting SystemWindow when it is closed: tear down the shell
	 and release libvterm."
	self stopShell.
	terminal ifNotNil: [ terminal free. terminal := nil ].
]
