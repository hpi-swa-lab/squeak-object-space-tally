"
Test-only stand-in for a CONTAINER node (package/class) in SWADatasetTest: it has NO crossRefKey (so metrics must roll up from children) and a settable #children collection. Complements SWADuplicationPartnerStub, which models a keyed leaf.
"
Class {
	#name : #SWADatasetTestContainer,
	#superclass : #Object,
	#instVars : [
		'childrenColl'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:55'
}
SWADatasetTestContainer >> children [
	^ childrenColl ifNil: [#()]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:55'
}
SWADatasetTestContainer >> childrenColl: aCollection [
	childrenColl := aCollection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:55'
}
SWADatasetTestContainer >> crossRefKey [
	"A container has no cross-view identity -- metrics must roll up from children."
	^ nil
]
