"
Metacello baseline for the Object Space Tally tools.

Load with:

	Metacello new
		baseline: 'ObjectSpaceTally';
		repository: 'github://hpi-swa-lab/squeak-object-space-tally:main/src';
		load.
"
Class {
	#name : #BaselineOfObjectSpaceTally,
	#superclass : #BaselineOf,
	#category : #BaselineOfObjectSpaceTally
}

{ #category : #baselines }
BaselineOfObjectSpaceTally >> baseline: spec [
	<baseline>
	spec for: #common do: [
		spec package: 'SWA-SpaceTally' ].
]
