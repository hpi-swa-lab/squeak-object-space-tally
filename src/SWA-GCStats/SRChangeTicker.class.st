"
Counts SystemChangeNotifier events and the time span they covered, so the
changes lane of a GC Stats panel can draw one bar per frame.

One ticker per graph, not one for the system: the drain is destructive, so a
shared ticker would let whichever panel updated first take the count and leave
the others drawing zero.

SystemChangeNotifier holds its subscribers strongly, so an armed ticker is
alive until #stop. Whoever owns one owes it a #stop.
"
Class {
	#name : #SRChangeTicker,
	#superclass : #Object,
	#instVars : [
		'count',
		'firstMicros',
		'lastMicros',
		'armed',
		'drainCount',
		'drainSpan'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #frame,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:09'
}
SRChangeTicker >> drainCount [
	"Change count from the last #frameCountAndSpanMicrosThenReset."
	^ drainCount
]

{
	#category : #frame,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:09'
}
SRChangeTicker >> drainSpan [
	"First-to-last change span (micros) from the last #frameCountAndSpanMicrosThenReset."
	^ drainSpan
]

{
	#category : #frame,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:09'
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
	"Store into retained slots instead of answering a fresh Array -- this runs every frame
	on the changes lane and the pair was one Array/frame of young garbage. Read via
	#drainCount / #drainSpan right after."
	drainCount := n. drainSpan := span
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:15'
}
SRChangeTicker >> initialize [
	count := 0.
	armed := false.
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

{
	#category : #arming,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:15'
}
SRChangeTicker >> start [
	armed ifTrue: [^ self].
	armed := true.
	count := 0. firstMicros := nil. lastMicros := nil.
	SystemChangeNotifier uniqueInstance
		notify: self ofAllSystemChangesUsing: #noteChange:.
]

{
	#category : #arming,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:15'
}
SRChangeTicker >> stop [
	armed ifFalse: [^ self].
	armed := false.
	SystemChangeNotifier uniqueInstance noMoreNotificationsFor: self.
]
