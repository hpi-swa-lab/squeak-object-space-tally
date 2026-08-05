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
		'maxTestsPerMethod',
		'captureCallTree',
		'callTreeRoot',
		'timeMap',
		'selfTimeMap',
		'wallMicros',
		'traceRoot',
		'traceEvictedCount',
		'traceEventCount'
	],
	#classVars : [
		'CurrentTestName',
		'InMetaMode',
		'LogFileName'
	],
	#category : #'SWA-Coverage',
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
	#category : #bisecting,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:55'
}
SWACoverage class >> bisectWrapPackages: pkgGlobs toLog: aLogPath [
	"CHILD bisection entry. Wrap every method of pkgGlobs, LOGGING each method right
	before it is installed, then flush ONCE, log done, and quit. NO tests run -- this
	isolates the install/WRAP explosion specifically. If a particular method's
	installation blows up (memory/recursion/crash), the LAST 'WRAP' line in the log
	names it.

	The install loop runs GUARDED (InWrapper raised) so the loop's own sends are never
	instrumented. Per-method logging is itself guarded (#log: uses #guardedDo:).
	Quits without saving no matter what."
	self logFileName: aLogPath.
	Transcript ifNotNil: [[TranscriptStream redirectToStdOut: true] on: Error do: [:e | nil]].
	[[| cov ms |
	  SWAMethodWrapper resetGuard.
	  SWACoverage log: '=== BISECT: selecting ', pkgGlobs printString, ' ==='.
	  cov := SWACoverage new methodsForPackages: pkgGlobs.
	  ms := cov methods asArray.
	  SWACoverage log: '=== BISECT: wrapping ', ms size printString, ' methods one by one ==='.
	  SWAMethodWrapper guardedDo: [
		ms doWithIndex: [:m :i |
			SWACoverage log: 'WRAP ', i printString, '/', ms size printString, '  ',
				m methodClass name, '>>', m selector.
			(SWACoverageWrapper new onClass: m methodClass selector: m selector data: nil)
				installNoFlush].
		SWAMethodWrapper flushSystemCache].
	  SWACoverage log: '=== BISECT: all ', ms size printString, ' wrapped OK; uninstalling ==='.
	  "uninstall everything cleanly (still guarded)"
	  SWAMethodWrapper guardedDo: [
		ms do: [:m | | w |
			w := m methodClass methodDictionary at: m selector ifAbsent: [nil].
			(w isKindOf: SWAMethodWrapper) ifTrue: [w uninstallNoFlush]].
		SWAMethodWrapper flushSystemCache].
	  SWACoverage log: '=== BISECT: DONE clean ===']
		on: Error, Halt do: [:e |
			SWACoverage log: '=== BISECT: ERROR ', e class name, ': ', e messageText printString, ' ===']]
		ensure: [
			SWACoverage log: '=== BISECT: quitting ==='.
			Smalltalk snapshot: false andQuit: true]
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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 11:36'
}
SWACoverage class >> everyTestClass [
	"EVERY concrete TestCase in the image with tests, MINUS the do-not-EXECUTE
	exclusions (#excludedTestClassPatterns / #excludedTestCategoryPatterns). The
	Stop button and CI timeouts are the safety net for hangs; but a few suites
	(e.g. InstallerTest) actively DAMAGE the image -- their generated tests do a
	real network install + Monticello MERGE over your working copy -- so those are
	hard-excluded from execution here, not left to a timeout."
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
	#'squeak_changestamp' : 'MCPServer 7/21/2026 12:47'
}
SWACoverage class >> excludedTestClassPatterns [
	"TestCase class-NAME globs whose tests must NEVER be EXECUTED during a coverage
	run (distinct from instrumentation exclusions -- these classes may still be
	instrumented and measured when other tests exercise them; we just refuse to RUN
	their own tests). Applied by #testClassesForPackages: and #everyTestClass, and
	by #allRunnableTestClasses.

	InstallerTest: its tests are GENERATED (InstallerTestSuite>>ensureTestMethods)
	as 'test<pkg>  Installer new merge: #<pkg>' for every package-definition the
	Installer knows. Each one does a REAL network install + Monticello MERGE into
	the running image -- it pops the 'Merge FFI...' dialog and tries to overwrite
	your local working-copy changes. Never run it unattended (or in a working image).
	(InstallerUrlTest is harmless -- it only builds/asserts URL strings -- so it is
	NOT excluded.)

	DebuggerTests: its tests spawn INFINITE-LOOP processes ([...] repeat / whileTrue)
	at several priorities and rely on a user-interrupt + the Debugger to break them.
	Under instrumentation (every loop iteration dispatches through run:with:in:, and
	the interrupt/Debugger path is itself wrapped, with a non-interactive
	DummyUIManager) the interrupt never halts the loop -> the run HANGS. Measure it
	when other tests touch it; never RUN its own tests in an unattended coverage run.

	(Other UI/Window/Hand/Event/Process/Delay/Socket/File suites that hang or block
	an unattended run were previously listed here; restore from version history
	before a fully unattended whole-image run.)"
	^ #('InstallerTest' 'DebuggerTests')
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
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:51'
}
SWACoverage class >> generateInstrumenting: instrumentGlobs testSpecs: testSpecs toFile: aFilePath forked: aBoolean [
	"PARENT entry point: instrument by package GLOBS, run an EXPLICIT set of tests
	given as SPECS ('Class>>selector' or 'Class'). For pinpoint coverage runs.

	forked: true  -> fresh throwaway headless image from disk (this image untouched),
	                 live tailer if there is a World.
	forked: false -> in-image: instrument, run the spec cases, write the JSON inline.

	Requires the CURRENT image to have been SAVED with this code (the child loads the
	same .image from disk).

	Example -- instrument the WHOLE system, run ONE test method:
		SWACoverage
			generateInstrumenting: #('*')
			testSpecs: #('DirectoryChooserDialogTest>>testTypeAndChooseDirectory')
			toFile: 'dirchooser-coverage.json'
			forked: true."
	| scriptPath cmd imageName logPath outPath proc |
	aBoolean ifFalse: [
		| cov |
		cov := SWACoverage new methodsForPackages: instrumentGlobs.
		^ (cov runWithProvenanceTestCases: (self testCasesFromSpecs: testSpecs) panel: nil)
			writeToFile: aFilePath; yourself].
	imageName := SmalltalkImage current imageName.
	scriptPath := aFilePath, '.run.st'.
	logPath := self logFileNameForOutput: aFilePath.
	outPath := aFilePath, '.out'.
	(FileStream forceNewFileNamed: scriptPath)
		nextPutAll: 'SWACoverage runForkedCoverageInstrumenting: ';
		nextPutAll: instrumentGlobs printString;
		nextPutAll: ' testSpecs: ';
		nextPutAll: testSpecs printString;
		nextPutAll: ' toFile: ';
		nextPutAll: aFilePath printString;
		nextPutAll: '.';
		close.
	(FileDirectory default fileExists: aFilePath)
		ifTrue: [FileDirectory default deleteFileNamed: aFilePath].
	(FileDirectory default fileExists: logPath)
		ifTrue: [FileDirectory default deleteFileNamed: logPath].
	(FileDirectory default fileExists: outPath)
		ifTrue: [FileDirectory default deleteFileNamed: outPath].
	cmd := '"', self vmExecutablePath, '" -nodisplay "', imageName, '" "', scriptPath,
		'" > "', outPath, '" 2>&1'.
	SWACoverage log: '=== FORK PARENT: launching child -> ', cmd, ' ==='.
	proc := OSProcess command: cmd.
	(Smalltalk at: #World ifAbsent: [nil])
		ifNil: [^ aFilePath].
	^ (SWACoverageLogTailer openOn: logPath output: aFilePath stderr: outPath)
		childProcess: proc scriptPath: scriptPath;
		yourself
]

{
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:44'
}
SWACoverage class >> generateInstrumenting: instrumentGlobs tests: testGlobs toFile: aFilePath forked: aBoolean [
	"PARENT entry point with the two axes SEPARATED (see
	#runForkedCoverageInstrumenting:tests:toFile:):
	  - instrumentGlobs: package globs to WRAP and MEASURE;
	  - testGlobs: package globs whose TestCase classes to RUN.

	forked: true  -> spawn a fresh throwaway headless image from disk (THIS image is
	                 never touched), open a live tailer if there is a World.
	forked: false -> run in-image via #generatePackages:tests:toFile: (scoped/safe).

	Requires the CURRENT image to have been SAVED with this code (the child loads the
	same .image from disk).

	Example -- run only Morphic tests, but measure coverage of the WHOLE system:
		SWACoverage generateInstrumenting: #('*') tests: #('Morphic*')
			toFile: 'morphic-tests-wholesystem-coverage.json' forked: true."
	| scriptPath cmd imageName logPath outPath proc |
	aBoolean ifFalse: [
		^ self generatePackages: instrumentGlobs
			tests: (self testClassesForPackages: testGlobs)
			toFile: aFilePath].
	imageName := SmalltalkImage current imageName.
	scriptPath := aFilePath, '.run.st'.
	logPath := self logFileNameForOutput: aFilePath.
	outPath := aFilePath, '.out'.
	(FileStream forceNewFileNamed: scriptPath)
		nextPutAll: 'SWACoverage runForkedCoverageInstrumenting: ';
		nextPutAll: instrumentGlobs printString;
		nextPutAll: ' tests: ';
		nextPutAll: testGlobs printString;
		nextPutAll: ' toFile: ';
		nextPutAll: aFilePath printString;
		nextPutAll: '.';
		close.
	(FileDirectory default fileExists: aFilePath)
		ifTrue: [FileDirectory default deleteFileNamed: aFilePath].
	(FileDirectory default fileExists: logPath)
		ifTrue: [FileDirectory default deleteFileNamed: logPath].
	(FileDirectory default fileExists: outPath)
		ifTrue: [FileDirectory default deleteFileNamed: outPath].
	cmd := '"', self vmExecutablePath, '" -nodisplay "', imageName, '" "', scriptPath,
		'" > "', outPath, '" 2>&1'.
	SWACoverage log: '=== FORK PARENT: launching child -> ', cmd, ' ==='.
	proc := OSProcess command: cmd.
	(Smalltalk at: #World ifAbsent: [nil])
		ifNil: [^ aFilePath].
	^ (SWACoverageLogTailer openOn: logPath output: aFilePath stderr: outPath)
		childProcess: proc scriptPath: scriptPath;
		yourself
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:09'
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
	SWACoverage log: '=== STAGE: generate START -> ', aFilePath, ' ==='.
	cov := SWACoverage new methodsForPackages: pkgGlobs.
	panel := SWACoverageRunPanel new
		openInWindowTitled: 'Coverage run -> ', aFilePath;
		yourself.
	work := [ | data |
		panel status: 'Instrumented ', cov methods size printString, ' methods; running ',
			testClasses size printString, ' test classes...'.
		data := cov runWithProvenance: testClasses asArray panel: panel.
		SWACoverage log: '=== STAGE: writing file ', aFilePath, ' ==='.
		data writeToFile: aFilePath.
		SWACoverage log: '=== STAGE: generate DONE -- wrote ', data coveredMethodCount printString,
			' methods, ', data testNames size printString, ' tests -> ', aFilePath, ' ==='.
		panel finishAndClose: 'Done. Wrote ', data coveredMethodCount printString,
			' methods, ', data testNames size printString, ' tests -> ', aFilePath].
	"Headless: no World -> run inline. Otherwise fork below the UI so Stop works."
	(Smalltalk at: #World ifAbsent: [nil]) isNil
		ifTrue: [work value. ^ aFilePath].
	work forkAt: Processor userBackgroundPriority.
	^ aFilePath
]

{
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:44'
}
SWACoverage class >> generatePackages: pkgGlobs toFile: aFilePath forked: aBoolean [
	"PARENT entry point (single-glob form): instrument AND run the same glob set.
	Delegates to #generateInstrumenting:tests:toFile:forked: with
	instrumentGlobs = testGlobs = pkgGlobs.

	To instrument and test DIFFERENT scopes -- e.g. run only the Morphic tests but
	measure coverage across the WHOLE system -- use the two-axis entry point:
		SWACoverage generateInstrumenting: #('*') tests: #('Morphic*')
			toFile: 'morphic-coverage.json' forked: true.

	Requires the CURRENT image to have been SAVED with this code, since the child
	loads the same image file from disk.

	Example (whole image, both axes = '*'):
		SWACoverage generatePackages: #('*')
			toFile: 'squeak-coverage.json' forked: true."
	^ self generateInstrumenting: pkgGlobs tests: pkgGlobs toFile: aFilePath forked: aBoolean
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
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:18'
}
SWACoverage class >> infrastructureClasses [
	"Classes that must NEVER be instrumented, regardless of package selection: the
	instrumentation machinery and the SUnit runner. Wrapping these makes dispatch
	recurse through its own machinery -- fatal.

	CRITICAL: SWAMethodWrapper is the SHARED SUPERCLASS where the dispatch entry
	#run:with:in:, #install, #forward:with:in:, #methodName and the guard now live.
	It MUST be here: wrapping SWAMethodWrapper>>run:with:in: makes every subsequent
	wrapper dispatch call a wrapped #run:with:in: -> infinite recursion -> OOM (found
	by bisection, 2026-06-26). Listing it covers ALL wrapper subclasses because
	#mustNotInstrument: also matches #inheritsFrom:. (The old list named the two
	subclasses but not the new superclass, which is why '*' still blew up after the
	refactor.)

	CRITICAL: SWACapturingLayer is the process-specific reentrancy guard that
	#run:with:in: consults on EVERY dispatch (#isActive / #suppressionDepth /
	#withoutCapturing:). Wrapping it makes reading the guard call a wrapped method,
	which reads the guard again -> infinite recursion -> HANG (the '*' tally hang
	after the COP-guard refactor). It MUST be here too.

	CRITICAL: SWASamplingTallyNode is the call-tree NODE the capture hooks build into
	while wrapped methods are running -- SWATallyWrapper>>captureIn: walks it and
	SWATimingWrapper>>run:with:in: sends #childNamed: / #addSelfTime: to it on EVERY
	wrapped call. Wrapping it makes recording a call call a wrapped method, which
	records a call -> infinite recursion. The counting tally used to get away with it
	only because #captureIn: runs inside #withoutCapturing:; the timing wrapper works
	on the raw path (that is what makes it affordable), so the exclusion has to be
	structural. Same rationale as SWACoverageData: it is the tool's own data
	structure, not something you can meaningfully profile from inside itself.

	Always on, even with #exclusions: #()."
	^ { SWAMethodWrapper. SWACapturingLayer. SWACoverage. SWACoverageData.
		SWACoverageWrapper. SWATallyWrapper. SWACoverageRunPanel.
		SWASamplingTallyNode.
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
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:33'
}
SWACoverage class >> log: aString [
	"Append one progress line to the log file (#logFileName). tail -f to watch a run.
	Crash-safe: opens, appends at end, flushes, CLOSES per line.

	Runs inside the BASE REENTRANCY GUARD (#guardedDo:) so the FileStream/Collections
	sends it makes fall straight through their wrappers instead of re-entering them.
	(This is plumbing -- the reentrancy guard -- NOT the coverage recording flag.)
	Any file error is swallowed -- logging must never break a run."
	SWAMethodWrapper guardedDo: [
		[| f |
		 f := FileStream fileNamed: SWACoverage logFileName.
		 [f setToEnd; nextPutAll: aString; nextPut: Character lf; flush]
			ensure: [f close]]
			on: Error do: [:e | nil]]
]

{
	#category : #logging,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:57'
}
SWACoverage class >> logFileName [
	"Path of the coverage progress log. Stage/package/test-class lines are appended
	here (see #log:). tail -f this file to watch a run; it survives a hard VM crash
	because #log: opens/appends/flushes/closes per line.

	Defaults to 'squeak-coverage.log' but can be redirected per run via #logFileName:
	-- the forked child sets it to a per-run file derived from the output path (e.g.
	morphic-coverage.json -> morphic-coverage.log)."
	^ LogFileName ifNil: [LogFileName := 'squeak-coverage.log']
]

{
	#category : #logging,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:57'
}
SWACoverage class >> logFileName: aStringOrNil [
	"Redirect the progress log. nil restores the default ('squeak-coverage.log' via
	#logFileName)."
	LogFileName := aStringOrNil
]

{
	#category : #logging,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:58'
}
SWACoverage class >> logFileNameForOutput: aFilePath [
	"Derive a per-run log file name from a coverage output path by replacing the
	extension with '.log': 'morphic-coverage.json' -> 'morphic-coverage.log'. If the
	path has no '.', append '.log'."
	| dotIndex |
	dotIndex := aFilePath lastIndexOf: $..
	^ dotIndex = 0
		ifTrue: [aFilePath, '.log']
		ifFalse: [(aFilePath copyFrom: 1 to: dotIndex - 1), '.log']
]

{
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:44'
}
SWACoverage class >> runForkedCoverageForPackages: pkgGlobs toFile: aFilePath [
	"CHILD entry point (single-glob form): instrument AND run the same glob set.
	Kept for backward compatibility; delegates to the two-axis form with
	instrumentGlobs = testGlobs = pkgGlobs. To instrument and test DIFFERENT scopes
	(e.g. run only Morphic tests but measure the whole system), use
	#runForkedCoverageInstrumenting:tests:toFile: directly (or the parent entry
	#generateInstrumenting:tests:toFile:forked:)."
	^ self runForkedCoverageInstrumenting: pkgGlobs tests: pkgGlobs toFile: aFilePath
]

{
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:51'
}
SWACoverage class >> runForkedCoverageInstrumenting: instrumentGlobs testSpecs: testSpecs toFile: aFilePath [
	"CHILD entry point: instrument by package GLOBS, but run an EXPLICIT, hand-picked
	set of tests given as SPECS (strings 'Class>>selector' or 'Class' for all its
	methods; see #testCasesFromSpecs:). For pinpoint runs -- e.g. instrument the whole
	system but run only DirectoryChooserDialogTest>>testTypeAndChooseDirectory.

	Fresh throwaway headless image; quits without saving. See
	#runForkedCoverageInstrumenting:tests:toFile: for the glob-based test selection."
	| cases cov data |
	self logFileName: (self logFileNameForOutput: aFilePath).
	[TranscriptStream redirectToStdOut: true] on: Error do: [:e | nil].
	[[SWACoverage log: '=== FORKED CHILD: START instrument=', instrumentGlobs printString,
		' testSpecs=', testSpecs printString, ' -> ', aFilePath, ' ==='.
	  cases := self testCasesFromSpecs: testSpecs.
	  SWACoverage log: '=== FORKED CHILD: ', cases size printString, ' explicit test cases ==='.
	  cov := SWACoverage new methodsForPackages: instrumentGlobs.
	  data := cov runWithProvenanceTestCases: cases panel: nil.
	  SWACoverage log: '=== FORKED CHILD: writing ', aFilePath, ' ==='.
	  data writeToFile: aFilePath.
	  SWACoverage log: '=== FORKED CHILD: DONE -- ', data coveredMethodCount printString,
		' methods, ', data testNames size printString, ' tests -> ', aFilePath, ' ===']
		on: Error, Halt do: [:e |
			SWACoverage log: '=== FORKED CHILD: ERROR ', e class name, ': ', e messageText printString, ' ===']]
		ensure: [
			SWACoverage log: '=== FORKED CHILD: quitting (no save) ==='.
			Smalltalk snapshot: false andQuit: true]
]

{
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:44'
}
SWACoverage class >> runForkedCoverageInstrumenting: instrumentGlobs tests: testGlobs toFile: aFilePath [
	"CHILD entry point with the two axes SEPARATED:
	  - instrumentGlobs: which package methods to WRAP and MEASURE coverage of;
	  - testGlobs: which TestCase classes to RUN.
	So you can run a small, well-behaved test set (e.g. #('Morphic*')) while still
	measuring coverage across the WHOLE system (instrument #('*')) -- or vice versa.

	Runs in a FRESH, throwaway headless image launched from disk; quits WITHOUT
	saving so the parent image is never touched. Wrapped so ANY error still reaches
	the quit. See #runForkedCoverageForPackages:toFile: (the single-glob form, which
	now delegates here with instrumentGlobs = testGlobs)."
	| testClasses cov data |
	self logFileName: (self logFileNameForOutput: aFilePath).
	[TranscriptStream redirectToStdOut: true] on: Error do: [:e | nil].
	[[SWACoverage log: '=== FORKED CHILD: START instrument=', instrumentGlobs printString,
		' tests=', testGlobs printString, ' -> ', aFilePath, ' ==='.
	  testClasses := self testClassesForPackages: testGlobs.
	  SWACoverage log: '=== FORKED CHILD: ', testClasses size printString, ' test classes ==='.
	  cov := SWACoverage new methodsForPackages: instrumentGlobs.
	  data := cov runWithProvenance: testClasses asArray panel: nil.
	  SWACoverage log: '=== FORKED CHILD: writing ', aFilePath, ' ==='.
	  data writeToFile: aFilePath.
	  SWACoverage log: '=== FORKED CHILD: DONE -- ', data coveredMethodCount printString,
		' methods, ', data testNames size printString, ' tests -> ', aFilePath, ' ===']
		on: Error, Halt do: [:e |
			SWACoverage log: '=== FORKED CHILD: ERROR ', e class name, ': ', e messageText printString, ' ===']]
		ensure: [
			SWACoverage log: '=== FORKED CHILD: quitting (no save) ==='.
			Smalltalk snapshot: false andQuit: true]
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
	#category : #bisecting,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:55'
}
SWACoverage class >> spawnBisectForPackages: pkgGlobs tag: aTag [
	"PARENT: launch a fresh headless child that wraps pkgGlobs method-by-method (no
	tests), logging each method, to find which one explodes. aTag names the run's
	files: bisect-<tag>.log (per-method WRAP lines) and bisect-<tag>.out (stdout/crash
	dump). Returns the log path. Watch with: tail -f bisect-<tag>.log -- the last WRAP
	line names the culprit if it dies."
	| scriptPath logPath outPath cmd |
	scriptPath := 'bisect-', aTag, '.run.st'.
	logPath := 'bisect-', aTag, '.log'.
	outPath := 'bisect-', aTag, '.out'.
	(FileStream forceNewFileNamed: scriptPath)
		nextPutAll: 'SWACoverage bisectWrapPackages: ', pkgGlobs printString,
			' toLog: ', logPath printString, '.';
		close.
	(FileDirectory default fileExists: logPath) ifTrue: [FileDirectory default deleteFileNamed: logPath].
	(FileDirectory default fileExists: outPath) ifTrue: [FileDirectory default deleteFileNamed: outPath].
	cmd := '"', self vmExecutablePath, '" -nodisplay "', SmalltalkImage current imageName,
		'" "', scriptPath, '" > "', outPath, '" 2>&1'.
	OSProcess command: cmd.
	^ logPath
]

{
	#category : #tracing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:16'
}
SWACoverage class >> stepProbeMethods [
	"The method a trace hangs its step MEASUREMENT off: the Morphic cycle, and nothing
	else. Wrapped with SWAStepTraceWrapper on every trace run, whether or not Morphic is
	in the package set, and never evicted.

	It is a MEASUREMENT POINT, not extra content. Its span is recorded exactly like any
	other traced call, in the process's own lane, because if Morphic is captured it
	would have been recorded there anyway -- an earlier version gave the steps a lane of
	their own and wrapped #runStepMethods and #displayWorldSafely: too, which duplicated
	rows the call graph already had. What the wrapper adds is the per-cycle memory sample
	and the GC-counter drain, and those need exactly one place to happen: the end of the
	cycle.

	Guarded by #includesSelector: so a refactored or absent Morphic drops the probe
	instead of breaking every trace."
	^ (WorldState includesSelector: #doOneCycleNowFor:)
		ifTrue: [Array with: WorldState >> #doOneCycleNowFor:]
		ifFalse: [#()]
]

{
	#category : #exclusions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:26'
}
SWACoverage class >> substratePackagePatterns [
	"Packages that MUST NEVER be instrumented under ANY setting (not even
	#exclusions: #()). These are the foundation the wrap-and-replace machinery -- and
	the entire running system -- depend on: wrapping them detours every basic
	operation (at:, do:, +, =, hash...) through doesNotUnderstand:/executeMethod:,
	which collapses the VM under overhead before a single test even runs. This is the
	hard lesson from the whole-image crashes: you measure coverage of code UNDER
	test, never the substrate it runs on. Standard coverage tools do the same.

	A run that hits these simply does not cover them (they show as 'not covered'),
	which is correct."
	^ #(
		'Kernel*' 'Collections*' 'Compiler*' 'ShoutCore*'
		'System-Support' 'System-Object*' 'System-Finalization'
		'Graphics-Primitives' 'Graphics-Display Objects'
		'Files*' 'FS-*' 'FileSystem*'
		'Multilingual*' 'Network-Kernel'
		'Morphic-Kernel' 'Morphic-Support'
		'Traits*' 'Environments*' )
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 7/28/2026 18:02'
}
SWACoverage class >> tallyPackages: packageNames while: aBlock [
	"SYNCHRONOUS call tally: instrument every method of packageNames, evaluate
	aBlock, and collect the counts the moment the block RETURNS -- no STOP window,
	no exercising by hand. Answers the collected SWACoverage (its #resultMap maps
	'Class>>selector' -> count, #collectCallTree gives the captured tree).

	The wrappers are uninstalled in an ensure: -- an error or non-local exit inside
	aBlock leaves NOTHING instrumented -- and a layer-aware stray sweep runs before
	installing and after collecting (see SWAPane>>startInvocationTally:). The same
	ensure: drops the shared call-tree capture state, which #collectTally has just
	moved into cov: CallTreeWatched otherwise keeps every instrumented
	CompiledMethod alive until the next tally. The answered cov still carries the
	tree (#collectCallTree is a plain accessor).

	Caveat: the block runs INSIDE the instrumented world, so the calls made by the
	caller itself (menu, compiler, UI) are counted too if they live in packageNames."
	| cov |
	SWAMethodWrapper uninstallAllStrayWrappers.
	cov := self new
		evictAt: 1000;
		captureCallTree: true;
		methodsForPackages: packageNames.
	cov instrumentTally.
	[aBlock value] ensure: [
		[cov collectTally.
		 cov uninstall] ensure: [
			SWAMethodWrapper uninstallAllStrayWrappers.
			SWATallyWrapper resetCallTree]].
	^ cov
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:49'
}
SWACoverage class >> testCasesFromSpecs: specCollection [
	"Turn an explicit collection of test SPECS into concrete TestCase instances to RUN.
	A spec is a String, either:
	  'ClassName>>selector'  -> exactly that one test method, or
	  'ClassName'            -> every test method of that class.
	Unknown classes / selectors are skipped (logged). Honors #excludedTestClassPatterns
	so a hand-picked spec can't accidentally run a do-not-execute class.

	This is the EXPLICIT counterpart to #testClassesForPackages: -- use it when you
	want to run a few specific tests (e.g. while debugging one method) but still
	instrument a broad scope. Example:
		SWACoverage testCasesFromSpecs:
			#('DirectoryChooserDialogTest>>testTypeAndChooseDirectory')."
	| cases nameExcl |
	cases := OrderedCollection new.
	nameExcl := self excludedTestClassPatterns.
	specCollection do: [:spec | | parts clsName selName cls |
		parts := spec subStrings: '>'.
		clsName := (parts first) withBlanksTrimmed.
		selName := parts size > 1 ifTrue: [(parts last) withBlanksTrimmed] ifFalse: [nil].
		cls := Smalltalk at: clsName asSymbol ifAbsent: [nil].
		(cls isNil or: [(cls inheritsFrom: TestCase) not])
			ifTrue: [SWACoverage log: '  SKIP spec (no such TestCase): ', spec]
			ifFalse: [
				(nameExcl anySatisfy: [:g | g match: cls name])
					ifTrue: [SWACoverage log: '  SKIP spec (excluded class): ', spec]
					ifFalse: [
						selName isNil
							ifTrue: [cls testSelectors do: [:s | cases add: (cls selector: s)]]
							ifFalse: [
								(cls canUnderstand: selName asSymbol)
									ifTrue: [cases add: (cls selector: selName asSymbol)]
									ifFalse: [SWACoverage log: '  SKIP spec (no such test method): ', spec]]]]].
	^ cases asArray
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:38'
}
SWACoverage class >> testClassesForPackages: pkgGlobs [
	"The concrete TestCase classes RELATED to the given package globs: those whose
	category EQUALS or STARTS WITH a matched package name, OR matches it as a glob.
	So 'JSON' picks up 'JSON-Tests'; 'SqueakXR*' picks up 'SqueakXR-Tests-Core' etc.
		SWACoverage generatePackages: #('SqueakXR*')
			tests: (SWACoverage testClassesForPackages: #('SqueakXR*'))
			toFile: 'squeakxr-coverage.json'.

	Honors the do-not-EXECUTE exclusions (#excludedTestClassPatterns /
	#excludedTestCategoryPatterns) -- e.g. InstallerTest, whose generated tests do a
	real network install+merge into the image -- so they are never RUN even when a
	package glob (or '*') would otherwise select them."
	| nameExcl catExcl |
	nameExcl := self excludedTestClassPatterns.
	catExcl := self excludedTestCategoryPatterns.
	^ (TestCase allSubclasses select: [:tc |
		| cat keep |
		cat := tc category ifNil: [''].
		keep := tc isAbstract not and: [tc testSelectors notEmpty].
		keep := keep and: [(nameExcl anySatisfy: [:g | g match: tc name]) not].
		keep := keep and: [(catExcl anySatisfy: [:g | g match: cat]) not].
		keep and: [pkgGlobs anySatisfy: [:g |
			| stem |
			stem := (g endsWith: '*') ifTrue: [g allButLast] ifFalse: [g].
			(g match: cat) or: [cat = g] or: [cat beginsWith: g] or: [cat beginsWith: stem]]]]) asArray
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
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:19'
}
SWACoverage class >> timePackages: packageNames while: aBlock [
	"SYNCHRONOUS call TIMING: the stopwatch twin of #tallyPackages:while:. Instrument
	every method of packageNames with SWATimingWrapper, evaluate aBlock, and collect
	the moment it RETURNS. Answers the collected SWACoverage, whose #resultMap holds
	call counts, #timeMap inclusive microseconds, #selfTimeMap exclusive microseconds,
	#wallMicros the elapsed time of the block, and #collectCallTree a flamegraph
	weighted in microseconds rather than calls.

	Same safety contract as the counting twin: the wrappers come off in an ensure: --
	an error or non-local exit inside aBlock leaves NOTHING instrumented -- with a
	layer-aware stray sweep before installing and after collecting, and the shared
	call-tree capture state is dropped (it strongly holds every instrumented
	CompiledMethod).

	Caveat, also inherited: the block runs INSIDE the instrumented world, so calls
	made by the caller itself are timed too if they live in packageNames."
	| cov |
	SWAMethodWrapper uninstallAllStrayWrappers.
	cov := self new
		captureCallTree: true;
		methodsForPackages: packageNames.
	cov instrumentTiming.
	[aBlock value] ensure: [
		[cov collectTiming.
		 cov uninstall] ensure: [
			SWAMethodWrapper uninstallAllStrayWrappers.
			SWATallyWrapper resetCallTree]].
	^ cov
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:06'
}
SWACoverage class >> tracePackages: packageNames while: aBlock [
	"SYNCHRONOUS call TRACING: the event-log twin of #timePackages:while:. Instrument
	every method of packageNames with SWATraceWrapper, evaluate aBlock, and collect
	the moment it returns. Answers the collected SWACoverage, which holds everything a
	timing run holds PLUS #collectTraceRoot -- the individual calls, in order, with
	their own start and end times, one lane per process.

	Same safety contract as the timing twin, with one addition: SWATraceWrapper
	resetTrace joins the ensure:. The lanes strongly hold every wrapper they recorded,
	so a busy run leaves megabytes behind if the reset is skipped -- and the reset
	must be in the ensure:, not after, because an error in aBlock must not leak them
	either.

	Grab the tree BEFORE the ensure: has run? No: #collectTrace moves it into the
	SWACoverage, so it survives the reset. That indirection is the whole reason
	#collectTraceRoot is an accessor and not a builder.

	Caveat, inherited: the block runs INSIDE the instrumented world, so the caller's
	own calls into packageNames are traced too -- they appear in the caller's lane."
	| cov |
	SWAMethodWrapper uninstallAllStrayWrappers.
	cov := self new
		captureCallTree: true;
		methodsForPackages: packageNames.
	cov instrumentTrace.
	[aBlock value] ensure: [
		[cov collectTrace.
		 cov uninstall] ensure: [
			SWAMethodWrapper uninstallAllStrayWrappers.
			SWATallyWrapper resetCallTree.
			SWATraceWrapper resetTrace]].
	^ cov
]

{
	#category : #'forked child',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:50'
}
SWACoverage class >> vmExecutablePath [
	"Absolute path of the squeak VM executable that is running THIS image, for
	launching a forked child image. vmPath answers the bin directory; the executable
	is 'squeak' inside it."
	^ (Smalltalk vmPath, 'squeak')
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:26'
}
SWACoverage >> captureCallTree [
	"Whether this tally run is building a flamegraph call tree (default false)."
	^ captureCallTree ifNil: [false]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:26'
}
SWACoverage >> captureCallTree: aBoolean [
	"Opt into building a flamegraph-style call tree during a TALLY run (see
	SWATallyWrapper class>>beginCallTreeFor:). Off by default -- the plain counting
	tally has no per-call stack-walk overhead; turning this on captures the nested
	call structure so the result can be shown as a flamegraph."
	captureCallTree := aBoolean
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:50'
}
SWACoverage >> casesForTestClasses: testClasses [
	"Expand whole TestCase CLASSES into a flat collection of one-selector TestCase
	instances (via #suite, so each class's own suite-building rules apply), logging a
	header per class. Used by #runWithProvenance:panel:."
	| cases |
	cases := OrderedCollection new.
	testClasses do: [:tc |
		SWACoverage log: '  TEST CLASS: ', tc name, ' (', tc testSelectors size printString, ' tests)'.
		tc suite tests do: [:testCase | cases add: testCase]].
	^ cases asArray
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 7/28/2026 18:01'
}
SWACoverage >> collectCallTree [
	"Answer the finished flamegraph call tree (a SWASamplingTallyNode rooted at 'root',
	weighted by invocation counts) captured during this tally run, or nil if capture
	was off / nothing was recorded. Roll-up is done by SWATallyWrapper.

	A pure ACCESSOR, and therefore idempotent and safe to send long after the run:
	the tree was moved out of SWATallyWrapper class variables into this instance by
	#collectTally, so the shared CallTreeRoot / CallTreeWatched can be dropped in the
	collecting ensure: without taking the tree with them. Answers nil if the run was
	never collected."
	self captureCallTree ifFalse: [^ nil].
	^ callTreeRoot
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 7/28/2026 18:01'
}
SWACoverage >> collectTally [
	"Read the current invocation counts from the live tally wrappers into resultMap
	('Class>>selector' -> count). Only methods called at least once are recorded.
	Does not uninstall -- call #uninstall when done.

	Also TAKES OWNERSHIP of the captured call tree: SWATallyWrapper's CallTreeRoot /
	CallTreeWatched are transient scratch for the LIVE capture only, so the finished,
	rolled-up tree is moved into this instance here, at collection time. From this
	moment the class variables are dead weight and the caller's ensure: is free to
	send #resetCallTree -- which it MUST, because CallTreeWatched strongly holds EVERY
	instrumented CompiledMethod (~70k for a whole-image run, pinning their classes and
	keeping recompiled-away methods alive). #collectCallTree then answers the ivar."
	kind := #tally.
	resultMap := Dictionary new.
	wrappers do: [:w | w count > 0 ifTrue: [
		resultMap at: w crossRefKey put: w count]].
	self captureCallTree ifTrue: [callTreeRoot := SWATallyWrapper finishCallTree].
	^ resultMap
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:19'
}
SWACoverage >> collectTiming [
	"Read the live timing wrappers into THREE maps, all keyed 'Class>>selector':
	resultMap (call count, so a timing run is a superset of a call tally), timeMap
	(inclusive microseconds) and selfTimeMap (exclusive microseconds). Only methods
	called at least once are recorded. Does not uninstall -- send #uninstall after.

	Also freezes #wallMicros into the elapsed wall time of the whole exercise (the
	performance.now() delta around the run), and takes ownership of the captured call
	tree exactly as #collectTally does -- from here on SWATallyWrapper's class
	variables are dead weight and the caller's ensure: must send #resetCallTree,
	which strongly holds every instrumented CompiledMethod.

	Note the two totals do NOT add up to the wall time and are not meant to: the
	tree's self times sum to the instrumented part of the run only. Everything spent
	in substrate, in packages outside the scope, or waiting is simply not attributed
	to any method here."
	kind := #timing.
	wallMicros := wallMicros
		ifNil: [0]
		ifNotNil: [:startMicros | Time utcMicrosecondClock - startMicros].
	resultMap := Dictionary new.
	timeMap := Dictionary new.
	selfTimeMap := Dictionary new.
	wrappers do: [:w | w count > 0 ifTrue: [ | key |
		key := w crossRefKey.
		resultMap at: key put: w count.
		timeMap at: key put: w totalMicros.
		selfTimeMap at: key put: w selfMicros]].
	self captureCallTree ifTrue: [callTreeRoot := SWATallyWrapper finishCallTree].
	SWATimingWrapper resetFrames.
	^ resultMap
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:08'
}
SWACoverage >> collectTrace [
	"Harvest a TRACE run: everything #collectTiming produces (counts, inclusive and
	self microseconds, wall time, call tree) PLUS the reconstructed span tree.

	DISARM FIRST. Uninstalling tens of thousands of wrappers is itself tens of
	thousands of sends, and every one of them would otherwise be appended to the log
	-- the tool measuring its own teardown. Disarming only stops appending; the lanes
	stay readable.

	Does not uninstall and does not free the lanes. The caller must send #uninstall
	and, in an ensure:, SWATraceWrapper resetTrace -- the buffers strongly hold every
	wrapper they recorded, so a full-capacity run is megabytes that would otherwise
	survive until the next one."
	| lanes |
	SWATraceWrapper disarmTrace.
	self collectTiming.
	lanes := SWATraceWrapper traceLanes.
	traceEventCount := lanes
		inject: 0
		into: [:s :lane | s + (SWATraceWrapper laneEventCount: lane)].
	"Not 'truncated' any more -- the log is unbounded. What is incomplete is the set of
	METHODS still being recorded at the end, so count the ones that evicted. Their
	counts and times are lower bounds and their calls stop appearing in the tree."
	traceEvictedCount := wrappers ifNil: [0] ifNotNil: [:ws | ws count: [:w | w evicted]].
	traceRoot := SWATraceNode fromLanes: lanes.
	^ resultMap
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:05'
}
SWACoverage >> collectTraceRoot [
	"The reconstructed span tree (a SWATraceNode 'trace' with one lane per process),
	or nil if this was not a trace run or nothing was recorded.

	A pure accessor, like #collectCallTree: #collectTrace has already moved the tree
	out of SWATraceWrapper's class variables into this instance, so the lanes can be
	dropped in the collecting ensure: without taking the tree with them."
	^ traceRoot
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
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 13:28'
}
SWACoverage >> describeException: e [
	"A short 'Class: message' string for a caught test exception, robust against a
	broken #messageText (some exceptions raise while describing themselves)."
	^ [e class name, ': ', (e messageText ifNil: ['<no message>'])]
		on: Error do: [:e2 | e class name, ' (messageText failed)']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:08'
}
SWACoverage >> evictAt [
	"After how many calls a wrapper uninstalls itself, or nil for never. Read by the
	UI so it can say what the bound on a run actually is."
	^ evictAt
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
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:25'
}
SWACoverage >> instrumentTally [
	"TALLY mode: install a live counting SWATallyWrapper on every watched method.
	They stay installed and count every call, self-evicting once a method passes
	evictAt so hot methods stop paying overhead. Exercise the system, then send
	#collectTally and #uninstall. Returns self.

	BULK install: use #installNoFlush per wrapper then #flushSystemCache ONCE.
	Calling #install (which flushes primitive 89, a GLOBAL cache flush) per method
	over tens of thousands of methods re-flushes the whole VM cache tens of thousands
	of times -- the '*' whole-image hang/crash. Same lesson as coverage's
	#installTestCoverage / #runProvenanceCases:panel:."
	"Stamp the kind NOW, not only at collect time: SWAPane holds one ivar for either
	flavour of live run and asks #isTimingRun to decide how to harvest it."
	kind := #tally.
	self captureCallTree
		ifTrue: [SWATallyWrapper beginCallTreeFor: methods]
		ifFalse: [SWATallyWrapper resetCallTree].
	wrappers := methods collect: [:m |
		(SWATallyWrapper new
			onClass: m methodClass selector: m selector evictAt: evictAt)
			installNoFlush; yourself].
	SWAMethodWrapper flushSystemCache.
	^ self
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:25'
}
SWACoverage >> instrumentTiming [
	"TIMING mode: the stopwatch twin of #instrumentTally. Install a live
	SWATimingWrapper on every watched method, so each call is bracketed with
	Time utcMicrosecondClock and charged to inclusive/self microsecond totals as well
	as counted. Exercise the system, then send #collectTiming and #uninstall.

	NO EVICTION (evictAt: nil), unlike the counting tally: a wrapper that uninstalls
	itself after evictAt calls would stop timing exactly the hot methods you are
	looking for, and would leave a total that silently covers only part of the run.
	The price is that the overhead stays for the whole run instead of decaying, so
	prefer a bounded doit or a short exercise -- see the class comment of
	SWATimingWrapper on what tracing costs.

	Also clears this process's timing frame record, so a run can never start halfway
	up a stale frame stack.

	BULK install as in #instrumentTally: #installNoFlush per wrapper, #flushSystemCache
	ONCE at the end (per-method flushing of the global VM cache is the whole-image
	hang)."
	kind := #timing.
	SWATimingWrapper resetFrames.
	self captureCallTree
		ifTrue: [SWATallyWrapper beginCallTreeFor: methods]
		ifFalse: [SWATallyWrapper resetCallTree].
	wrappers := methods collect: [:m |
		(SWATimingWrapper new
			onClass: m methodClass selector: m selector evictAt: nil)
			installNoFlush; yourself].
	SWAMethodWrapper flushSystemCache.
	"Start the wall clock AFTER installing: instrumenting tens of thousands of
	methods takes seconds, and that is setup, not part of what was exercised."
	wallMicros := Time utcMicrosecondClock.
	^ self
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:17'
}
SWACoverage >> instrumentTrace [
	"TRACE mode: everything #instrumentTiming does, plus an EVENT LOG. Each wrapped
	call additionally appends {method. start. stop. depth} to its process's lane, so
	the run can be rebuilt as individual spans on a wall-clock axis (a flame CHART)
	instead of only as aggregates (a flame GRAPH). See the SWATraceWrapper comment.

	EVICTION IS ON, unlike the timing twin, and it is what makes the log affordable.
	Each method drops out after #evictAt calls (1000 by default), so the log costs
	1000 x methods at worst instead of growing with the run. The alternative -- a
	buffer cap -- spends the budget in exactly the wrong place: it keeps the beginning
	and loses the END, which is where you were going. Eviction loses the repetitive
	TAIL of hot methods, which is the part a trace has least to say about.

	Three consequences, all deliberate:
	  * an evicted method is invisible for the rest of the run;
	  * its callees reattach one level up (see SWATraceNode class>>fromLane:) -- a
	    level vanishes, nothing is misattributed;
	  * #timeMap / #selfTimeMap / #resultMap become LOWER BOUNDS for evicted methods,
	    because their wrapper stopped counting and stopped timing at the cut. So the
	    timing metrics on a trace dataset are not interchangeable with those from a
	    real timing run. #traceStatus says how many methods this affected.

	ORDER MATTERS. #armTrace comes BEFORE the wrappers are installed, because the
	install itself must not be recorded, and #wallMicros starts AFTER, because
	instrumenting tens of thousands of methods takes seconds of setup that is not
	part of what was exercised. The trace's own zero is SWATraceWrapper's
	#traceStartMicros, set in #armTrace, so the two clocks agree to within the
	install.

	The log itself is UNBOUNDED (chunked, never truncated) -- eviction is the bound."
	| steps |
	kind := #trace.
	SWATimingWrapper resetFrames.
	self captureCallTree
		ifTrue: [SWATallyWrapper beginCallTreeFor: methods]
		ifFalse: [SWATallyWrapper resetCallTree].
	SWATraceWrapper armTrace.
	steps := SWACoverage stepProbeMethods.
	methods := methods reject: [:m | steps includes: m].
	wrappers := methods collect: [:m |
		(SWATraceWrapper new
			onClass: m methodClass selector: m selector evictAt: evictAt)
			installNoFlush; yourself].
	"The step probe goes in LAST and with evictAt: nil -- always present, never evicted.
	It takes the place of the ordinary wrapper on the Morphic cycle (hence the reject:
	above; wrapping it twice would LAYER two wrappers) and records the same span the
	ordinary one would, plus the per-cycle memory sample and the GC drain. See
	SWACoverage class>>stepProbeMethods."
	wrappers := wrappers asOrderedCollection.
	steps do: [:m |
		wrappers add: ((SWAStepTraceWrapper new
			onClass: m methodClass selector: m selector evictAt: nil)
			installNoFlush; yourself)].
	SWAMethodWrapper flushSystemCache.
	wallMicros := Time utcMicrosecondClock.
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:02'
}
SWACoverage >> isTimingRun [
	"True if this run was instrumented with SWATimingWrapper, so #collectTiming (not
	#collectTally) is the right way to harvest it. Asked by SWAPane when the STOP
	button fires, since one ivar holds either kind of live run.

	#kind is authoritative and is set at INSTRUMENT time by both modes, precisely so
	the answer survives #uninstall -- which empties #wrappers, leaving the fallback
	probe below with nothing to look at. That fallback only covers a run built by
	hand without going through #instrumentTiming."
	#tally == kind ifTrue: [^ false].
	#timing == kind ifTrue: [^ true].
	"A TRACE run is a superset of a timing run -- SWATraceWrapper is a
	SWATimingWrapper and fills the same three maps -- so it answers true here too.
	Callers that want the event log as well must ask #isTraceRun FIRST."
	#trace == kind ifTrue: [^ true].
	^ wrappers notNil and: [wrappers notEmpty and: [wrappers first isKindOf: SWATimingWrapper]]
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:01'
}
SWACoverage >> isTraceRun [
	"True if this run was instrumented with SWATraceWrapper, so #collectTrace is the
	right harvest. #kind is authoritative and set at instrument time so the answer
	survives #uninstall (which empties #wrappers), exactly as in #isTimingRun."
	#trace == kind ifTrue: [^ true].
	kind notNil ifTrue: [^ false].
	^ wrappers notNil and: [wrappers notEmpty and: [wrappers first isKindOf: SWATraceWrapper]]
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
	#category : #instrumenting,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:08'
}
SWACoverage >> methodsForPackages: globCollection [
	"Watch every method of every package whose name matches one of globCollection
	(String>>match: globs), MINUS:
	 - the SUBSTRATE packages (Kernel/Collections/Compiler/...) -- a HARD guard that
	   applies even with #exclusions: #(), because wrapping the foundation collapses
	   the VM (the whole-image-crash lesson);
	 - the user exclusion list (#isExcluded:);
	 - TestCase methods and the coverage/test infrastructure (#mustNotInstrument:).
	Logs each package DIRECTLY to stdout (flag-guarded) so a hang/crash during
	selection is locatable on the command line."
	| infos |
	infos := (PackageInfo allPackages select: [:p |
		globCollection anySatisfy: [:g | g match: p packageName]])
			asSortedCollection: [:a :b | a packageName <= b packageName].
	methods := OrderedCollection new.
	SWACoverage log: '=== STAGE: instrumenting -- selecting methods from ',
		infos size printString, ' candidate packages ==='.
	infos do: [:p |
		(self isSubstrate: p packageName)
			ifTrue: [SWACoverage log: '  SKIP (substrate): ', p packageName]
			ifFalse: [
				(self isExcluded: p packageName)
					ifTrue: [SWACoverage log: '  SKIP (excluded): ', p packageName]
					ifFalse: [ | added |
						SWACoverage log: '  INSTRUMENTING package: ', p packageName.
						added := 0.
						p methods do: [:ref | | m |
							m := ref compiledMethod.
							(m notNil
								and: [(ref actualClass inheritsFrom: TestCase) not]
								and: [(self mustNotInstrument: m) not])
								ifTrue: [methods add: m. added := added + 1]].
						SWACoverage log: '  + ', p packageName, ' (', added printString, ' methods)']]].
	SWACoverage log: '=== STAGE: instrumenting done -- total watched: ', methods size printString, ' methods ==='.
	^ self
]

{
	#category : #selecting,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 19:00'
}
SWACoverage >> mustNotInstrument: aCompiledMethod [
	"True if aCompiledMethod belongs to the coverage/test infrastructure (or a
	subclass of it) -- a hard correctness guard independent of the user exclusion
	list. Checks the instance side so metaclass methods are caught too."
	| cls |
	"#doesNotUnderstand: is on the VM's message-lookup fallback path. Wrapping it as an
	object-as-method corrupts the synthetic DNU send the VM builds -- the reconstructed
	message's receiver/selector shift, so a forwarded send lands on the selector SYMBOL
	(seen as e.g. ByteSymbol>>commitColumns when a Git proxy forwards its list request).
	NEVER instrument it, on any class."
	aCompiledMethod selector == #doesNotUnderstand: ifTrue: [^ true].
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
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:53'
}
SWACoverage >> runOneTest: testCase named: testName [
	"Run one test inside the MEASURING WINDOW -- #whileUnguardedDo: lowers the
	reentrancy guard ONLY here, so the wrapped methods the test body exercises are
	counted and attributed. Everything outside (the loop, logging, install/uninstall)
	stays guarded and is never instrumented. Under a broad Exception handler; logs
	'ok' / 'ERR <test> -- ...'. A 'RUN' with no following ok/ERR means a hard VM crash."
	| failure |
	failure := nil.
	SWAMethodWrapper whileUnguardedDo: [
		[testCase run] on: Exception do: [:e |
			failure := self describeException: e.
			e return: nil]].
	failure isNil
		ifTrue: [SWACoverage log: '    ok   ', testName]
		ifFalse: [SWACoverage log: '    ERR  ', testName, ' -- ', failure]
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:50'
}
SWACoverage >> runProvenanceCase: testCase into: cov done: done of: total panel: aPanelOrNil [
	"Run ONE already-bound TestCase instance under the current (guarded) loop:
	set CurrentTest, run it in the measuring window (#runOneTest:named: lowers the
	guard around #testCase run), clear CurrentTest, and update the panel every 10."
	| testName |
	testName := testCase class name, '>>', testCase selector.
	SWACoverage log: '    RUN  ', testName.
	SWACoverageWrapper currentTest: testName.
	self runOneTest: testCase named: testName.
	SWACoverageWrapper currentTest: nil.
	(aPanelOrNil notNil and: [done \\ 10 = 0]) ifTrue: [
		aPanelOrNil status: 'Running tests: ', done printString, '/', total printString,
			'  (', cov coveredMethodCount printString, ' methods covered)']
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:36'
}
SWACoverage >> runProvenanceCases: testCases panel: aPanelOrNil [
	"THE single provenance core. Runs a FLAT collection of TestCase instances (each
	bound to one selector), attributing every watched method each test exercises to
	that test, into a SWACoverageData. Both public runners delegate here:
	  - #runWithProvenance:panel: expands whole test CLASSES to their cases;
	  - #runWithProvenanceTestCases:panel: passes hand-picked cases through.

	FLAG MODEL: the whole loop runs GUARDED (#guardedDo:); the measuring window is
	opened ONLY around #testCase run (in #runOneTest:named:). Wrappers + recording
	state are always cleaned up (ensure:). Answers the SWACoverageData (partial if
	stopped). EVICTION: each wrapper self-uninstalls after evictAt calls; AFTER the
	run we flag those methods in the data (#markEvicted:) so the analyse side can
	paint them RED. This is end-of-run bookkeeping, NOT the capture hot path.
	INVOCATIONS: we also persist each wrapper's raw call count (#count) so the view
	can size tiles by actual invocation count, not just covering-test count."
	| cov wrappers total done evictedCount |
	cov := SWACoverageData new maxTestsPerMethod: maxTestsPerMethod.
	watchedMethods := methods asArray.
	wrappers := watchedMethods collect: [:m |
		SWACoverageWrapper new onClass: m methodClass selector: m selector data: cov].
	total := testCases size max: 1.
	done := 0.
	SWACoverage log: '=== STAGE: provenance run -- ', watchedMethods size printString,
		' methods, ', testCases size printString, ' test cases ==='.
	SWACoverageWrapper resetRecordingState.
	SWACoverageWrapper sink: cov.
	[	wrappers do: [:w | w installNoFlush].
		SWAMethodWrapper flushSystemCache.
		SWACoverage log: '=== STAGE: wrappers installed (', wrappers size printString, '); starting tests ==='.
		self withSuppressedUI: [SWAMethodWrapper guardedDo: [
			testCases do: [:testCase |
				(aPanelOrNil isNil or: [aPanelOrNil stopRequested not]) ifTrue: [
					done := done + 1.
					self runProvenanceCase: testCase into: cov done: done of: total panel: aPanelOrNil]]]]]
		ensure: [
			SWACoverage log: '=== STAGE: uninstalling wrappers ==='.
			SWACoverageWrapper resetRecordingState.
			wrappers do: [:w | w uninstallNoFlush].
			SWAMethodWrapper flushSystemCache].
	evictedCount := wrappers count: [:w | w evicted].
	wrappers do: [:w | w evicted ifTrue: [cov markEvicted: w methodName]].
	"Persist raw invocation counts (lower bound for evicted methods)."
	wrappers do: [:w | cov recordInvocationCount: w count for: w methodName].
	SWACoverage log: '=== STAGE: ', evictedCount printString, ' methods EVICTED (hot, >= ',
		SWAMethodWrapper defaultEvictAt printString, ' calls) ==='.
	SWACoverage log: '=== STAGE: provenance complete -- ',
		cov coveredMethodCount printString, ' covered, ',
		cov testNames size printString, ' tests ==='.
	^ cov
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
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:50'
}
SWACoverage >> runWithProvenance: testClasses panel: aPanelOrNil [
	"Run whole test CLASSES with provenance: expand each to its one-selector cases
	(#casesForTestClasses:, which logs a per-class header AND builds #suite under the
	guard -- some classes COMPILE methods in #suite, firing the wrapped system-change
	chain, so this must stay guarded), then delegate to the shared core
	#runProvenanceCases:panel:. Answers the SWACoverageData."
	^ SWAMethodWrapper guardedDo: [
		self runProvenanceCases: (self casesForTestClasses: testClasses) panel: aPanelOrNil]
]

{
	#category : #provenance,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:51'
}
SWACoverage >> runWithProvenanceTestCases: testCases panel: aPanelOrNil [
	"Run an EXPLICIT, hand-picked collection of TestCase INSTANCES (each bound to one
	selector, e.g. from #testCasesFromSpecs:) while instrumenting the current method
	scope. Thin delegator to the shared core #runProvenanceCases:panel:. Use to run a
	few specific tests (e.g. one method) but measure a broad instrumentation scope."
	^ SWAMethodWrapper guardedDo: [
		self runProvenanceCases: testCases asArray panel: aPanelOrNil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:19'
}
SWACoverage >> selfTimeMap [
	"'Class>>selector' -> EXCLUSIVE microseconds, filled by #collectTiming. Empty
	Dictionary for a run that was not a timing run."
	^ selfTimeMap ifNil: [selfTimeMap := Dictionary new]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:19'
}
SWACoverage >> timeMap [
	"'Class>>selector' -> INCLUSIVE microseconds, filled by #collectTiming. Empty
	Dictionary for a run that was not a timing run."
	^ timeMap ifNil: [timeMap := Dictionary new]
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:08'
}
SWACoverage >> traceStatus [
	"One line about the captured trace, EVICTION INCLUDED. A method that evicted stops
	appearing in the tree and its count and times stop growing, so a run with heavy
	eviction looks like a run that quietly got simpler. This string is meant to be
	shown, not just available."
	| lanes |
	traceRoot ifNil: [^ 'Trace: nothing recorded'].
	lanes := traceRoot children size.
	^ String streamContents: [:s |
		s nextPutAll: 'Trace: ';
			print: (traceEventCount ifNil: [0]);
			nextPutAll: ' calls in ';
			print: lanes;
			nextPutAll: (lanes = 1 ifTrue: [' process'] ifFalse: [' processes']).
		(traceEvictedCount ifNil: [0]) > 0 ifTrue: [
			s nextPutAll: ' -- '; print: traceEvictedCount;
			nextPutAll: ' methods evicted after '; print: (evictAt ifNil: [0]);
			nextPutAll: ' calls (their counts/times are lower bounds)']]
]

{
	#category : #'invocation tally',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:33'
}
SWACoverage >> uninstall [
	"Restore every method (tally mode). Idempotent; safe to call after eviction.

	BULK uninstall: #uninstallNoFlush per wrapper then #flushSystemCache ONCE, for
	the same reason as #instrumentTally -- a per-method global cache flush over the
	whole image ('*') hangs/crashes the VM."
	wrappers do: [:w | w uninstallNoFlush].
	SWAMethodWrapper flushSystemCache.
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

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:19'
}
SWACoverage >> wallMicros [
	"Wall time of the exercise in microseconds -- the clock delta between the end of
	instrumenting (#instrumentTiming) and #collectTiming, instrumentation overhead
	INCLUDED. This is 'how long the run actually took', the number a stopwatch in the
	room would show; the per-method totals are the compensated ones. 0 outside a
	timing run."
	^ wallMicros ifNil: [0]
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 10:27'
}
SWACoverage >> withSuppressedUI: aBlock [
	"Evaluate aBlock with a non-interactive DummyUIManager installed on the current
	project, restoring the previous one afterwards (ensure:).

	WHY: a test may try to pop a menu / open a (pre-)Debugger / show a dialog. With
	the real (Morphic/MVC) UIManager that builds an actual menu Form -- and under
	instrumentation that path crashed the VM in PopUpMenu>>computeForm (the '*' run,
	2026-06-26). DummyUIManager answers every UI request programmatically (menus ->
	nil, choices -> a default index, confirm -> default), so such tests neither block
	nor build UI. This lets us KEEP the menu/ToolBuilder/Debugger packages
	INSTRUMENTED (we still measure their coverage) instead of excluding them -- we
	just stop them from actually opening during the run."
	| project saved |
	project := Project current.
	saved := project uiManager.
	project instVarNamed: 'uiManager' put: DummyUIManager new.
	^ [aBlock value]
		ensure: [project instVarNamed: 'uiManager' put: saved]
]
