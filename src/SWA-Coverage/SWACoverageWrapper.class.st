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
	#superclass : #SWAMethodWrapper,
	#instVars : [
		'data',
		'lastTestId'
	],
	#classVars : [
		'CurrentTest',
		'Recording',
		'Sink'
	],
	#category : #'SWA-Coverage',
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
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:33'
}
SWACoverageWrapper class >> emit: aMethodName test: aTestName [
	"Record one (test covers method) pair into the active sink. Called from
	#captureIn:, which the base template invokes inside #guardedDo: -- so the
	reentrancy guard is raised and the dictionary/string sends in #recordTest:covers:
	fall through their wrappers harmlessly. Sink is a SWACoverageData set via #sink:."
	Sink ifNotNil: [Sink recordTest: aTestName covers: aMethodName]
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:27'
}
SWACoverageWrapper class >> resetRecordingState [
	"Clear all shared coverage state AND the base reentrancy guard, so a crash or a
	stray flag can't wedge attribution off (Recording) or wedge every wrapper into
	pass-through (InWrapper). Called before and after a run."
	Recording := false.
	CurrentTest := nil.
	Sink := nil.
	SWAMethodWrapper resetGuard
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
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:26'
}
SWACoverageWrapper class >> whileRecordingDo: aBlock [
	"Open the recording-active LAYER (Recording=true) for the dynamic extent of aBlock
	-- the measuring window -- restoring the previous value afterwards. Coverage only
	attributes while this layer is on, so the runner wraps ONLY #testCase run with it;
	all the runner's own scaffolding runs with Recording=false and is never
	attributed.

	NOTE: this is the SEMANTIC layer (what to capture), independent of the base
	reentrancy guard (InWrapper, which prevents the wrapper recursing into itself).
	Both must cooperate: capture happens only when Recording=true AND not InWrapper."
	| was |
	was := Recording.
	Recording := true.
	^ aBlock ensure: [Recording := was]
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:52'
}
SWACoverageWrapper >> captureIn: aReceiver [
	"Coverage capture hook, called by the base template ONLY when not guarded -- i.e.
	we are inside the measuring window the runner opened around #testCase run
	(#whileUnguardedDo:). So we no longer need a separate Recording flag: being here
	means 'attribute now'. We only need CurrentTest (what to attribute to) and the
	de-dup (lastTestId == CurrentTest means already recorded for this test).

	The base template raises InWrapper around this call, so the dictionary/string
	sends in #emit:test: -> #recordTest:covers: fall through their wrappers."
	(CurrentTest notNil and: [lastTestId ~~ CurrentTest]) ifTrue: [
		lastTestId := CurrentTest.
		SWACoverageWrapper emit: methodNameString test: CurrentTest]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:31'
}
SWACoverageWrapper >> onClass: aClass selector: aSelector data: aCoverageData [
	"Coverage-specific init: base setup (class/selector/originalMethod/name) via
	super, plus the coverage data sink and per-instance de-dup state."
	self onClass: aClass selector: aSelector.
	data := aCoverageData.
	lastTestId := nil
]
