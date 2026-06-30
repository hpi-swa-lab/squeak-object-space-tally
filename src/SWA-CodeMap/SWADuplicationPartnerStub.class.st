"
A minimal stand-in for a near-duplicate PARTNER method that is referenced by loaded SWADuplicationData but is NOT present in the currently-displayed Code Map tree (e.g. the data was generated over a wider package set than is on screen).

It answers just enough for the duplication consumers:
  crossRefKey -- for the details side-pane list and pair de-duplication,
  loc         -- for the shared-duplicated-lines link-width estimate,
  parent      -- nil, so the link-drawing ancestor walk terminates,
  children    -- empty,
and it is intentionally NOT a SWACodeMethodNode and never appears in the
treemap's tiles, so SWATreemapMorph>>rectForNode: returns nil for it and NO link
is drawn to it. Per Jens's call: off-screen partners are listed in the details
pane but not drawn on the map.
"
Class {
	#name : #SWADuplicationPartnerStub,
	#superclass : #Object,
	#instVars : [
		'crossRefKey',
		'loc'
	],
	#category : #'SWA-CodeMap-Duplication',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationPartnerStub >> children [
	^ #()
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationPartnerStub >> crossRefKey [
	^ crossRefKey
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationPartnerStub >> crossRefKey: aString loc: anInteger [
	crossRefKey := aString.
	loc := anInteger
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationPartnerStub >> loc [
	^ loc
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationPartnerStub >> parent [
	"No parent: the link-drawing nearest-visible-ancestor walk terminates here,
	and since this stub is never in the tiles, no link is drawn."
	^ nil
]
