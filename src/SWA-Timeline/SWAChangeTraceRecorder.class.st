"
Captures live SystemChangeNotifier events into a rolling SWAChangeTraceNode tree for
the SWA change trace timeline.

Each edit (class/method add/remove/modify/recategorize) fans out synchronously to
~8 subscribers; GSCodeMapper (GitS) and MCWorkingCopy are the expensive ones. This
recorder is itself one more subscriber, deliberately cheap, and records for every
event: a microsecond stamp, the change type, a Class>>selector label, and the bytes
allocated during the fan-out.

Allocation is measured with vmParameterAt: 34 (bytes allocated since last full GC),
a cheap monotonic-ish counter; a full GC between two events resets it, so a negative
delta is clamped to 0. The delta is measured since the previously recorded event, so
it attributes the whole fan-out's cost to the edit rather than to one subscriber.

SWAChangeTraceRecorder default is the shared live recorder. Open the timeline with
SWAChangeTraceRecorder open.
"
Class {
	#name : #SWAChangeTraceRecorder,
	#superclass : #Object,
	#instVars : [
		'root',
		'leaves',
		'capacity',
		'lastAllocated',
		'running',
		'view',
		'currentChange'
	],
	#classVars : [
		'Default'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:04'
}
SWAChangeTraceRecorder class >> default [
	^Default ifNil: [Default := self new]
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:02'
}
SWAChangeTraceRecorder class >> open [
	"Open the recorded trace (snapshot) in the SWAPane chrome. Record first with
	#record, or use #stopAndOpen. Answers the window."
	^self default open
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:02'
}
SWAChangeTraceRecorder class >> openRecorded [
	"Open the trace on what has been recorded so far (a snapshot, no live refresh)."
	^ self default open
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:01'
}
SWAChangeTraceRecorder class >> record [
	"Start (or restart) capturing into the shared recorder -- no window. Edit code, then
	SWAChangeTraceRecorder openRecorded to inspect what was captured."
	^ self default start
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:04'
}
SWAChangeTraceRecorder class >> reset [
	Default ifNotNil: [Default stop].
	Default := nil.
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:01'
}
SWAChangeTraceRecorder class >> stopAndOpen [
	"Stop capturing and open the recorded trace for analysis."
	self default stop.
	^ self default open
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:02'
}
SWAChangeTraceRecorder class >> xrMenuOpen: aMenu [
	"Open the RECORDED change trace in the 2D world; the framework promotes the window
	into 3D. Record with 'Change Trace: record' first. Inert without SqueakXR."
	<xrMenu: #(world debug) label: 'Change Trace: open recorded' priority: 441>
	^ self open
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:02'
}
SWAChangeTraceRecorder class >> xrMenuRecord: aMenu [
	"Start (or restart) recording the change trace, no window. Do the edits, then
	'Change Trace: stop + open'. Inert without SqueakXR."
	<xrMenu: #(world debug) label: 'Change Trace: record' priority: 439>
	^ self record
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:02'
}
SWAChangeTraceRecorder class >> xrMenuStopAndOpen: aMenu [
	"Stop recording and open the captured trace for analysis. Inert without SqueakXR."
	<xrMenu: #(world debug) label: 'Change Trace: stop + open' priority: 442>
	^ self stopAndOpen
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:05'
}
SWAChangeTraceRecorder >> allocatedBytes [
	"Bytes allocated since the last full GC. Monotonic between full GCs; a full GC
	resets it, which the delta computation in #systemChanged: clamps to 0."
	^Smalltalk vmParameterAt: 34
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:22'
}
SWAChangeTraceRecorder >> beginChange: anEvent [
	"Open a change node for one edit's fan-out. Its reaction children are added by
	#reaction:micros:bytes: as each subscriber runs; #endChange seals it."
	running ifFalse: [^self].
	currentChange := SWAChangeTraceNode new
		kind: #change;
		changeType: (self changeTypeFor: anEvent);
		methodClassName: (anEvent itemClass ifNotNil: [:c | c name asString]);
		methodSelector: anEvent itemSelector;
		label: (self labelFor: anEvent);
		timeStamp: DateAndTime now;
		micros: Time utcMicrosecondClock allocatedBytes: 0;
		yourself.
	currentChange children: OrderedCollection new.
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:05'
}
SWAChangeTraceRecorder >> changeTypeFor: anEvent [
	"Map the notifier's changeKind (#Added #Removed ...) to the lowercase symbols the
	kind color dictionary keys on."
	| k |
	k := anEvent changeKind.
	k == #Added ifTrue: [^#added].
	k == #Removed ifTrue: [^#removed].
	k == #Modified ifTrue: [^#modified].
	k == #Recategorized ifTrue: [^#recategorized].
	k == #Commented ifTrue: [^#commented].
	k == #Renamed ifTrue: [^#renamed].
	k == #DoIt ifTrue: [^#doIt].
	^k
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:26'
}
SWAChangeTraceRecorder >> clear [
	leaves := OrderedCollection new: capacity.
	lastAllocated := self allocatedBytes.
	currentChange := nil.
	self rebuildRoot.
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:23'
}
SWAChangeTraceRecorder >> endChange [
	"Seal the current change and add it to the rolling buffer."
	(running and: [currentChange notNil]) ifFalse: [^self].
	leaves size >= capacity ifTrue: [leaves removeFirst].
	leaves addLast: currentChange.
	root children: leaves copy.
	currentChange := nil.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:26'
}
SWAChangeTraceRecorder >> infoString [
	| total reactions |
	total := leaves inject: 0 into: [:s :n | s + n allocatedBytes].
	reactions := leaves inject: 0 into: [:s :n | s + n children size].
	^(running ifTrue: ['recording'] ifFalse: ['stopped']), '   ',
		leaves size printString, ' changes',
		'   ', reactions printString, ' reactions',
		'   ', (total // 1024) printString, ' KB allocated in fan-out'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:04'
}
SWAChangeTraceRecorder >> initialize [
	capacity := 2000.
	running := false.
	self clear.
]

{
	#category : #instrumentation,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:23'
}
SWAChangeTraceRecorder >> installInstrumentation [
	"Replace each of the change notifier's action sequences with an instrumented copy
	that reports every subscriber send to me. Same subscribers, same order -- only the
	sequence class changes -- so behaviour is unchanged while it measures."
	| src map |
	src := SystemChangeNotifier uniqueInstance instVarNamed: 'eventSource'.
	map := src instVarNamed: 'actionMap'.
	map keysAndValuesDo: [:evt :seq |
		(seq isKindOf: SWAInstrumentedActionSequence) ifFalse: [
			| instrumented |
			instrumented := SWAInstrumentedActionSequence withAll: seq.
			instrumented recorder: self.
			map at: evt put: instrumented]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:04'
}
SWAChangeTraceRecorder >> isRunning [
	^running
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:05'
}
SWAChangeTraceRecorder >> labelFor: anEvent [
	| cls sel |
	cls := anEvent itemClass ifNil: [^anEvent item printString].
	sel := anEvent itemSelector.
	^sel
		ifNil: [cls name asString]
		ifNotNil: [cls name asString, '>>', sel asString]
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:01'
}
SWAChangeTraceRecorder >> open [
	"Open the trace on whatever has been RECORDED so far -- a snapshot, not a live view.

	The live SWATimelineMorph rebuild-per-change was too heavy to drive at frame rate
	(that job is now the GC-stats changes lane's). This displays the finished reaction
	tree for detailed offline analysis -- subscribers, durations, bytes -- with the full
	zoom/pan/select chrome and NO stepper fighting the user. Record first with #start /
	edit / #stop, then call this. If still recording, it shows the tree so far frozen."
	| chart panel |
	chart := SWAChangeTraceMorph on: root.
	view := chart.
	chart metaInfo: self infoString.
	panel := SWAPane on: chart.
	^ panel
		openInWindowLabeled: 'SWA Change Trace (recorded)'
		bounds: (((Display extent - (1200 @ 700)) // 2) extent: 1200 @ 700)
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:23'
}
SWAChangeTraceRecorder >> reaction: aMessageSend micros: durMicros bytes: bytesOrNil [
	"Record one subscriber's reaction under the current change. bytesOrNil is nil only
	if a caller could not measure it; treat that as 0 for weight."
	| name reaction |
	(running and: [currentChange notNil]) ifFalse: [^self].
	name := self subscriberNameFor: aMessageSend.
	reaction := SWAChangeReactionNode new
		subscriberName: name
		micros: Time utcMicrosecondClock
		durationMicros: durMicros
		allocatedBytes: (bytesOrNil ifNil: [0]).
	currentChange children add: reaction.
	reaction parent: currentChange.
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:05'
}
SWAChangeTraceRecorder >> rebuildRoot [
	root := SWAChangeTraceNode new
		kind: #root;
		label: 'Live changes';
		yourself.
	root children: leaves copy.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:04'
}
SWAChangeTraceRecorder >> root [
	^root
]

{
	#category : #control,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:22'
}
SWAChangeTraceRecorder >> start [
	running ifTrue: [^self].
	self clear.
	running := true.
	self installInstrumentation.
]

{
	#category : #control,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:22'
}
SWAChangeTraceRecorder >> stop [
	running := false.
	self uninstallInstrumentation.
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:23'
}
SWAChangeTraceRecorder >> subscriberNameFor: aMessageSend [
	"'Receiver>>selector'. A class receiver is shown as 'Foo class>>sel' so the browse
	link resolves to the metaclass method."
	| rcvr rcvrName |
	rcvr := aMessageSend receiver.
	rcvrName := rcvr isBehavior
		ifTrue: [rcvr name asString, (rcvr isMeta ifTrue: [''] ifFalse: [' class'])]
		ifFalse: [rcvr class name asString].
	^ rcvrName, '>>', aMessageSend selector asString
]

{
	#category : #instrumentation,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:23'
}
SWAChangeTraceRecorder >> uninstallInstrumentation [
	"Restore plain sequences. Rebuild an ordinary WeakActionSequenceTrappingErrors from
	each instrumented one so the notifier is exactly as it was before recording."
	| src map |
	src := SystemChangeNotifier uniqueInstance instVarNamed: 'eventSource'.
	map := src instVarNamed: 'actionMap'.
	map keysAndValuesDo: [:evt :seq |
		(seq isKindOf: SWAInstrumentedActionSequence) ifTrue: [
			map at: evt put: (WeakActionSequenceTrappingErrors withAll: seq)]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:05'
}
SWAChangeTraceRecorder >> view: aMorph [
	view := aMorph.
]
