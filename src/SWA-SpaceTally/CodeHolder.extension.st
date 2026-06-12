Extension { #name : #CodeHolder }

{
	#category : #'*SWA-SpaceTally',
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:42'
}
CodeHolder >> classListMenuSpaceTally: aMenu [
	"Add a 'Space Tally instances' item to the class-list context menu.
	Tallies the memory owned by the selected class's instances, using the
	ignore list so global anchors aren't followed."

	<classListMenu>
	<menuPriority: 145>

	| cls |
	cls := self selectedClassOrMetaClass.
	cls ifNil: [^ aMenu].
	aMenu
		add: 'Space Tally instances'
		target: SWASpaceTally
		selector: #exploreInstancesOf:
		argument: cls.
	^ aMenu
]
