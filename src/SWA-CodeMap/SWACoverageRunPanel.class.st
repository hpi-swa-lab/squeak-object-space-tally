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
		'stopRequested'
	],
	#category : #'SWA-CodeMap',
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:06'
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
		contents: 'Starting coverage run...';
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
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:07'
}
SWACoverageRunPanel >> openInWindowTitled: aTitle [
	"Open me in a small SystemWindow (no-op return self if headless)."
	| win |
	Smalltalk at: #World ifAbsent: [^ self].
	World ifNil: [^ self].
	win := (SystemWindow labelled: aTitle) model: nil.
	win addMorph: self frame: (0@0 corner: 1@1).
	win openInWorld.
	win extent: 460 @ 120.
	^ self
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:06'
}
SWACoverageRunPanel >> requestStop [
	stopRequested := true.
	self status: 'Stopping after current test...'
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:26'
}
SWACoverageRunPanel >> status: aString [
	"Update the status line. When the run is backgrounded (the normal case) the UI
	process repaints on its own, so we just mark the morph dirty. (#changed is
	cross-process safe enough for a label update.)"
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
