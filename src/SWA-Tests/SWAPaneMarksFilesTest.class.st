Class {
	#name : #SWAPaneMarksFilesTest,
	#superclass : #TestCase,
	#instVars : [
		'savedDirectory'
	],
	#category : #'SWA-Tests'
}

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:02'
}
SWAPaneMarksFilesTest >> setUp [

	savedDirectory := SWAPane classPool at: #MarksDirectory.
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:02'
}
SWAPaneMarksFilesTest >> tearDown [

	SWAPane classPool at: #MarksDirectory put: savedDirectory.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:02'
}
SWAPaneMarksFilesTest >> testAVanishedDirectoryFallsBackToTheImageDirectory [

	SWAPane noteMarksFile: (FileDirectory default fullNameFor: 'no-such-dir/marks.json').
	self assert: FileDirectory default fullName equals: SWAPane marksDirectory fullName.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:02'
}
SWAPaneMarksFilesTest >> testCancellingRemembersNothing [

	SWAPane classPool at: #MarksDirectory put: nil.
	self assert: nil equals: ([SWAPane basicNew chooseMarksFileLabelled: 'Load marks from file']
		valueSupplyingAnswers: {{'Load marks from file'. ''}}).
	self assert: FileDirectory default fullName equals: SWAPane marksDirectory fullName.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/26/2026 15:02'
}
SWAPaneMarksFilesTest >> testChoosingAFileRemembersItsDirectory [

	| dir file chosen |
	dir := FileDirectory default directoryNamed: 'swa-tests-marks'.
	file := dir fullNameFor: 'some.json'.
	dir assureExistence.
	[chosen := [SWAPane basicNew chooseMarksFileLabelled: 'Load marks from file']
		valueSupplyingAnswers: {{'Load marks from file'. file}}.
	self assert: file equals: chosen.
	self assert: dir fullName equals: SWAPane marksDirectory fullName.
	self assert: (dir fullNameFor: 'swa-marks.json') equals: SWAPane basicNew defaultMarksFileName]
		ensure: [dir recursiveDelete].
]
