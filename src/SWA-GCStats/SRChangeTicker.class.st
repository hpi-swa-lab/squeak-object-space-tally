"
Ultralight system-change counter for the GC-stats changes lane.

The live SWAChangeTraceRecorder builds a full reaction tree per edit -- far too heavy
to drive an in-frame overlay. This does the opposite: a single SystemChangeNotifier
subscriber that only bumps a counter and remembers the first and last change time of
the current frame. No tree, no allocation probing, no GC -- just mark and time.

The changes graph drains it once per frame with #frameCountAndSpanMicrosThenReset,
which answers { changesThisFrame . spanMicros } and clears the accumulators. spanMicros
is first-to-last change time within the frame, a cheap proxy for how long system-change
work stole from the frame.

SRChangeTicker current is the shared armed instance. Arming subscribes; disarming
unsubscribes, so an idle panel costs nothing.
"
Class {
	#name : #SRChangeTicker,
	#superclass : #Object,
	#instVars : [
		'count',
		'firstMicros',
		'lastMicros',
		'armed',
		'users'
	],
	#classVars : [
		'Current'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:59'
}
SRChangeTicker class >> current [
	^ Current ifNil: [Current := self new]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 15:16'
}
SRChangeTicker class >> releaseCurrent [
	^ Current := nil
]

{
	#category : #control,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
SRChangeTicker >> arm [
	"A default user (e.g. a workspace test). Prefer #armFor: from a panel so it releases
	on close."
	self armFor: self
]

{
	#category : #control,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
SRChangeTicker >> armFor: aUser [
	"Register aUser (a panel) as needing the ticker. A Set, so calling it every frame
	with the same panel is harmless. The subscription goes up on the first user."
	(users ifNil: [users := IdentitySet new]) add: aUser.
	armed ifTrue: [^ self].
	armed := true.
	count := 0. firstMicros := nil. lastMicros := nil.
	SystemChangeNotifier uniqueInstance
		notify: self ofAllSystemChangesUsing: #noteChange:
]

{
	#category : #control,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
SRChangeTicker >> disarm [
	self disarmFor: self
]

{
	#category : #control,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
SRChangeTicker >> disarmFor: aUser [
	"aUser (a panel) no longer needs the ticker. Unsubscribe only when the last one
	goes -- desktop and XR panels can be open at once."
	users ifNotNil: [users remove: aUser ifAbsent: []].
	(users notNil and: [users notEmpty]) ifTrue: [^ self].
	armed ifFalse: [^ self].
	armed := false.
	SystemChangeNotifier uniqueInstance noMoreNotificationsFor: self
]

{
	#category : #frame,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:14'
}
SRChangeTicker >> frameCountAndSpanMicrosThenReset [
	"Drain one frame: answer { changesThisFrame . spanMicros } and clear. spanMicros is
	first-to-last change time this frame (0 when 0 or 1 change). Called once per frame
	by the changes graph."
	| n span |
	n := count.
	span := (firstMicros notNil and: [lastMicros notNil])
		ifTrue: [lastMicros - firstMicros]
		ifFalse: [0].
	"Subtract what we read rather than zeroing: noteChange: runs on the editing process
	while this runs on the UI process, and a plain count := 0 loses any change that
	arrived between reading n and the reset. Subtracting n keeps late arrivals."
	count := count - n.
	firstMicros := nil. lastMicros := nil.
	^ { n. span }
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
SRChangeTicker >> initialize [
	count := 0.
	armed := false.
	users := IdentitySet new.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:59'
}
SRChangeTicker >> isArmed [
	^ armed
]

{
	#category : #capture,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:59'
}
SRChangeTicker >> noteChange: anEvent [
	"The whole per-change cost: bump the counter and stamp first/last time. No tree, no
	allocation read, nothing that could itself perturb a frame."
	| now |
	now := Time utcMicrosecondClock.
	count := count + 1.
	firstMicros ifNil: [firstMicros := now].
	lastMicros := now
]
