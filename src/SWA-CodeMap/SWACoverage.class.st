"
Pluggable execution-measurement source for the Code Map's #coverage color mode.

Produces a Dictionary 'Class>>selector' -> Number (the same shape the cross-ref
machinery consumes, so it feeds straight into SWAView>>highlightWeights:). The
value is mode-dependent but always 'higher = more exercised':

- BOOLEAN coverage (#runTestCoverageOn:): instruments a set of methods with the
  one-shot SUnit TestCoverage wrapper, runs all tests, then maps ran -> 1.
  Methods that never ran are absent (treated as 0 / 'not covered').

- INVOCATION TALLY (#instrumentTally / ... / #collectTally): installs counting
  SWATallyWrappers (Dan Ingalls' Lively Kernel tallyFunc pattern) that stay live
  and increment on every call, self-EVICTING once a method gets too hot (evictAt)
  so the instrumented image keeps running smoothly. You instrument, exercise the
  system however you like, then collect counts.

Both modes share #methods (the methods to watch) and restore every method on
#uninstall.

Class-side convenience:
  SWACoverage testCoverageForPackages: {'Kernel'}   -> boolean map
  SWACoverage new methodsForPackages: {'Morphic*'}; instrumentTally   -> live tally

Instance Variables
	methods    <Collection of CompiledMethod>  the methods under measurement
	wrappers   <Collection>                    live wrappers (tally mode)
	resultMap  <Dictionary>                    'Class>>selector' -> Number
	evictAt    <Integer|nil>                   tally hot-eviction threshold
"
Class {
	#name : #SWACoverage,
	#superclass : #Object,
	#instVars : [
		'methods',
		'wrappers',
		'resultMap',
		'evictAt',
		'watchedMethods',
		'kind'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:30'
}
SWACoverage class >> testCoverageForAll [
	"Whole-image boolean coverage: every non-test method, all tests run."
	^ self testCoverageForPackages: { '*' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:30'
}
SWACoverage class >> testCoverageForPackages: globCollection [
	"Boolean coverage: instrument methods of the matching packages, run all tests,
	answer the finished SWACoverage (its resultMap is 'Class>>selector' -> 1)."
	^ self new
		methodsForPackages: globCollection;
		runTestCoverage;
		yourself
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWACoverage >> collectTally [
	"Read the current invocation counts from the live tally wrappers into resultMap
	('Class>>selector' -> count). Only methods called at least once are recorded.
	Does not uninstall -- call #uninstall when done."
	kind := #tally.
	resultMap := Dictionary new.
	wrappers do: [:w | w count > 0 ifTrue: [
		resultMap at: w crossRefKey put: w count]].
	^ resultMap
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWACoverage >> covers [
	"The live TestCoverage wrappers (boolean mode), kept so a run can be driven
	step by step (install, run some tests, collect partial, repeat)."
	^ wrappers
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:28'
}
SWACoverage >> evictAt: anIntegerOrNil [
	"Tally mode: uninstall a wrapper once its method has been called this many
	times (nil = never evict). Keeps hot methods fast."
	evictAt := anIntegerOrNil
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:28'
}
SWACoverage >> initialize [
	methods := OrderedCollection new.
	wrappers := OrderedCollection new.
	resultMap := Dictionary new.
	evictAt := 1000
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:58'
}
SWACoverage >> installTestCoverage [
	"Install one-shot TestCoverage wrappers on every watched method, WITHOUT running
	anything. Pins the watched-methods array so wrappers and methods stay index-
	aligned even if running tests later recompiles methods. Use with
	#refreshBooleanResult to drive a run step by step, then #uninstallTestCoverage."
	watchedMethods := methods asArray.
	wrappers := watchedMethods collect: [:m |
		TestCoverage new initializeOn: m methodReference].
	wrappers do: [:c | c install].
	^ self
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:30'
}
SWACoverage >> instrumentTally [
	"TALLY mode: install a live counting SWATallyWrapper on every watched method.
	They stay installed and count every call, self-evicting once a method passes
	evictAt so hot methods stop paying overhead. Exercise the system, then send
	#collectTally and #uninstall. Returns self."
	wrappers := methods collect: [:m |
		(SWATallyWrapper new
			onClass: m methodClass selector: m selector evictAt: evictAt)
			install; yourself].
	^ self
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:29'
}
SWACoverage >> keyForMethod: aCompiledMethod [
	"The Code Map cross-ref key 'Class>>selector' for aCompiledMethod, matching
	SWACodeMethodNode>>crossRefKey (metaclass prints as 'Foo class>>bar')."
	^ aCompiledMethod methodClass name asString, '>>', aCompiledMethod selector
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWACoverage >> kind [
	"#boolean (ran/not-run, every value 1) or #tally (invocation counts), set by
	the run methods. Lets the view label per-node values correctly."
	^ kind
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:28'
}
SWACoverage >> methods [
	^ methods
]

{
	#category : #selecting,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:29'
}
SWACoverage >> methodsForAll [
	"Watch every method in the image except those of TestCase subclasses."
	^ self methodsForPackages: { '*' }
]

{
	#category : #selecting,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:29'
}
SWACoverage >> methodsForPackages: globCollection [
	"Watch every method of every package whose name matches one of globCollection
	(String>>match: globs). TestCase methods are excluded -- we measure the code
	under test, not the tests. Returns self."
	| infos |
	infos := PackageInfo allPackages select: [:p |
		globCollection anySatisfy: [:g | g match: p packageName]].
	methods := OrderedCollection new.
	infos do: [:p | p methods do: [:ref | | m |
		m := ref compiledMethod.
		(m notNil and: [(ref actualClass inheritsFrom: TestCase) not])
			ifTrue: [methods add: m]]].
	^ self
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWACoverage >> refreshBooleanResult [
	"Re-read which watched methods have run so far into resultMap (ran -> 1).
	Safe to call repeatedly mid-run. Uses the pinned watchedMethods array so it
	stays index-aligned with wrappers regardless of later recompilation."
	kind := #boolean.
	resultMap := Dictionary new.
	watchedMethods withIndexDo: [:m :i |
		(wrappers at: i) hasRun ifTrue: [
			resultMap at: (self keyForMethod: m) put: 1]].
	^ resultMap
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:28'
}
SWACoverage >> resultMap [
	"Dictionary 'Class>>selector' -> Number, ready for SWAView>>highlightWeights:."
	^ resultMap
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:29'
}
SWACoverage >> runAllTests [
	"Run every concrete TestCase in the image, swallowing failures/errors -- we only
	care which methods got exercised, not whether the tests passed. Abstract test
	classes (no selectors) are skipped."
	TestCase allSubclasses do: [:tc |
		(tc isAbstract not and: [tc testSelectors notEmpty]) ifTrue: [
			[tc suite run] on: Error, Halt do: [:e | e return: nil]]]
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:32'
}
SWACoverage >> runTestCoverage [
	"BOOLEAN mode: instrument every watched method, run ALL tests in the image,
	record ran -> 1. (Heavy: instruments thousands of methods and runs the whole
	suite. Use #runTestCoverageWith: to scope it.)"
	^ self runTestCoverageWith: [self runAllTests]
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:58'
}
SWACoverage >> runTestCoverageWith: aBlock [
	"Like #runTestCoverage but runs aBlock (which should exercise code) instead of
	the whole test suite. Lets callers scope the run (one package's tests, a demo,
	an interaction). Populates resultMap with ran -> 1. Pins the watched-methods
	array so it stays index-aligned with the wrappers even if aBlock recompiles
	methods."
	watchedMethods := methods asArray.
	wrappers := watchedMethods collect: [:m |
		TestCoverage new initializeOn: m methodReference].
	[wrappers do: [:c | c install].
	 aBlock value]
		ensure: [wrappers do: [:c | c uninstall]].
	^ self refreshBooleanResult; yourself
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:30'
}
SWACoverage >> uninstall [
	"Restore every method (tally mode). Idempotent; safe to call after eviction."
	wrappers do: [:w | w uninstall].
	wrappers := OrderedCollection new.
	^ self
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:59'
}
SWACoverage >> uninstallTestCoverage [
	"Remove the installed TestCoverage wrappers from their method dictionaries.
	Keeps the wrapper objects (and their hasRun flags) so a final
	#refreshBooleanResult after uninstall still works."
	wrappers do: [:c | c uninstall].
	^ self
]
