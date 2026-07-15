"
A lean tree node for a simulated-heap tally (see SWASimSpaceTally).

Like SWASpaceTallyNode but wraps a simulated object identified by an oop
(simulated heap address) plus a SimObjectMirror, instead of a live host object.

  simulator - the StackInterpreterSimulator whose memory we walked
  oop       - the simulated heap address this node wraps (nil for root)
  mirror    - the SimObjectMirror for that object (nil for root)

#object returns the mirror so the explorer/treemap can reach the simulated
object opaquely (e.g. shift-click). All other rendering (sizes, children,
treemap, diff) is inherited unchanged.
"
Class {
	#name : #SWASimSpaceTallyNode,
	#superclass : #AnObsoleteSWASpaceTallyNode,
	#instVars : [
		'simulator',
		'oop',
		'mirror'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:26'
}
SWASimSpaceTallyNode >> mirror [
	"The SimObjectMirror for this node's simulated object (nil for root)."

	^ mirror
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:26'
}
SWASimSpaceTallyNode >> object [
	"The analyzed object. For a sim tally this is the mirror, not a host
	object. The explorer/treemap only use it opaquely (shift-click)."

	^ mirror
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:26'
}
SWASimSpaceTallyNode >> oop [
	"The simulated heap address this node wraps (nil for the synthetic root)."

	^ oop
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:26'
}
SWASimSpaceTallyNode >> setOop: anOop mirror: aMirror [
	"Record the simulated object and capture class name + self size up front."

	oop := anOop.
	mirror := aMirror.
	self setClassName: aMirror simClassName selfSize: aMirror byteSize totalSize: 0
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:26'
}
SWASimSpaceTallyNode >> setSimulator: aStackInterpreterSimulator [
	simulator := aStackInterpreterSimulator
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:26'
}
SWASimSpaceTallyNode >> simulator [
	^ simulator
]
