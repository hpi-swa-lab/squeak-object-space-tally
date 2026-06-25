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
		'kind',
		'exclusions',
		'log',
		'maxTestsPerMethod'
	],
	#classVars : [
		'CurrentTestName',
		'InMetaMode'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:07'
}
SWACoverage class >> allRunnableTestClasses [
	"Every concrete TestCase in the image with tests, MINUS the name/category
	exclusions (UI/process/network/package-loading suites that hang an unattended
	run)."
	| nameExcl catExcl |
	nameExcl := self excludedTestClassPatterns.
	catExcl := self excludedTestCategoryPatterns.
	^ (TestCase allSubclasses select: [:tc | | cat |
		cat := tc category ifNil: [''].
		tc isAbstract not and: [tc testSelectors notEmpty and: [
			(nameExcl anySatisfy: [:g | g match: tc name]) not
				and: [(catExcl anySatisfy: [:g | g match: cat]) not]]]]) asArray
]

{
	#category : #attribution,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:46'
}
SWACoverage class >> currentTestName [
	"The 'Class>>selector' of the test currently running during a coverage-with-
	provenance pass, or nil. Read by SWACoverageWrapper to attribute methods."
	^ CurrentTestName
]

{
	#category : #attribution,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:46'
}
SWACoverage class >> currentTestName: aStringOrNil [
	"Set by the run loop before each individual test runs."
	CurrentTestName := aStringOrNil
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:32'
}
SWACoverage class >> everyTestClass [
	"EVERY concrete TestCase in the image with tests -- no exclusions. The standalone
	generator runs them all; if something breaks or hangs we find out (the Stop
	button and CI timeouts are the safety net, not a hand-maintained skip list)."
	^ (TestCase allSubclasses select: [:tc |
		tc isAbstract not and: [tc testSelectors notEmpty]]) asArray
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:46'
}
SWACoverage class >> excludedPackagePatterns [
	"Emptied by request: no packages are excluded from instrumentation by default.
	(Previously excluded SUnit/Kernel/Collections/Morphic/Tools/our own tools etc.)
	The only remaining guard is substratePackagePatterns -- also emptied -- so a
	broad run is now unguarded. Restore from version history before running broadly."
	^ #()
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:46'
}
SWACoverage class >> excludedTestCategoryPatterns [
	"Emptied by request: no test CATEGORIES are excluded from whole-image runs.
	(Previously excluded Monticello/Metacello/Installer/Network/OSProcess/Morphic/
	etc. categories that load packages, open UI, or fork processes mid-run.)
	Restore from version history before running unattended."
	^ #()
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:46'
}
SWACoverage class >> excludedTestClassPatterns [
	"Emptied by request: no TestCase classes are excluded from whole-image runs.
	(Previously excluded UI/Window/Hand/Event/Process/Delay/Socket/File/etc. tests
	known to hang or block an unattended run.) Restore from version history before
	running unattended."
	^ #()
]

{
	#category : #import,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:19'
}
SWACoverage class >> fromCoverallsFile: aFilePath [
	"Build a SWACoverage from a smalltalkCI Coveralls JSON file on disk
	(e.g. '_builds/.../coveralls_results.json')."
	| contents |
	contents := (FileStream readOnlyFileNamed: aFilePath) contentsOfEntireFile.
	^ self fromCoverallsJson: contents
]

{
	#category : #import,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:18'
}
SWACoverage class >> fromCoverallsJson: aJsonString [
	"Build a SWACoverage from a smalltalkCI Coveralls JSON string (the contents of
	coveralls_results.json). Each source_file entry is one method whose 'coverage'
	array is uniformly 1 (covered), 0 (uncovered), or null (excluded). We map covered
	methods to 'Class>>selector' -> 1, matching the live boolean overlay. Returns a
	ready SWACoverage whose resultMap can be handed to a view via #showCoverage:."
	| json files cov |
	json := Json readFrom: aJsonString readStream.
	files := (json at: 'source_files' ifAbsent: [#()]).
	cov := self new log: false.
	cov importCoverallsSourceFiles: files.
	^ cov
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:32'
}
SWACoverage class >> generateAllTestsToFile: aFilePath [
	"STANDALONE heavy run -- call from a Workspace, the command line, or CI; NOT the
	Code Map UI. Instruments EVERY package and runs EVERY test (no exclusions) WITH
	provenance, and writes the reusable, image-independent SWACoverageData JSON to
	aFilePath AT THE END (even if stopped). If a test breaks or hangs, that's fine --
	we find out; use the Stop button or a CI timeout.

	Opens its own little Stop window (skipped if headless). Answers the file path.

	Example (Workspace):
		SWACoverage generateAllTestsToFile: '/tmp/squeak-coverage.json'."
	| cov panel data |
	cov := SWACoverage new
		exclusions: #();   "instrument everything"
		methodsForAll.
	panel := SWACoverageRunPanel new
		openInWindowTitled: 'Coverage run -> ', aFilePath;
		yourself.
	panel status: 'Instrumented ', cov methods size printString, ' methods; running ALL tests...'.
	data := cov runWithProvenance: self everyTestClass panel: panel.
	data writeToFile: aFilePath.
	panel status: 'Done. Wrote ', data coveredMethodCount printString, ' methods to ', aFilePath.
	Transcript cr; show: 'SWACoverage: wrote ', aFilePath; cr.
	^ aFilePath
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:30'
}
SWACoverage class >> generatePackages: pkgGlobs tests: testClasses toFile: aFilePath [
	"STANDALONE scoped run: instrument pkgGlobs, run testClasses WITH provenance,
	write the SWACoverageData JSON to aFilePath at the end. Opens its own Stop window.

	The heavy run is FORKED at background priority so the UI process stays live to
	deliver the Stop click and repaint the status line. This method returns
	immediately (the run and the file write happen in the background); the panel
	shows progress and, when finished, AUTO-CLOSES after a short delay.

	Headless (no World): runs synchronously inline and returns the path.

	Example:
		SWACoverage generatePackages: #('SqueakXR*')
			tests: (SWACoverage testClassesForPackages: #('SqueakXR*'))
			toFile: 'squeakxr-coverage.json'."
	| cov panel work |
	cov := SWACoverage new methodsForPackages: pkgGlobs.
	panel := SWACoverageRunPanel new
		openInWindowTitled: 'Coverage run -> ', aFilePath;
		yourself.
	work := [ | data |
		panel status: 'Instrumented ', cov methods size printString, ' methods; running ',
			testClasses size printString, ' test classes...'.
		data := cov runWithProvenance: testClasses asArray panel: panel.
		data writeToFile: aFilePath.
		SWACoverage log: 'SWACoverage: wrote ', aFilePath.
		panel finishAndClose: 'Done. Wrote ', data coveredMethodCount printString,
			' methods, ', data testNames size printString, ' tests -> ', aFilePath].
	"Headless: no World -> run inline. Otherwise fork below the UI so Stop works."
	(Smalltalk at: #World ifAbsent: [nil]) isNil
		ifTrue: [work value. ^ aFilePath].
	work forkAt: Processor userBackgroundPriority.
	^ aFilePath
]

{
	#category : #attribution,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:42'
}
SWACoverage class >> inMetaMode [
	"True while a wrapper is busy recording attribution. Wrappers consult this and
	skip their own attribution when set, so the bookkeeping code (which itself runs
	wrapped collection/kernel methods) cannot recursively re-enter attribution --
	the cause of the whole-image-run crash. This is the 'are we measuring vs.
	executing the test' guard."
	^ InMetaMode == true
]

{
	#category : #attribution,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:42'
}
SWACoverage class >> inMetaMode: aBoolean [
	InMetaMode := aBoolean
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:42'
}
SWACoverage class >> infrastructureClasses [
	"Classes that must NEVER be instrumented, regardless of package selection: the
	coverage machinery and the SUnit runner. Wrapping these lets attribution recurse
	through its own guard/bookkeeping. The meta-mode flag already prevents the worst
	recursion, but excluding these is cleaner and much faster (you can't meaningfully
	measure the measurer anyway). Always on, even with #exclusions: #()."
	^ { SWACoverage. SWACoverageData. SWACoverageWrapper. SWATallyWrapper.
		SWACoverageRunPanel.
		TestCase. TestSuite. TestResult. TestCoverage }
]

{
	#category : #import,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:18'
}
SWACoverage class >> keyFromCoverallsPath: aPath [
	"Recover a 'Class>>selector' key from a smalltalkCI Coveralls/Tonel source-file
	path, or nil if it is not a method file. Examples:
	  '.../MyClass.class/instance/foo.st'      -> 'MyClass>>foo'
	  '.../MyClass.class/class/bar.st'         -> 'MyClass class>>bar'
	  '.../MyClass.class/instance/at.put..st'  -> 'MyClass>>at:put:'
	(Selectors with colons are stored with the colons turned into dots; trailing
	'.st' leaves a trailing dot for keyword selectors.)"
	| parts fileName className side selector |
	parts := aPath findTokens: '/'.
	parts size < 3 ifTrue: [^ nil].
	fileName := parts last.
	(fileName endsWith: '.st') ifFalse: [^ nil].
	side := parts at: parts size - 1.   "'instance' or 'class'"
	className := (parts at: parts size - 2).   "'MyClass.class' / '.trait' / '.extension'"
	(className includesSubstring: '.') ifTrue: [
		className := className copyFrom: 1 to: (className indexOf: $.) - 1].
	(side = 'instance' or: [side = 'class']) ifFalse: [^ nil].
	"selector: strip '.st', turn dots back into colons. Leading '^' = special-char
	encoding (rare: binary selectors); skip those for now."
	selector := fileName copyFrom: 1 to: fileName size - 3.
	(selector beginsWith: '^') ifTrue: [^ nil].
	selector := selector copyReplaceAll: '.' with: ':'.
	^ side = 'class'
		ifTrue: [className, ' class>>', selector]
		ifFalse: [className, '>>', selector]
]

{
	#category : #logging,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:51'
}
SWACoverage class >> log: aString [
	"Write a progress line to the Transcript (visible in-image) AND to stdout
	(visible on the command line / CI). Both are wrapped so a missing channel never
	breaks a run. Used by the standalone generator for progress that shows up
	headless."
	[Transcript show: aString; cr] on: Error do: [:e | nil].
	[FileStream stdout nextPutAll: aString; nextPut: Character lf; flush]
		on: Error do: [:e | nil]
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:39'
}
SWACoverage class >> runProvenanceForPackages: pkgGlobs tests: testClasses then: aBlock [
	"Shared Stop-able provenance runner. Instruments pkgGlobs, runs testClasses WITH
	provenance under a forked SWACoverageRunPanel (so the UI stays live for Stop),
	and evaluates aBlock with the resulting SWACoverageData on the UI process when
	done. Used by both the standalone file generator and the Code Map's Cover+Tests
	button, so neither can ever wedge the image.

	Headless: runs inline and evaluates aBlock directly. Returns the panel (or nil)."
	| cov panel work |
	cov := SWACoverage new methodsForPackages: pkgGlobs.
	panel := SWACoverageRunPanel new
		openInWindowTitled: 'Coverage+tests run';
		yourself.
	work := [ | data |
		panel status: 'Instrumented ', cov methods size printString, ' methods; running ',
			testClasses size printString, ' test classes...'.
		data := cov runWithProvenance: testClasses asArray panel: panel.
		WorldState addDeferredUIMessage: [aBlock value: data].
		panel finishAndClose: 'Done. ', data coveredMethodCount printString,
			' methods, ', data testNames size printString, ' tests'].
	(Smalltalk at: #World ifAbsent: [nil]) isNil
		ifTrue: [work value. ^ nil].
	work forkAt: Processor userBackgroundPriority.
	^ panel
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:46'
}
SWACoverage class >> substratePackagePatterns [
	"DANGER: emptied by request. Normally this is the hard VM-safety guard listing
	packages that must NEVER be instrumented (Kernel/Collections/Compiler/
	Morphic-Kernel/...). With it empty, a coverage run CAN crash the VM, because
	wrapping the foundation detours every basic operation through the wrapper
	machinery. Restore the real list from version history before running broadly."
	^ #()
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:41'
}
SWACoverage class >> testClassesForPackages: pkgGlobs [
	"The concrete TestCase classes RELATED to the given package globs: those whose
	category EQUALS or STARTS WITH a matched package name, OR matches it as a glob.
	So 'JSON' picks up 'JSON-Tests'; 'SqueakXR*' picks up 'SqueakXR-Tests-Core' etc.
		SWACoverage generatePackages: #('SqueakXR*')
			tests: (SWACoverage testClassesForPackages: #('SqueakXR*'))
			toFile: 'squeakxr-coverage.json'."
	^ (TestCase allSubclasses select: [:tc | | cat |
		cat := tc category ifNil: [''].
		tc isAbstract not and: [tc testSelectors notEmpty and: [
			pkgGlobs anySatisfy: [:g |
				(g match: cat)
					or: [cat = g
					or: [cat beginsWith: g]
					or: [cat beginsWith: ((g endsWith: '*')
						ifTrue: [g allButLast] ifFalse: [g])]]]]]]) asArray
]

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
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:33'
}
SWACoverage >> exclusions: aGlobCollection [
	"Override the package-exclusion globs (default: class-side excludedPackagePatterns)."
	exclusions := aGlobCollection
]

{
	#category : #import,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:19'
}
SWACoverage >> importCoverallsSourceFiles: aCollection [
	"Populate resultMap from Coveralls source_file dictionaries. A file is COVERED
	if its 'coverage' array contains any value >= 1, UNCOVERED if it contains a 0
	but no hit, and EXCLUDED (skipped) if every entry is null. Keyed by the path."
	| covered |
	resultMap := Dictionary new.
	kind := #boolean.
	covered := 0.
	aCollection do: [:entry | | name arr key hit |
		name := entry at: 'name' ifAbsent: [nil].
		arr := entry at: 'coverage' ifAbsent: [#()].
		(name notNil and: [arr notEmpty]) ifTrue: [
			key := SWACoverage keyFromCoverallsPath: name.
			key ifNotNil: [
				hit := arr anySatisfy: [:v | v notNil and: [v >= 1]].
				hit ifTrue: [resultMap at: key put: 1. covered := covered + 1]]]].
	log ifTrue: [Transcript cr; show: 'SWACoverage: imported ', covered printString,
		' covered methods from ', aCollection size printString, ' source files'; cr].
	^ resultMap
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:47'
}
SWACoverage >> initialize [
	methods := OrderedCollection new.
	wrappers := OrderedCollection new.
	resultMap := Dictionary new.
	evictAt := 1000.
	maxTestsPerMethod := 10.
	exclusions := SWACoverage excludedPackagePatterns.
	log := true
]

{
	#category : #'boolean coverage',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:33'
}
SWACoverage >> installTestCoverage [
	"Install one-shot TestCoverage wrappers on every watched method, WITHOUT running
	anything. Pins the watched-methods array so wrappers and methods stay index-
	aligned even if running tests later recompiles methods. Logs install progress to
	the Transcript so a hang during instrumentation is locatable."
	watchedMethods := methods asArray.
	log ifTrue: [Transcript cr; show: '=== SWACoverage installing ',
		watchedMethods size printString, ' wrappers ==='; cr].
	wrappers := watchedMethods collect: [:m |
		TestCoverage new initializeOn: m methodReference].
	wrappers doWithIndex: [:c :i |
		c install.
		(log and: [i \\ 500 = 0]) ifTrue: [
			Transcript show: '  installed ', i printString, '/',
				watchedMethods size printString; cr]].
	log ifTrue: [Transcript show: '=== install complete ==='; cr].
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
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:33'
}
SWACoverage >> isExcluded: aPackageName [
	"True if aPackageName matches any exclusion glob."
	^ exclusions anySatisfy: [:g | g match: aPackageName]
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:54'
}
SWACoverage >> isSubstrate: aPackageName [
	"True if aPackageName is a foundation package that must never be instrumented
	under any setting (see SWACoverage class>>substratePackagePatterns)."
	^ SWACoverage substratePackagePatterns anySatisfy: [:g | g match: aPackageName]
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:33'
}
SWACoverage >> log: aBoolean [
	"Whether to print progress to the Transcript while selecting/instrumenting."
	log := aBoolean
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:47'
}
SWACoverage >> maxTestsPerMethod: anInteger [
	"Cap on covering test ids stored per method in provenance runs."
	maxTestsPerMethod := anInteger
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:54'
}
SWACoverage >> methodsForPackages: globCollection [
	"Watch every method of every package whose name matches one of globCollection
	(String>>match: globs), MINUS:
	 - the SUBSTRATE packages (Kernel/Collections/Compiler/...) -- a HARD guard that
	   applies even with #exclusions: #(), because wrapping the foundation collapses
	   the VM (the whole-image-crash lesson);
	 - the user exclusion list (#isExcluded:);
	 - TestCase methods and the coverage/test infrastructure (#mustNotInstrument:).
	Logs each package to the Transcript so a hang during selection is locatable."
	| infos |
	infos := (PackageInfo allPackages select: [:p |
		globCollection anySatisfy: [:g | g match: p packageName]])
			asSortedCollection: [:a :b | a packageName <= b packageName].
	methods := OrderedCollection new.
	log ifTrue: [Transcript cr; show: '=== SWACoverage selecting methods from ',
		infos size printString, ' candidate packages ==='; cr].
	infos do: [:p |
		(self isSubstrate: p packageName)
			ifTrue: [log ifTrue: [Transcript show: '  SKIP (substrate): ', p packageName; cr]]
			ifFalse: [
				(self isExcluded: p packageName)
					ifTrue: [log ifTrue: [Transcript show: '  SKIP (excluded): ', p packageName; cr]]
					ifFalse: [ | added |
						added := 0.
						p methods do: [:ref | | m |
							m := ref compiledMethod.
							(m notNil
								and: [(ref actualClass inheritsFrom: TestCase) not]
								and: [(self mustNotInstrument: m) not])
								ifTrue: [methods add: m. added := added + 1]].
						log ifTrue: [Transcript show: '  + ', p packageName, ' (', added printString, ' methods)'; cr]]]].
	log ifTrue: [Transcript show: '=== total watched: ', methods size printString, ' methods ==='; cr].
	^ self
]

{
	#category : #selecting,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:42'
}
SWACoverage >> mustNotInstrument: aCompiledMethod [
	"True if aCompiledMethod belongs to the coverage/test infrastructure (or a
	subclass of it) -- a hard correctness guard independent of the user exclusion
	list. Checks the instance side so metaclass methods are caught too."
	| cls |
	cls := aCompiledMethod methodClass instanceSide.
	^ SWACoverage infrastructureClasses anySatisfy: [:infra |
		cls == infra or: [cls inheritsFrom: infra]]
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
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 17:07'
}
SWACoverage >> runWithProvenance: testClasses [
	"Run each test method in testClasses INDIVIDUALLY, attributing every watched
	method it executes to that test, producing a SWACoverageData (the PathTools-
	style test<->method relation). No UI. See #runWithProvenance:panel: for the
	Stop-able variant."
	^ self runWithProvenance: testClasses panel: nil
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:26'
}
SWACoverage >> runWithProvenance: testClasses panel: aPanelOrNil [
	"Core provenance run. Runs each test method individually, attributing every
	watched method it executes to that test, into a SWACoverageData. Polls the panel
	for Stop before EACH test method (responsive cancel) and reports progress.
	Wrappers and the shared recording state are always cleaned up (ensure:). Answers
	the SWACoverageData (partial if stopped).

	Intended to run on a BACKGROUND process (see #generatePackages:tests:toFile:) so
	the UI process stays live to deliver the Stop click and repaint; hence it does
	NOT itself force a redraw."
	| cov wrappers total done stopped testName |
	cov := SWACoverageData new maxTestsPerMethod: maxTestsPerMethod.
	watchedMethods := methods asArray.
	wrappers := watchedMethods collect: [:m |
		SWACoverageWrapper new onClass: m methodClass selector: m selector data: cov].
	total := (testClasses inject: 0 into: [:sum :tc | sum + tc testSelectors size]) max: 1.
	done := 0.
	stopped := false.
	log ifTrue: [Transcript cr; show: '=== SWACoverage provenance: ',
		watchedMethods size printString, ' methods, ', total printString, ' tests ==='; cr].
	SWACoverageWrapper resetRecordingState.
	SWACoverageWrapper sink: cov.
	[wrappers do: [:w | w install].
	 testClasses do: [:tc |
		stopped ifFalse: [
			tc suite tests do: [:testCase |
				(stopped not and: [aPanelOrNil notNil and: [aPanelOrNil stopRequested]])
					ifTrue: [stopped := true].
				stopped ifFalse: [
					testName := tc name, '>>', testCase selector.
					SWACoverageWrapper currentTest: testName.
					[testCase run] on: Error, Halt do: [:e | e return: nil].
					SWACoverageWrapper currentTest: nil.
					done := done + 1.
					(aPanelOrNil notNil and: [done \\ 10 = 0]) ifTrue: [
						aPanelOrNil status: 'Running tests: ', done printString, '/', total printString,
							'  (', cov coveredMethodCount printString, ' methods covered)  -- ', tc name]]]]]]
		ensure: [
			SWACoverageWrapper resetRecordingState.
			wrappers do: [:w | w uninstall]].
	log ifTrue: [Transcript show: '=== provenance ',
		(stopped ifTrue: ['STOPPED'] ifFalse: ['complete']), ': ',
		cov coveredMethodCount printString, ' covered, ',
		cov testNames size printString, ' tests ==='; cr].
	^ cov
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
