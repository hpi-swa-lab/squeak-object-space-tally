"
A method wrapper that records WHICH TEST covered this method, for the PathTools-
style test<->method relation in SWACoverageData.

Installed in a method dictionary in place of the real method (like SWATallyWrapper
and SUnit's TestCoverage). On each call it forwards to the original, but first --
if a test is currently running (SWACoverage CurrentTestName) and this is the first
call under that test -- it records (currentTest covers thisMethod) into the shared
SWACoverageData. De-dups per test via lastTestId so a method called many times by
one test is recorded once.

The wrapper stays installed across the whole run (unlike the one-shot TestCoverage)
so it keeps attributing to each successive test.

Instance Variables
	theClass        <Behavior>
	selector        <Symbol>
	originalMethod  <CompiledMethod>   restored on uninstall
	data            <SWACoverageData>  shared relation being built
	lastTestId      <Object>           the test id last recorded for (de-dup)
"
Class {
	#name : #SWACoverageWrapper,
	#superclass : #Object,
	#instVars : [
		'theClass',
		'selector',
		'originalMethod',
		'data',
		'lastTestId',
		'methodNameString'
	],
	#classVars : [
		'CurrentTest',
		'Recording',
		'Sink'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:49'
}
SWACoverageWrapper class >> currentTest: aTestNameOrNil [
	"Set by the run loop before each individual test runs. Read send-free by the hot
	path via the CurrentTest class var."
	CurrentTest := aTestNameOrNil
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:49'
}
SWACoverageWrapper class >> emit: aMethodName test: aTestName [
	"Record one (test covers method) pair into the active sink. Only ever called with
	Recording=true, so any instrumented collection/stream methods used here fall
	through the wrappers harmlessly. Sink is a SWACoverageData set via #sink:."
	Sink ifNotNil: [Sink recordTest: aTestName covers: aMethodName]
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:49'
}
SWACoverageWrapper class >> resetRecordingState [
	"Clear all shared recording state. Called before and after a run so a crash or
	stray flag can't wedge attribution off."
	Recording := false.
	CurrentTest := nil.
	Sink := nil
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:49'
}
SWACoverageWrapper class >> sink: aCoverageDataOrNil [
	"The SWACoverageData receiving emitted pairs (nil to disable)."
	Sink := aCoverageDataOrNil
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:46'
}
SWACoverageWrapper >> doesNotUnderstand: aMessage [
	"Forward any reflection the system does on the installed 'method'."
	^ originalMethod perform: aMessage selector withArguments: aMessage arguments
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:46'
}
SWACoverageWrapper >> install [
	theClass methodDictionary at: selector put: self.
	theClass flushCache
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:48'
}
SWACoverageWrapper >> methodName [
	"Precomputed 'Class>>selector' (built at install, never in the hot path)."
	^ methodNameString
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:48'
}
SWACoverageWrapper >> onClass: aClass selector: aSelector data: aCoverageData [
	"Precompute the 'Class>>selector' string NOW (at install, never in the hot path)
	so #run:with:in: does zero string-building -- string ops like #, and #asString
	are themselves instrumented and would re-enter the wrapper."
	theClass := aClass.
	selector := aSelector.
	originalMethod := aClass >> aSelector.
	data := aCoverageData.
	lastTestId := nil.
	methodNameString := aClass name asString, '>>', aSelector
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:48'
}
SWACoverageWrapper >> run: aSelector with: anArray in: aReceiver [
	"VM entry point for the wrapped send. Hot path is deliberately send-free until we
	decide to record:
	 - Recording (class var) read -> push literal variable, NO send
	 - CurrentTest (class var) read -> NO send
	 - lastTestId (ivar) read/compare with == -> NO send
	 - ifTrue:/ifFalse:/and: with literal blocks -> inlined, NO send
	So nested wrapped methods reached WHILE recording (which has Recording=true) fall
	straight through to the forward, breaking the recursion that crashed whole-image
	runs.

	When we do record, we set Recording, emit one line to the shared sink, clear
	Recording (ensure:), then forward. Both the sink write and the flag set happen
	only with Recording already true, so they are immune to re-entry.

	De-dup: lastTestId == CurrentTest means we already recorded this method for the
	running test."
	(Recording == true) ifFalse: [
		(CurrentTest notNil and: [lastTestId ~~ CurrentTest]) ifTrue: [
			lastTestId := CurrentTest.
			Recording := true.
			[SWACoverageWrapper emit: methodNameString test: CurrentTest]
				ensure: [Recording := false]]].
	^ aReceiver withArgs: anArray executeMethod: originalMethod
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:46'
}
SWACoverageWrapper >> uninstall [
	"Restore the real method. Idempotent."
	(theClass methodDictionary at: selector ifAbsent: [nil]) == self
		ifTrue: [theClass methodDictionary at: selector put: originalMethod.
			theClass flushCache]
]
