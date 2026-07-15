"
An image-independent, PathTools-style test-coverage relation: not just WHICH
methods ran, but WHICH TESTS covered each method.

Inspired by Michael Perscheid et al.'s PathTools / test-driven fault navigation:
the dynamic test<->method relation is the interesting datum -- from a method you
can see its covering tests (and jump to them); from a test you can see what it
exercises.

Identity is by 'Class>>selector' strings (metaclass: 'Class class>>selector'), so
the data survives recompilation, relayout, and different checkouts -- it is image-
and file-independent (unlike Coveralls' path/line/md5 format).

Structure (also the on-disk JSON shape):
  tests    : Array of 'Class>>selector'  -- the test index; position = test id
  methods  : Array of 'Class>>selector'  -- the method index; position = method id
  coverage : Dictionary methodId -> { #count -> Integer. #tests -> Array of testId }
             count = total number of distinct tests that covered the method;
             tests = the FIRST maxTestsPerMethod (default 10) of them.

So a method covered by 37 tests stores count=37 and 10 sample test ids -- bounded
memory, hot methods can't blow it up, but you still know how broadly it is covered.

Build it with SWACoverage (the runner attributes each fired method to the running
test); query with #testsForMethod: / #methodsForTest:; persist with
#asJsonString / SWACoverageData fromJsonString:.

Instance Variables
	testNames          <Array of String>          test index (id -> name)
	methodNames        <Array of String>          method index (id -> name)
	methodIds          <Dictionary name -> id>    reverse method lookup (build time)
	testIds            <Dictionary name -> id>    reverse test lookup (build time)
	coverage           <Dictionary methodId -> Dict(#count,#tests)>
	maxTestsPerMethod  <Integer>                  cap on stored covering tests (n)
"
Class {
	#name : #SWACoverageData,
	#superclass : #Object,
	#instVars : [
		'testNames',
		'methodNames',
		'methodIds',
		'testIds',
		'coverage',
		'maxTestsPerMethod'
	],
	#category : #'SWA-Coverage',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData class >> fromFile: aFilePath [
	"Reconstruct from a JSON file written by #writeToFile:."
	| contents |
	contents := (FileStream readOnlyFileNamed: aFilePath) contentsOfEntireFile.
	^ self fromJsonString: contents
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData class >> fromJsonString: aJsonString [
	"Reconstruct from the JSON form written by #asJsonString. Image-independent:
	names are matched by 'Class>>selector' against whatever image loads them."
	| json data |
	json := Json readFrom: aJsonString readStream.
	data := self new.
	data loadFromJson: json.
	^ data
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:36'
}
SWACoverageData >> asJsonString [
	"Serialise to the reusable, image-independent JSON form:
	{ #format, #tests:[names], #methods:[names],
	  #coverage:{ methodId(string): { count:N, tests:[testIds], evicted:true,
	                                  invocations:N } } }.
	Method/test ids are 1-based positions into the name arrays. JSON object keys
	must be strings, so methodId keys are printed as strings. #evicted is written
	only for methods that were evicted (hot methods whose wrapper self-uninstalled).
	#invocations (raw call count) is written only when recorded."
	| dict cov |
	cov := Dictionary new.
	coverage keysAndValuesDo: [:mid :entry |
		| e |
		e := Dictionary new
			at: 'count' put: (entry at: #count);
			at: 'tests' put: (entry at: #tests) asArray;
			yourself.
		(entry at: #evicted ifAbsent: [false]) == true ifTrue: [e at: 'evicted' put: true].
		entry at: #invocations ifPresent: [:n | e at: 'invocations' put: n].
		cov at: mid printString put: e].
	dict := Dictionary new
		at: 'format' put: 'SWACoverageData/1';
		at: 'maxTestsPerMethod' put: maxTestsPerMethod;
		at: 'tests' put: testNames asArray;
		at: 'methods' put: methodNames asArray;
		at: 'coverage' put: cov;
		yourself.
	^ String streamContents: [:s | dict jsonWriteOn: s]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData >> coveredMethodCount [
	^ coverage size
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> coveringTestCountFor: aMethodName [
	"How many distinct tests covered the method (may exceed the stored sample)."
	| mid |
	mid := methodIds at: aMethodName ifAbsent: [^ 0].
	^ (coverage at: mid ifAbsent: [^ 0]) at: #count
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:36'
}
SWACoverageData >> hasInvocationData [
	"True if any method carries a raw invocation count (i.e. this data was generated
	by a runner that records invocations). Old JSON files answer false, so the view
	can fall back to covering-test weighting and tell the user."
	^ coverage anySatisfy: [:entry | entry includesKey: #invocations]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:19'
}
SWACoverageData >> initialize [
	testNames := OrderedCollection new.
	methodNames := OrderedCollection new.
	methodIds := Dictionary new.
	testIds := Dictionary new.
	coverage := Dictionary new.
	maxTestsPerMethod := 10
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:35'
}
SWACoverageData >> invocationCountFor: aMethodName [
	"How many times the method was actually invoked during the run (0 if unknown --
	not recorded, or coverage generated before invocation counting existed). A lower
	bound for evicted methods (counting stopped at the eviction cap)."
	| mid |
	mid := methodIds at: aMethodName ifAbsent: [^ 0].
	^ (coverage at: mid ifAbsent: [^ 0]) at: #invocations ifAbsent: [0]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:35'
}
SWACoverageData >> invocationMap [
	"A flat 'Class>>selector' -> raw invocation count map, for driving the
	invocation-count-WEIGHTED treemap (tiles sized by how many times each method was
	actually called). Methods with no recorded invocation count are absent."
	| map |
	map := Dictionary new.
	coverage keysAndValuesDo: [:mid :entry |
		entry at: #invocations ifPresent: [:n |
			map at: (methodNames at: mid) put: n]].
	^ map
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> isCovered: aMethodName [
	"True if any test covered the method 'Class>>selector'."
	| mid |
	mid := methodIds at: aMethodName ifAbsent: [^ false].
	^ coverage includesKey: mid
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:23'
}
SWACoverageData >> isEvicted: aMethodName [
	"True if aMethodName ('Class>>selector') was evicted during the run."
	| mid entry |
	mid := methodIds at: aMethodName ifAbsent: [^ false].
	entry := coverage at: mid ifAbsent: [^ false].
	^ (entry at: #evicted ifAbsent: [false]) == true
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:22'
}
SWACoverageData >> isTestKey: aKey [
	"True if aKey is the crossRefKey of a test method that ran ('TestClass>>selector')
	or of a TestCase class whose tests ran (bare class name)."
	aKey ifNil: [^ false].
	^ (testIds includesKey: aKey) or: [self testClassNameSet includes: aKey]
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:36'
}
SWACoverageData >> loadFromJson: json [
	"Populate from a parsed JSON object (see #asJsonString for the shape)."
	| cov |
	maxTestsPerMethod := (json at: 'maxTestsPerMethod' ifAbsent: [10]).
	testNames := (json at: 'tests' ifAbsent: [#()]) asOrderedCollection.
	methodNames := (json at: 'methods' ifAbsent: [#()]) asOrderedCollection.
	"Rebuild reverse lookups."
	testIds := Dictionary new.
	testNames doWithIndex: [:nm :i | testIds at: nm put: i].
	methodIds := Dictionary new.
	methodNames doWithIndex: [:nm :i | methodIds at: nm put: i].
	"Rebuild coverage relation (keys came back as strings)."
	coverage := Dictionary new.
	cov := json at: 'coverage' ifAbsent: [Dictionary new].
	cov keysAndValuesDo: [:midStr :entry |
		| e |
		e := Dictionary new
			at: #count put: (entry at: 'count');
			at: #tests put: (entry at: 'tests') asOrderedCollection;
			yourself.
		(entry at: 'evicted' ifAbsent: [false]) == true ifTrue: [e at: #evicted put: true].
		entry at: 'invocations' ifPresent: [:n | e at: #invocations put: n].
		coverage at: midStr asNumber put: e]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:23'
}
SWACoverageData >> markEvicted: aMethodName [
	"Flag aMethodName ('Class>>selector') as EVICTED -- its wrapper self-uninstalled
	after evictAt invocations (a hot method that stopped being measured). Set ONCE at
	the END of a run by the runner (NOT in the capture hot path). Stored inline in the
	method's coverage entry under #evicted; an evicted method was called >= evictAt
	times so it has a coverage entry, but intern defensively."
	| mid entry |
	mid := self methodIdFor: aMethodName.
	entry := coverage at: mid ifAbsentPut: [
		Dictionary new at: #count put: 0; at: #tests put: OrderedCollection new; yourself].
	entry at: #evicted put: true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> maxTestsPerMethod: anInteger [
	"Cap (n) on how many covering test ids are stored per method."
	maxTestsPerMethod := anInteger
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> methodIdFor: aMethodName [
	"Intern a method 'Class>>selector', answering its (1-based) id."
	^ methodIds at: aMethodName ifAbsentPut: [
		methodNames add: aMethodName.
		methodNames size]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> methodNames [
	"The method index: Array where position i is method id i's 'Class>>selector'."
	^ methodNames
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData >> methodsForTest: aTestName [
	"All methods (as 'Class>>selector') that the given test covered, reconstructed
	from the stored relation. Note: only reflects methods where this test is within
	the per-method sample cap."
	| tid |
	tid := testIds at: aTestName ifAbsent: [^ #()].
	^ (coverage keys
		select: [:mid | ((coverage at: mid) at: #tests) includes: tid])
		collect: [:mid | methodNames at: mid]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:22'
}
SWACoverageData >> methodsForTestClass: aClassName [
	"Union of all methods ('Class>>selector') covered by any test method of the
	named TestCase class. Best-effort: per-method test samples are capped at
	maxTestsPerMethod, so a method covered ONLY by tests beyond the cap may be
	missed (same caveat as methodsForTest:)."
	| tids result |
	tids := Set new.
	testIds keysAndValuesDo: [:name :tid | | idx |
		idx := name indexOfSubCollection: '>>'.
		(idx > 0 and: [(name copyFrom: 1 to: idx - 1) = aClassName])
			ifTrue: [tids add: tid]].
	result := Set new.
	coverage keysAndValuesDo: [:mid :entry |
		((entry at: #tests) anySatisfy: [:tid | tids includes: tid])
			ifTrue: [result add: (methodNames at: mid)]].
	^ result
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:22'
}
SWACoverageData >> methodsForTestOrClass: aKey [
	"Methods covered by the test or TestCase identified by aKey. If aKey is a
	'TestClass>>selector' test method key, answers just that test's methods; if
	aKey is a bare TestCase class name, answers the union over all its test
	methods. Answers an empty collection for anything else."
	aKey ifNil: [^ #()].
	(testIds includesKey: aKey) ifTrue: [^ self methodsForTest: aKey].
	^ self methodsForTestClass: aKey
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:35'
}
SWACoverageData >> recordInvocationCount: anInteger for: aMethodName [
	"Store the RAW invocation count (how many times the method was actually called
	during the run, as tracked by SWAMethodWrapper>>count) for aMethodName. Set
	ONCE at the end of a run by the runner, alongside #markEvicted:. Distinct from
	#count, which is the number of distinct COVERING TESTS. A method that hit the
	eviction cap stopped counting at evictAt, so its invocation count is a lower
	bound (the method is also flagged #evicted). Zero counts are skipped."
	| mid entry |
	anInteger <= 0 ifTrue: [^ self].
	mid := self methodIdFor: aMethodName.
	entry := coverage at: mid ifAbsentPut: [
		Dictionary new at: #count put: 0; at: #tests put: OrderedCollection new; yourself].
	entry at: #invocations put: anInteger
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> recordTest: aTestName covers: aMethodName [
	"Note that the test aTestName executed the method aMethodName. Increments the
	method's total covering-test count and stores the test id if still under the
	cap. Interns both names. Idempotent per (test, method) pair within one build is
	NOT enforced here -- the runner is expected to call this once per pair."
	| mid tid entry tests |
	mid := self methodIdFor: aMethodName.
	tid := self testIdFor: aTestName.
	entry := coverage at: mid ifAbsentPut: [
		Dictionary new at: #count put: 0; at: #tests put: OrderedCollection new; yourself].
	entry at: #count put: (entry at: #count) + 1.
	tests := entry at: #tests.
	tests size < maxTestsPerMethod ifTrue: [tests add: tid]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData >> resultMap [
	"A flat 'Class>>selector' -> coveringTestCount map, for driving the existing
	coverage overlay (treated like a tally: more covering tests = hotter). Methods
	with no coverage are simply absent."
	| map |
	map := Dictionary new.
	coverage keysAndValuesDo: [:mid :entry |
		map at: (methodNames at: mid) put: (entry at: #count)].
	^ map
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:22'
}
SWACoverageData >> testClassNameSet [
	"A Set of the names of all TestCase classes whose tests ran (parsed from the
	'TestClass>>selector' test keys). Used to tint TestCase class tiles blue."
	| set |
	set := Set new.
	testNames do: [:each | | idx |
		idx := each indexOfSubCollection: '>>'.
		idx > 0 ifTrue: [set add: (each copyFrom: 1 to: idx - 1)]].
	^ set
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:22'
}
SWACoverageData >> testClassesForMethod: aMethodName [
	"The distinct TestCase class names among the (sampled) covering tests of the
	method. Derived from testsForMethod:, so subject to the per-method sample cap."
	| set |
	set := Set new.
	(self testsForMethod: aMethodName) do: [:testKey | | idx |
		idx := testKey indexOfSubCollection: '>>'.
		idx > 0 ifTrue: [set add: (testKey copyFrom: 1 to: idx - 1)]].
	^ set
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> testIdFor: aTestName [
	"Intern a test 'Class>>selector', answering its (1-based) id."
	^ testIds at: aTestName ifAbsentPut: [
		testNames add: aTestName.
		testNames size]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:22'
}
SWACoverageData >> testKeySet [
	"A Set of all executed test keys ('TestClass>>selector') seen in this run.
	Used by the Code Map to tint test method tiles blue."
	^ testNames asSet
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWACoverageData >> testKeysForMethod: aMethodName [
	"The crossRefKeys to highlight as 'covered this method': the (sampled) covering
	test methods ('TestClass>>selector') AND their distinct TestCase class names, so
	both the test tiles and their class tiles light up. Subject to the per-method
	sample cap (same caveat as testsForMethod:)."
	| set |
	set := Set new.
	(self testsForMethod: aMethodName) do: [:testKey |
		set add: testKey.
		(testKey indexOfSubCollection: '>>') > 0 ifTrue: [
			set add: (testKey copyFrom: 1 to: (testKey indexOfSubCollection: '>>') - 1)]].
	^ set
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:44'
}
SWACoverageData >> testNames [
	"The test index: Array where position i is test id i's 'Class>>selector'."
	^ testNames
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData >> testsForMethod: aMethodName [
	"The first n covering tests of the method, as 'Class>>selector' strings
	(possibly fewer than the total count)."
	| mid entry |
	mid := methodIds at: aMethodName ifAbsent: [^ #()].
	entry := coverage at: mid ifAbsent: [^ #()].
	^ (entry at: #tests) collect: [:tid | testNames at: tid]
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:45'
}
SWACoverageData >> writeToFile: aFilePath [
	"Write the JSON form to aFilePath."
	| stream |
	stream := FileStream forceNewFileNamed: aFilePath.
	[stream nextPutAll: self asJsonString] ensure: [stream close].
	^ aFilePath
]
