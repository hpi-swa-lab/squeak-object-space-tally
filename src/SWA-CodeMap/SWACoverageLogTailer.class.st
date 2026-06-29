"
A live in-image ""tail -f"" for a forked SWACoverage run.

A forked coverage child (see SWACoverage class>>generatePackages:toFile:forked:)
runs headless in a throwaway image and writes progress to a per-run log file. We
lose live feedback in the parent -- this window restores it: it polls the log
file on Morphic step, appends only the new bytes (cheap, like tail -f), auto-
scrolls, and detects when the run finishes (the child's 'quitting (no save)'
line, or the output JSON appearing). On finish it flips the status banner to
green and evaluates an optional onFinish block (e.g. open the Code Map on the
result).

	SWACoverageLogTailer openOn: 'morphic-coverage.log' output: 'morphic-coverage.json'.
"
Class {
	#name : #SWACoverageLogTailer,
	#superclass : #SystemWindow,
	#instVars : [
		'logPath',
		'outputPath',
		'bytePosition',
		'textMorph',
		'statusMorph',
		'finished',
		'finishNotified',
		'onFinish',
		'accumulated',
		'sawFinishLine',
		'sawErrorLine',
		'stderrPath',
		'idleSteps',
		'lastSize',
		'childProcess',
		'scriptPath',
		'stopButton',
		'outTextMorph',
		'outAccumulated',
		'outBytePosition'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:02'
}
SWACoverageLogTailer class >> openOn: aLogPath [
	"Open a tailer on a log file with no separate output file to watch."
	^ self openOn: aLogPath output: nil
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:02'
}
SWACoverageLogTailer class >> openOn: aLogPath output: anOutputPath [
	"Open a live tailer window on aLogPath, watching anOutputPath (may be nil) to
	detect completion. Returns the tailer."
	| tailer |
	tailer := self new
		logPath: aLogPath output: anOutputPath;
		yourself.
	tailer buildWindow.
	tailer openInWorld.
	^ tailer
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:57'
}
SWACoverageLogTailer class >> openOn: aLogPath output: anOutputPath stderr: aStderrPath [
	"Open a tailer watching aLogPath, the output JSON anOutputPath, and the child's
	captured stdout+stderr aStderrPath (where a VM crash dump / Transcript lands)."
	| tailer |
	tailer := self new
		logPath: aLogPath output: anOutputPath;
		stderrPath: aStderrPath;
		yourself.
	tailer buildWindow.
	tailer openInWorld.
	"openInWorld re-applies the theme's per-window-type tint; set the neutral color
	AFTER it so the window has no green."
	tailer color: Color veryVeryLightGray.
	^ tailer
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 13:30'
}
SWACoverageLogTailer >> appendStderrTail [
	"Append the tail of the child's captured stdout+stderr (the '.out' file) to the
	view. This is where a VM-level crash dump ('Smalltalk stack dump', pthread
	warnings, uncaught primitive failures) lands -- NOT in our per-line log. Bounded
	to the last 8KB so a huge dump can't bloat the pane."
	| content tail |
	stderrPath ifNil: [^ self].
	(FileDirectory default fileExists: stderrPath) ifFalse: [^ self].
	content := [(FileStream readOnlyFileNamed: stderrPath) contentsOfEntireFile]
		on: Error do: [:e | nil].
	(content isNil or: [content isEmpty]) ifTrue: [^ self].
	tail := content size > 8192 ifTrue: [content last: 8192] ifFalse: [content].
	accumulated := self logContents, String cr,
		'======= child stdout/stderr (.out) =======', String cr, tail.
	textMorph setText: (self styledText: accumulated).
	textMorph textMorph ifNotNil: [:tm | tm editor selectAt: accumulated size + 1].
	textMorph scrollSelectionIntoView
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:56'
}
SWACoverageLogTailer >> buildWindow [
	"Top row: a STOP button (kills the forked child) + a status banner. Below: TWO
	read-only panes side by side -- left = our structured per-line log (logPath),
	right = the child's stdout/Transcript capture (the '.out' file, fed by
	#redirectToStdOut: in the child).

	The window is forced to the neutral default SystemWindow color
	(veryVeryLightGray) instead of the per-window-type green tint the theme would
	otherwise apply -- 'no color'. Panes keep their own theme colors."
	self setLabel: 'Coverage log: ', (logPath ifNil: ['?']).
	stopButton := SimpleButtonMorph new
		target: self;
		label: 'STOP';
		actionSelector: #stopChild;
		yourself.
	statusMorph := TextMorph new
		contents: 'Watching ', logPath, ' ...';
		yourself.
	textMorph := PluggableTextMorph
		on: self text: #logContents accept: nil readSelection: nil menu: nil.
	textMorph askBeforeDiscardingEdits: false.
	outTextMorph := PluggableTextMorph
		on: self text: #outContents accept: nil readSelection: nil menu: nil.
	outTextMorph askBeforeDiscardingEdits: false.
	self
		addMorph: stopButton
			fullFrame: (LayoutFrame fractions: (0@0 corner: 0@0) offsets: (4@2 corner: 84@26));
		addMorph: statusMorph
			fullFrame: (LayoutFrame fractions: (0@0 corner: 1@0) offsets: (88@0 corner: 0@28));
		addMorph: textMorph
			fullFrame: (LayoutFrame fractions: (0@0 corner: 0.5@1) offsets: (0@28 corner: 0@0));
		addMorph: outTextMorph
			fullFrame: (LayoutFrame fractions: (0.5@0 corner: 1@1) offsets: (0@28 corner: 0@0)).
	self
		color: Color veryVeryLightGray;
		extent: 980@520
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:44'
}
SWACoverageLogTailer >> checkFinished [
	"Finish detection -- CLEAN only. Finished when the child logged its final
	'quitting (no save)' line (latched in sawFinishLine, printed on success AND error).
	We deliberately DO NOT infer failure from a stalled log: a big '*' run can go
	silent for a long time (installing 73k wrappers, a slow test) without being dead.
	If it really is wedged, the user presses STOP. The right pane already shows the
	child's stdout/.out (incl. any crash dump) live, so no separate append needed."
	finished ifTrue: [^ self].
	sawFinishLine == true ifFalse: [^ self].
	finished := true.
	self markFinished: sawErrorLine ~~ true error: sawErrorLine == true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:41'
}
SWACoverageLogTailer >> childProcess: anOSProcessOrNil scriptPath: aScriptPath [
	"The forked child's OSProcess handle (for STOP -> sigkill) and the script path
	(for a pkill fallback that reaches the squeak grandchild)."
	childProcess := anOSProcessOrNil.
	scriptPath := aScriptPath
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:57'
}
SWACoverageLogTailer >> delete [
	"Closing the window must STOP the forked child -- otherwise a wedged/thrashing
	child keeps running with no UI left to kill it. Kill it (idempotent: harmless if
	already finished or never started), then close normally."
	[self killChild] on: Error do: [:e | nil].
	super delete
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:57'
}
SWACoverageLogTailer >> killChild [
	"Kill the forked child process. Tries the captured OSProcess handle first
	(sigkill); then a pkill fallback matching the unique script path, because
	OSProcess command: runs the squeak child under a shell and the sigkill may only
	reach the shell -- pkill -f on the script path reaches the squeak grandchild too.
	Idempotent and side-effect-free on the UI (callable from #delete)."
	[childProcess ifNotNil: [:p | p sigkill]] on: Error do: [:e | nil].
	scriptPath ifNotNil: [
		[OSProcess command: 'pkill -9 -f ', scriptPath printString]
			on: Error do: [:e | nil]]
]

{
	#category : #model,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:02'
}
SWACoverageLogTailer >> logContents [
	"Text accessor for the PluggableTextMorph: the accumulated log so far."
	^ accumulated ifNil: [accumulated := '']
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:02'
}
SWACoverageLogTailer >> logPath: aLogPath output: anOutputPath [
	logPath := aLogPath.
	outputPath := anOutputPath.
	bytePosition := 0.
	finished := false.
	finishNotified := false
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 11:15'
}
SWACoverageLogTailer >> markFinished: ok error: isError [
	"Update the status banner text and run onFinish once. No color overrides --
	the banner uses the theme default; the success/error distinction is in the text."
	| msg |
	finishNotified ifTrue: [^ self].
	finishNotified := true.
	msg := isError
		ifTrue: ['FINISHED WITH ERROR -- see log above']
		ifFalse: [(outputPath notNil and: [FileDirectory default fileExists: outputPath])
			ifTrue: ['FINISHED -- wrote ', outputPath]
			ifFalse: ['FINISHED (no output file found)']].
	statusMorph contents: msg.
	self setLabel: 'Coverage log: ', logPath, ' -- DONE'.
	onFinish ifNotNil: [[onFinish value: ok] on: Error do: [:e | nil]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:03'
}
SWACoverageLogTailer >> onFinish: aBlock [
	"A one-arg block evaluated (with a Boolean ok) when the run finishes -- e.g. to
	open the Code Map on the result file."
	onFinish := aBlock
]

{
	#category : #model,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:43'
}
SWACoverageLogTailer >> outContents [
	"Text accessor for the second pane: the child's stdout/Transcript ('.out') so far."
	^ outAccumulated ifNil: [outAccumulated := '']
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:43'
}
SWACoverageLogTailer >> pollLog [
	"Read newly-appended structured-log bytes into the left pane. Finish/error are
	latched from the RAW chunk (sawFinishLine/sawErrorLine) so display capping can't
	hide them."
	| result newText |
	result := self readNewBytesOf: logPath from: bytePosition.
	bytePosition := result key.
	newText := result value.
	newText isEmpty ifTrue: [^ self].
	(newText includesSubstring: 'FORKED CHILD: quitting') ifTrue: [sawFinishLine := true].
	(newText includesSubstring: 'FORKED CHILD: ERROR') ifTrue: [sawErrorLine := true].
	accumulated := self logContents, newText.
	self show: accumulated in: textMorph
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:43'
}
SWACoverageLogTailer >> pollOut [
	"Read newly-appended child stdout/Transcript bytes into the right pane."
	| result newText |
	stderrPath ifNil: [^ self].
	outBytePosition ifNil: [outBytePosition := 0].
	result := self readNewBytesOf: stderrPath from: outBytePosition.
	outBytePosition := result key.
	newText := result value.
	newText isEmpty ifTrue: [^ self].
	outAccumulated := self outContents, newText.
	self show: outAccumulated in: outTextMorph
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:43'
}
SWACoverageLogTailer >> readNewBytesOf: aPath from: aPosition [
	"Read bytes appended to aPath since aPosition. Answer an Association
	newPosition -> newText (newText empty if nothing new). Opens read-only and closes
	immediately so it never blocks the child's writes."
	| stream size newText |
	(FileDirectory default fileExists: aPath) ifFalse: [^ aPosition -> ''].
	stream := FileStream readOnlyFileNamed: aPath.
	stream ifNil: [^ aPosition -> ''].
	^ [size := stream size.
	   size <= aPosition
		ifTrue: [aPosition -> '']
		ifFalse: [stream position: aPosition.
			newText := stream upToEnd.
			size -> newText]]
		ensure: [stream close]
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:43'
}
SWACoverageLogTailer >> show: aString in: aTextMorph [
	"Set aTextMorph's contents to aString (capped to the last 200k chars so a long run
	can't bog the pane), then auto-scroll to the bottom."
	| display |
	display := aString size > 200000
		ifTrue: ['...(earlier output truncated)...', String cr, (aString last: 200000)]
		ifFalse: [aString].
	aTextMorph setText: display asText.
	aTextMorph textMorph ifNotNil: [:tm | tm editor selectAt: display size + 1].
	aTextMorph scrollSelectionIntoView
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:44'
}
SWACoverageLogTailer >> stderrPath: aPath [
	"Path of the child's captured stdout+stderr+Transcript ('.out'), shown live in
	the right pane."
	stderrPath := aPath.
	outBytePosition := 0
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:43'
}
SWACoverageLogTailer >> step [
	"Poll BOTH files (structured log -> left pane, child stdout/.out -> right pane),
	then check for clean completion. All guarded so a transient file error (mid-write
	by the child) never breaks stepping."
	[self pollLog] on: Error do: [:e | nil].
	[self pollOut] on: Error do: [:e | nil].
	[self checkFinished] on: Error do: [:e | nil]
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:02'
}
SWACoverageLogTailer >> stepTime [
	"Poll the log file about twice a second."
	^ 500
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:57'
}
SWACoverageLogTailer >> stopChild [
	"STOP button: kill the forked child (#killChild) and update the banner; the run is
	considered finished-with-error."
	self killChild.
	finished := true.
	finishNotified := false.
	self markFinished: false error: true.
	statusMorph contents: 'STOPPED by user -- child killed'
]

{
	#category : #model,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 13:19'
}
SWACoverageLogTailer >> styledText: aString [
	"Plain text -- let the PluggableTextMorph apply the current theme's text colour.
	(Kept as a hook in case we later want per-line coloring of STAGE/ERROR lines.)"
	^ aString asText
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 11:02'
}
SWACoverageLogTailer >> wantsSteps [
	^ true
]
