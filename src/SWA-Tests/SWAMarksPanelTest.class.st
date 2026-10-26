Class {
	#name : #SWAMarksPanelTest,
	#superclass : #TestCase,
	#instVars : [
		'pane',
		'panel',
		'savedDefault',
		'savedReviewed'
	],
	#category : #'SWA-Tests'
}

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> buttonFor: aSelector [

	panel allMorphsDo: [:each |
		((each isKindOf: SimpleButtonMorph) and: [each actionSelector == aSelector]) ifTrue: [^ each]].
	^ nil
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> list: aSelector [

	panel allMorphsDo: [:each |
		((each isKindOf: SWAMarksListMorph) and: [each getListSelector == aSelector]) ifTrue: [^ each]].
	^ nil
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:36'
}
SWAMarksPanelTest >> setUp [
	"Fresh sets, so the user's marks and sign-offs are neither read nor changed."

	savedDefault := SWAMarkSet classPool at: #Default.
	savedReviewed := SWAMarkSet classPool at: #Reviewed.
	SWAMarkSet classPool at: #Default put: SWAMarkSet new.
	SWAMarkSet classPool at: #Reviewed put: SWAMarkSet new.
	SWAMarkSet default addAll: #('SRAvatar' 'SRAvatar>>turnBy:' 'SRHand>>tool').
	SWAMarkSet reviewed addAll: #('SRAvatar>>teleportTo: 1a2b3c' 'SRWorld>>stop 4d5e6f').
	pane := SWAPane on: (SWACodeTreemapMorph new
		setRoot: (SWACodeRootNode new addPackages: 'SWA-Widgets'; yourself);
		yourself).
	panel := pane newMarksPanel.
	pane updateMarksList.
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> tearDown [

	SWAMarkSet classPool at: #Default put: savedDefault.
	SWAMarkSet classPool at: #Reviewed put: savedReviewed.
	SWAMarkSet default notifyPanes.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testACommentGoesToTheSetOfTheSelectedRow [

	pane reviewedPrimaryIndex: 2 shifted: false controlled: true.
	pane acceptComment: 'looked at it'.
	self assert: 'looked at it' equals: (SWAMarkSet reviewed commentAt: 'SRWorld>>stop 4d5e6f') asString.
	self assert: '' equals: (SWAMarkSet default commentAt: 'SRWorld>>stop 4d5e6f') asString.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testEachListHasItsOwnLoadButton [

	self assert: (self buttonFor: #loadMarks) notNil.
	self assert: (self buttonFor: #loadReviewed) notNil.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testRemovingASelectedReviewLeavesTheMarks [

	pane reviewedPrimaryIndex: 1 shifted: false controlled: true.
	pane removeSelectedMark.
	self assert: #('SRWorld>>stop 4d5e6f') equals: pane reviewedListItems.
	self assert: 3 equals: pane marksListItems size.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testReviewsHaveTheirOwnList [

	self assert: #('SRAvatar' 'SRAvatar>>turnBy:' 'SRHand>>tool') equals: pane marksListItems.
	self assert: #('SRAvatar>>teleportTo: 1a2b3c' 'SRWorld>>stop 4d5e6f') equals: pane reviewedListItems.
	self assert: (self list: #reviewedListItems) notNil.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testSelectingAReviewTakesThePrimaryRowFromTheMarks [

	pane marksPrimaryIndex: 2 shifted: false controlled: true.
	self assert: 2 equals: pane marksPrimaryIndex.
	pane reviewedPrimaryIndex: 1 shifted: false controlled: true.
	self assert: 0 equals: pane marksPrimaryIndex.
	self assert: 1 equals: pane reviewedPrimaryIndex.
	self assert: (pane reviewedListSelectionAt: 1).
	self deny: (pane reviewedListSelectionAt: 2).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testShiftSelectsARangeWithinTheReviewedList [

	pane reviewedPrimaryIndex: 1 shifted: false controlled: true.
	pane reviewedPrimaryIndex: 2 shifted: true controlled: false.
	self assert: (pane reviewedListSelectionAt: 1).
	self assert: (pane reviewedListSelectionAt: 2).
	self deny: (pane marksListSelectionAt: 1).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> testTheLoadButtonSitsAboveTheMarksList [

	| column |
	column := (self list: #marksListItems) owner.
	self
		assert: (column submorphs indexOf: (self buttonFor: #loadMarks) owner)
		< (column submorphs indexOf: (self list: #marksListItems)).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:36'
}
SWAMarksPanelTest >> testTheTitlesCountEachSet [

	self assert: (self titles includes: 'Marks (3)').
	self assert: (self titles includes: 'Reviewed (2)').
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:35'
}
SWAMarksPanelTest >> titles [

	| titles |
	titles := OrderedCollection new.
	panel allMorphsDo: [:each | ((each isMemberOf: StringMorph) and: [each contents notNil]) ifTrue: [titles add: each contents asString]].
	^ titles
]
