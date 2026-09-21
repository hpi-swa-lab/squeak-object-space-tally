Extension { #name : #DialogWindow }

{
	#category : #'*SWA-Base',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 17:51'
}
DialogWindow >> getUserResponseIn: aMorph [
	"Run me modally as a child of aMorph and answer my result. A tool rendered as a
	texture -- SqueakXR's SRMorphPanel -- needs its dialogs inside the morph it hosts,
	otherwise every prompt detaches into a second panel floating in front of the user.

	When aMorph is not a world I clamp myself into its bounds (nothing else would),
	and I still drive the modal loop from the real world, since that is what runs the
	cycles."
	| hand world delta |
	self message ifEmpty: [messageMorph delete]. "Do not waste space."
	self paneMorph submorphs
		ifEmpty: ["Do not waste space and avoid strange button-row wraps."
			self paneMorph delete.
			self buttonRowMorph wrapDirection: #none].

	hand := self currentHand.
	world := aMorph isWorldMorph ifTrue: [aMorph] ifFalse: [aMorph world].

	self fullBounds.
	self morphicLayerNumber: self class dialogLayer.
	self moveToPreferredPosition.
	aMorph isWorldMorph
		ifTrue: [self openInWorld: aMorph]
		ifFalse: [
			delta := self bounds amountToTranslateWithin: aMorph bounds.
			delta isZero ifFalse: [self position: self position + delta].
			aMorph addMorphFront: self].

	hand showTemporaryCursor: nil. "Since we are out of context, reset the cursor."

	hand keyboardFocus in: [:priorKeyboardFocus |
		hand mouseFocus in: [:priorMouseFocus |
			self exclusive ifTrue: [hand newMouseFocus: self].
			hand newKeyboardFocus: self defaultFocusMorph.

			[[self isInWorld] whileTrue: [world doOneSubCycle]]
				ifCurtailed: [self cancelDialog].

			hand newKeyboardFocus: priorKeyboardFocus.

			self flag: #discuss. "Since 2016 we are having this *ping pong* between (a) restoring the prior mouse focus and (b) just clearing it globally. The former solution makes more sense while the latter fixes issues with some modal dialogs. We have to investigate this further."
			hand releaseMouseFocus.
			"hand newMouseFocus: priorMouseFocus."]].

	^ result
]
