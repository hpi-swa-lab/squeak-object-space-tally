"
A tiny self-contained progress + Stop panel for a long coverage-generation run
(SWACoverage class>>generateAllTestsToFile:). It is the ONLY UI the heavy
whole-image run shows -- deliberately separate from the Code Map nav bar.

Shows a one-line status (updated as tests run) and a big Stop button. Pressing
Stop sets #stopRequested, which the run loop polls between tests to abort early
and still write whatever was collected.

Headless-safe: if there is no World (command-line run), the generator simply does
not open one and uses #stopRequested := false throughout.

Instance Variables
	statusMorph    <StringMorph>   the live status line
	stopRequested  <Boolean>       set true by the Stop button
"
Class {
	#name : #SWACoverageRunPanel,
	#superclass : #Morph,
	#instVars : [
		'statusMorph',
		'stopRequested',
		'onStop',
		'onClose'
	],
	#category : #'SWA-Coverage',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:07'
}
SWACoverageRunPanel >> closeWindow [
	"Close my enclosing window, if any."
	(self ownerThatIsA: SystemWindow) ifNotNil: [:w | w delete]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:57'
}
SWACoverageRunPanel >> delete [
	"Run the #onClose: action (once) when I am removed, so closing the window by any
	means tears down a live tally, then proceed with normal morph deletion."
	| block |
	block := onClose.
	onClose := nil.
	block ifNotNil: [block value].
	super delete
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:31'
}
SWACoverageRunPanel >> finishAndClose: aFinalStatus [
	"Show a final status, pause briefly so it is readable, then close my window.
	Called from the background run process; the delay runs there, and the actual
	delete is deferred to the UI process so it is morphic-safe."
	self status: aFinalStatus.
	self world ifNil: [^ self closeWindow].
	(Delay forMilliseconds: 1500) wait.
	WorldState addDeferredUIMessage: [self closeWindow]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 13:11'
}
SWACoverageRunPanel >> initialize [
	super initialize.
	stopRequested := false.
	self
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #leftCenter;
		cellInset: 8;
		layoutInset: 10;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap.
	statusMorph := StringMorph new
		contents: 'Starting...';
		color: Color white;
		font: (TextStyle default fontOfPointSize: 12);
		yourself.
	self addMorphBack: statusMorph.
	self addMorphBack: (SimpleButtonMorph new
		label: 'STOP';
		color: (Color r: 0.7 g: 0.15 b: 0.15);
		target: self;
		actionSelector: #requestStop;
		yourself)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:57'
}
SWACoverageRunPanel >> onClose: aBlock [
	"Set a zero-arg block run once when my window is deleted by ANY means (the close
	box, not just STOP). The live call tally uses this to abandon (uninstall) the
	tally if the user closes the window without pressing STOP, so instrumentation
	never lingers. Guarded against double-firing with #closeWindow's own delete."
	onClose := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:54'
}
SWACoverageRunPanel >> onStop: aBlock [
	"Set a zero-arg action block run when the STOP button is pressed. Used by the live
	call tally, where 'stop' is not a poll-and-abort (as in the coverage run) but an
	immediate action: collect the counts and uninstall the wrappers. The coverage run
	leaves this nil and polls #stopRequested instead."
	onStop := aBlock
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 13:18'
}
SWACoverageRunPanel >> openInWindowTitled: aTitle [
	"Open me in a SystemWindow, centered (no-op return self if headless)."
	| win |
	Smalltalk at: #World ifAbsent: [^ self].
	World ifNil: [^ self].
	win := (SystemWindow labelled: aTitle) model: nil.
	win addMorph: self frame: (0@0 corner: 1@1).
	win openInWorld.
	win extent: 1000 @ 200.
	win center: World center.
	^ self
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:54'
}
SWACoverageRunPanel >> requestStop [
	"STOP pressed. Flag it (for the polling coverage run) and, if an #onStop: action
	block was set (the live call tally), run it now -- deferred to the UI process so
	it is morphic-safe."
	stopRequested := true.
	self status: 'Stopping...'.
	onStop ifNotNil: [
		WorldState addDeferredUIMessage: [onStop value]]
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 13:11'
}
SWACoverageRunPanel >> status: aString [
	"Update the status line."
	statusMorph contents: aString.
	statusMorph changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:06'
}
SWACoverageRunPanel >> stopRequested [
	^ stopRequested
]
