"
I parse a Squeak .changes file into a time-bucketed SWAChangeNode tree, optionally scoped to a time interval.

I do two passes over the file (or a tail region large enough to cover the requested interval):

1. A raw scan for save boundaries -- the ----SNAPSHOT----{ts}, ----QUIT----{ts}
   and ----STARTUP----{ts} lines -- recording each one's file position, kind and
   TimeStamp. These become #save nodes.
2. A ChangeList scan for ChangeRecords (method defs, doIts, class defs, comments,
   removals).

Each record's effective timestamp is its own stamp when it has one, else the
timestamp of the nearest preceding boundary (matched by file position). Records
outside [fromTime, toTime] are dropped. The survivors are bucketed:

  root -> year -> month -> week -> day -> save -> change

Usage:
	SWAChangeParser new treeForLastDays: 7.
	(SWAChangeParser onFile: '/path/x.changes') treeFrom: aTime to: bTime.
	SWAChangeParser openLastDays: 7.   """"build + open the treemap""""
"
Class {
	#name : #SWAChangeParser,
	#superclass : #Object,
	#instVars : [
		'fileName',
		'fromTime',
		'toTime',
		'boundaries',
		'records'
	],
	#category : #'SWA-ChangeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 12:09'
}
SWAChangeParser class >> chooseChangesFilePrompt: aPromptString [
	"Open a *.changes file chooser and answer the chosen full path, or nil if
	cancelled. Falls back to a text path prompt if no file chooser is available."
	| result |
	(Smalltalk includesKey: #StandardFileMenu) ifTrue: [
		result := StandardFileMenu oldFileFrom: FileDirectory default withPattern: '*.changes'.
		result ifNil: [^ nil].
		^ result directory fullNameFor: result name].
	^ (UIManager default request: aPromptString initialAnswer: '')
		ifNil: [nil] ifNotNil: [:s | s isEmpty ifTrue: [nil] ifFalse: [s withBlanksTrimmed]]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:45'
}
SWAChangeParser class >> initialize [
	"Register the Apps-menu entries for the Change Map, alongside the other SWA
	tools. The 'SWA ' label prefix groups them together in the (alphabetically
	sorted) Apps menu. Idempotent: removes any prior entry for this receiver first.

		SWAChangeParser initialize"
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Change Map'.
		{self. #openChangeMapForDays}.
		'Treemap of this image''s .changes file over the last N days' }.
	TheWorldMenu registerOpenCommand: {
		'SWA Change Map (diff two changes files)'.
		{self. #openInteractiveDiffChangeMap}.
		'Pick a NEWER and a BASELINE .changes file; map what the newer one has and the baseline is missing' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:50'
}
SWAChangeParser class >> onFile: aFileName [
	^ self new fileName: aFileName
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:46'
}
SWAChangeParser class >> openChangeMapForDays [
	"Apps-menu entry: ask how far back to go, then map the running image's own
	.changes file. Answers nil if cancelled or if the answer is not a number.

	The window is the interesting variable here -- a day tells you what this session
	did, a fortnight tells you what the project did -- so the menu asks rather than
	hardcoding 7 (which #openChangeMapLast7Days still does, for scripts)."
	| answer days |
	answer := UIManager default
		request: 'Map the last how many days of changes?'
		initialAnswer: '7'.
	(answer isNil or: [answer isEmpty]) ifTrue: [^ nil].
	days := answer asNumber.
	(days isNil or: [days <= 0]) ifTrue: [^ nil].
	"max: 1 -- a fractional answer like '0.5' survives the >0 test but truncates to
	zero, which would silently open an empty map."
	^ self openLastDays: (days asInteger max: 1)
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:45'
}
SWAChangeParser class >> openChangeMapLast7Days [
	"Open a change treemap of the image's .changes file for the last 7 days.
	A fixed-window convenience for scripts; the Apps-menu entry is
	#openChangeMapForDays, which asks for the window (see #initialize)."
	| parser root |
	parser := self new.
	parser fileName: Smalltalk changesName.
	root := parser treeForLastDays: 7.
	^ parser openTreemapForRoot: root
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:56'
}
SWAChangeParser class >> openFrom: aStartTimeStamp to: anEndTimeStampOrNil onFile: aFileNameOrNil [
	"Build and open a treemap of changes in [start, end] from a specific changes
	file (nil = the running image's own). Scans the whole file (any interval)."
	| parser root |
	parser := aFileNameOrNil
		ifNil: [self new]
		ifNotNil: [:fn | self onFile: fn].
	parser fromTime: aStartTimeStamp to: anEndTimeStampOrNil.
	root := parser buildTreeTailBytes: nil
		rootLabel: 'Changes: ', aStartTimeStamp date mmddyyyy,
			(anEndTimeStampOrNil ifNil: [' -> now'] ifNotNil: [:t | ' -> ', t date mmddyyyy]).
	^ parser openTreemapForRoot: root
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 12:09'
}
SWAChangeParser class >> openInteractiveDiffChangeMap [
	"Interactively diff two changes files. Ask the user to pick a NEWER (foreign)
	changes file, then a BASELINE file, then open a treemap of the changes present
	in the newer file but missing from the baseline (see buildRecoveryTreeAgainst:).
	Answer the opened window, or nil if the user cancelled either prompt."
	| newerFile baselineFile parser root |
	newerFile := self chooseChangesFilePrompt: 'Path of the NEWER changes file'.
	newerFile ifNil: [^ nil].
	baselineFile := self chooseChangesFilePrompt: 'Path of the BASELINE changes file to diff against'.
	baselineFile ifNil: [^ nil].
	parser := self onFile: newerFile.
	root := parser buildRecoveryTreeAgainst: baselineFile.
	^ parser openTreemapForRoot: root
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:29'
}
SWAChangeParser class >> openLastDays: nDays [
	"Build and open a time-bucketed treemap of the last nDays of the running
	image's changes.

	SWAChangeParser openLastDays: 7."
	^ self openLastDays: nDays onFile: nil
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:29'
}
SWAChangeParser class >> openLastDays: nDays onFile: aFileNameOrNil [
	"Build and open a time-bucketed treemap of the last nDays of changes from a
	specific changes file (nil = the running image's own).

	SWAChangeParser openLastDays: 14 onFile: '/home/jens/lively4/squeak/alpha.10.changes'.
	SWAChangeParser openLastDays: 7 onFile: nil."
	| parser root |
	parser := aFileNameOrNil
		ifNil: [self new]
		ifNotNil: [:fn | self onFile: fn].
	root := parser treeForLastDays: nDays.
	^ parser openTreemapForRoot: root
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:39'
}
SWAChangeParser class >> openRecover: aForeignChangesFileName [
	"Open a treemap of the changes captured in a foreign changes file that are NOT
	in MY changes file (the running image's own) -- i.e. what that image branch did
	that mine lacks. Diffs the two append-only changes files: their long identical
	prefix is skipped by a byte compare, and only the small divergent tails are
	parsed and set-differenced. Tree is the usual time->package->class hierarchy
	pruned to the missing leaves.

	SWAChangeParser openRecover: '/home/jens/lively4/squeak/alpha.10.changes'."
	^ self openRecover: aForeignChangesFileName against: Smalltalk changesName
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:39'
}
SWAChangeParser class >> openRecover: aForeignChangesFileName against: myChangesFileName [
	"Open a recovery treemap of the changes in aForeignChangesFileName that are NOT
	in myChangesFileName, by diffing the two append-only changes files (common
	prefix skipped via byte compare; only divergent tails parsed).

	SWAChangeParser
		openRecover: '/home/jens/lively4/squeak/alpha.10.changes'
		against: '/home/jens/lively4/squeak/beta.1.changes'."
	| parser root |
	parser := self onFile: aForeignChangesFileName.
	root := parser buildRecoveryTreeAgainst: myChangesFileName.
	^ parser openTreemapForRoot: root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:53'
}
SWAChangeParser >> attachLeaf: aLeaf under: aParentNode [
	| kids |
	kids := aParentNode children asOrderedCollection.
	kids add: aLeaf.
	aParentNode children: kids
]

{
	#category : #grouping,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 15:05'
}
SWAChangeParser >> baseClassNameFrom: aClassNameStringOrNil [
	"The instance-side class name for a change's methodClassName, dropping a
	trailing ' class' so a metaclass change groups with its base class."
	| s |
	aClassNameStringOrNil ifNil: [^ nil].
	s := aClassNameStringOrNil asString withBlanksTrimmed.
	(s endsWith: ' class') ifTrue: [^ (s copyFrom: 1 to: s size - 6) withBlanksTrimmed].
	^ s
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:52'
}
SWAChangeParser >> boundaryTimeFor: aRecord in: sortedBoundaries [
	"The TimeStamp of the last boundary at or before aRecord's file position,
	or nil if none precedes it."
	| pos best |
	pos := aRecord position.
	best := nil.
	sortedBoundaries do: [:assoc |
		assoc key <= pos
			ifTrue: [best := assoc value timeStamp]
			ifFalse: [^ best]].
	^ best
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:34'
}
SWAChangeParser >> buildRecoveryTree [
	"Build a time->package->class tree of the changes in this parser's file that are
	NOT present in the running image (see SWAChangeNode>>isMissingFromImage), pruning
	away every branch with no missing leaf. Scans the WHOLE file with no time window."
	| root label |
	label := 'Recover: ', (FileDirectory localNameFor: self fileName),
		'  (missing from image)'.
	self fromTime: nil to: nil.
	root := self buildTreeTailBytes: nil rootLabel: label.
	root pruneKeepingLeavesSatisfying: [:leaf | leaf isMissingFromImage].
	root children isEmpty ifTrue: [
		root label: label, ' -- nothing missing'].
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:38'
}
SWAChangeParser >> buildRecoveryTreeAgainst: myFileName [
	"Build a time->package->class tree of the changes in this parser's (FOREIGN)
	file that are NOT present in myFileName, by DIFFING THE TWO CHANGES FILES.

	Changes files are append-only: two files sharing history are byte-identical for
	a long common prefix and diverge only near the end. So we:
	  1. find the common-prefix length (a plain byte compare -- no parsing),
	  2. back both up to a clean chunk boundary,
	  3. collect the signatures of MY divergent tail,
	  4. parse the FOREIGN divergent tail into the usual tree,
	  5. keep only leaves whose signature is NOT in my tail, pruning empty branches.
	The identical prefix is never interpreted, so this is fast regardless of file
	size -- only the small divergent tails are scanned."
	| divergePos foreignStart myStart myParser mySigs root label mySize |
	divergePos := self commonPrefixLengthWith: myFileName.
	foreignStart := self chunkAlignedStartBefore: divergePos.
	myParser := SWAChangeParser onFile: myFileName.
	myStart := myParser chunkAlignedStartBefore: divergePos.
	mySize := (FileStream readOnlyFileNamed: myFileName) size.
	mySigs := myParser signaturesFrom: myStart to: mySize.
	label := 'Recover: ', (FileDirectory localNameFor: self fileName),
		'  vs ', (FileDirectory localNameFor: myFileName).
	self fromTime: nil to: nil.
	root := self buildTreeFromPosition: foreignStart rootLabel: label.
	root pruneKeepingLeavesSatisfying: [:leaf |
		(mySigs includes: leaf contentSignature) not].
	root children isEmpty ifTrue: [
		root label: label, ' -- nothing missing'].
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:38'
}
SWAChangeParser >> buildTreeFromPosition: startPos rootLabel: aLabel [
	"Like buildTreeTailBytes:rootLabel: but scans from an EXACT byte position (a
	chunk boundary) to end of file. Used by the recovery diff, which starts exactly
	at the divergence point."
	| sz bnds recs |
	sz := (FileStream readOnlyFileNamed: self fileName) size.
	bnds := self scanBoundariesFrom: startPos to: sz.
	recs := self scanRecordsFrom: startPos to: sz.
	^ self buildTreeFromRecords: recs boundaries: bnds rootLabel: aLabel
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:20'
}
SWAChangeParser >> buildTreeFromRecords: recs boundaries: sortedBoundaries rootLabel: aLabel [
	"Bucket recs (already time-filtered) into the tree
	root -> year -> month -> week -> day -> save -> package -> class -> change.
	Class-less changes (doIts, misc) go under a synthetic 'doIts' package with the
	leaf placed directly under it (no class level).

	As records are processed in file order we also link, per Class>>selector:
	- #prevInScope: each leaf's nearest earlier change in this scope (the diff
	  baseline), and
	- #superseded: the earlier leaf is flagged when a later one appears.

	A separate lastSourceByKey map tracks the last DEFINITION source per method seen
	anywhere in the scanned region (even outside the time window) so a method REMOVAL
	can diff against -- and be sized by -- the body that was removed.

	Boundary-marker #misc records are skipped -- they are already #save nodes."
	| root index saveCache kept lastLeafByKey lastSourceByKey |
	root := SWAChangeNode new kind: #root; label: aLabel; yourself.
	index := IdentityDictionary new.
	saveCache := Dictionary new.
	lastLeafByKey := Dictionary new.
	lastSourceByKey := Dictionary new.
	kept := 0.
	recs do: [:rec | | ts date yNode mNode wNode dNode sNode leaf saveNode
			baseClass pkgName pNode leafParent key recKey |
		(self isNoiseRecord: rec) ifFalse: [
			"Track last method-definition body per key across the whole scanned
			region, in file order, for removal baselines."
			recKey := self keyForRecord: rec.
			(recKey notNil and: [rec type == #method]) ifTrue: [
				lastSourceByKey at: recKey put: ([rec string] on: Error do: [:e | nil])].
			ts := self effectiveTimeFor: rec in: sortedBoundaries.
			(ts notNil and: [self inWindow: ts]) ifTrue: [
				date := ts date.
				yNode := self childNamed: date year kind: #year
					label: date year printString under: root index: index.
				mNode := self childNamed: (date year * 100 + date monthIndex) kind: #month
					label: (date monthName, ' ', date year printString) under: yNode index: index.
				wNode := self childNamed: (self weekLabelFor: date) kind: #week
					label: (self weekLabelFor: date) under: mNode index: index.
				dNode := self childNamed: date mmddyyyy kind: #day
					label: (date weekday, ' ', date mmddyyyy) under: wNode index: index.
				saveNode := self saveNodeFor: rec in: sortedBoundaries cache: saveCache.
				sNode := self childNamed: saveNode kind: #save
					label: saveNode label under: dNode index: index.
				leaf := self leafFor: rec at: ts.
				"A removal's diff baseline is the removed method's last known body."
				leaf changeType == #methodRemoval ifTrue: [
					recKey ifNotNil: [
						leaf priorSource: (lastSourceByKey at: recKey ifAbsent: [nil])]].
				baseClass := self baseClassNameFrom: leaf methodClassName.
				leafParent := baseClass
					ifNil: [
						self childNamed: '(doIts)' kind: #package
							label: '(doIts)' under: sNode index: index]
					ifNotNil: [:bc | | classNode |
						pkgName := self packageNameForClassNamed: bc.
						pNode := self childNamed: pkgName kind: #package
							label: pkgName under: sNode index: index.
						classNode := self childNamed: bc kind: #class
							label: bc under: pNode index: index.
						classNode].
				self attachLeaf: leaf under: leafParent.
				key := leaf crossRefKey.
				key ifNotNil: [
					(lastLeafByKey at: key ifAbsent: [nil]) ifNotNil: [:prev |
						prev markSuperseded.
						leaf prevInScope: prev].
					lastLeafByKey at: key put: leaf].
				kept := kept + 1]]].
	root children isEmpty ifTrue: [
		root label: aLabel, '  (no changes in interval)'].
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:54'
}
SWAChangeParser >> buildTreeTailBytes: nBytesOrNil rootLabel: aLabel [
	"Full pipeline: pick a scan region (tail nBytes, or whole file if nil), scan
	boundaries + records, then bucket into the time tree scoped to [fromTime,toTime]."
	| sz start bnds recs |
	sz := (FileStream readOnlyFileNamed: self fileName) size.
	start := self scanStartForTailBytes: nBytesOrNil.
	bnds := self scanBoundariesFrom: start to: sz.
	recs := self scanRecordsFrom: start to: sz.
	^ self buildTreeFromRecords: recs boundaries: bnds rootLabel: aLabel
]

{
	#category : #recovery,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:37'
}
SWAChangeParser >> changeSignatureFor: aRecord [
	"A comparison key identifying a change's content: 'Class>>selector' plus the
	trimmed source. Two records with the same signature are the SAME change; a
	foreign change absent from this set is one the other file lacks. Answer nil for
	records we don't diff (boundary noise)."
	| key src |
	(self isNoiseRecord: aRecord) ifTrue: [^ nil].
	key := self keyForRecord: aRecord.
	src := ([aRecord string] on: Error do: [:e | '']) ifNil: [''].
	^ (key ifNil: [aRecord type asString]), '||', src withBlanksTrimmed
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:53'
}
SWAChangeParser >> childNamed: aKey kind: aKind label: aLabel under: aParentNode index: anIndexDict [
	"Find-or-create a child SWAChangeNode of aParentNode identified by aKey among
	the parent's children. anIndexDict maps (parentNode -> (key -> childNode))."
	| perParent |
	perParent := anIndexDict at: aParentNode ifAbsentPut: [Dictionary new].
	^ perParent at: aKey ifAbsentPut: [| child kids |
		child := SWAChangeNode new kind: aKind; label: aLabel; yourself.
		kids := aParentNode children asOrderedCollection.
		kids add: child.
		aParentNode children: kids.
		child]
]

{
	#category : #recovery,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:37'
}
SWAChangeParser >> chunkAlignedStartBefore: aPosition [
	"Back up from aPosition to just after the previous chunk terminator ('!') so a
	scan started here begins on a clean chunk boundary (never mid-chunk)."
	| f start |
	aPosition <= 0 ifTrue: [^ 0].
	f := FileStream readOnlyFileNamed: self fileName.
	start := 0.
	[| p |
	 p := aPosition.
	 [p > 0 and: [f position: p - 1. f next ~= $!]] whileTrue: [p := p - 1].
	 start := p] ensure: [f close].
	^ start
]

{
	#category : #recovery,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:40'
}
SWAChangeParser >> commonPrefixLengthWith: otherFileName [
	"Byte position up to which this parser's file and otherFileName are identical.
	Changes files are append-only, so two files sharing history are byte-identical
	for a long common prefix and diverge near the end. Compared in blocks; answer
	the first differing byte position (0-based length of the identical prefix)."
	| f g blockSize limit pos result |
	blockSize := 65536.
	f := FileStream readOnlyFileNamed: self fileName.
	g := FileStream readOnlyFileNamed: otherFileName.
	pos := 0.
	result := nil.
	[limit := f size min: g size.
	 [result isNil and: [pos < limit]] whileTrue: [| n fa ga |
		n := blockSize min: (limit - pos).
		f position: pos. g position: pos.
		fa := f next: n. ga := g next: n.
		fa = ga
			ifTrue: [pos := pos + n]
			ifFalse: [
				1 to: n do: [:i |
					(result isNil and: [(fa at: i) ~= (ga at: i)])
						ifTrue: [result := pos + i - 1]]]]]
		ensure: [f close. g close].
	^ result ifNil: [pos]
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:52'
}
SWAChangeParser >> effectiveTimeFor: aRecord in: sortedBoundaries [
	"aRecord's own stamp when it has a usable one, else the enclosing save
	boundary's time. Answer nil if neither is available."
	| ts |
	(aRecord stamp notNil and: [aRecord stamp notEmpty]) ifTrue: [
		ts := aRecord timeStamp.
		(ts notNil and: [ts asSeconds > 0]) ifTrue: [^ ts]].
	^ self boundaryTimeFor: aRecord in: sortedBoundaries
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:50'
}
SWAChangeParser >> fileName [
	^ fileName ifNil: [fileName := Smalltalk changesName]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:50'
}
SWAChangeParser >> fileName: aFileName [
	fileName := aFileName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:53'
}
SWAChangeParser >> fromTime: aStartTimeStampOrNil to: anEndTimeStampOrNil [
	fromTime := aStartTimeStampOrNil.
	toTime := anEndTimeStampOrNil
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:53'
}
SWAChangeParser >> inWindow: aTimeStamp [
	"Is aTimeStamp within [fromTime, toTime]? An unset bound is open."
	(fromTime notNil and: [aTimeStamp < fromTime]) ifTrue: [^ false].
	(toTime notNil and: [aTimeStamp > toTime]) ifTrue: [^ false].
	^ true
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:17'
}
SWAChangeParser >> isNoiseRecord: aRecord [
	"True for records that carry no real change: the ----SNAPSHOT----/----QUIT----/
	----STARTUP---- boundary lines the ChangeList scanner captures as #misc chunks.
	Those are already represented as #save nodes, so they must not appear as leaves."
	| src |
	src := [aRecord string] on: Error do: [:e | ''].
	src ifNil: [^ true].
	^ src withBlanksTrimmed beginsWith: '----'
]

{
	#category : #grouping,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:20'
}
SWAChangeParser >> keyForRecord: aRecord [
	"The 'ClassName>>selector' key for a method/removal record, or nil otherwise.
	Uses the base (instance-side) class name so a metaclass change shares the key
	of its base -- matching SWAChangeNode>>crossRefKey."
	| cls sel base |
	((aRecord type == #method) or: [aRecord type == #methodRemoval]) ifFalse: [^ nil].
	cls := [aRecord methodClassName] on: Error do: [:e | nil].
	sel := [aRecord methodSelector] on: Error do: [:e | nil].
	(cls isNil or: [sel isNil]) ifTrue: [^ nil].
	base := self baseClassNameFrom: cls.
	^ base, '>>', sel asString
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:16'
}
SWAChangeParser >> leafFor: aRecord at: aTimeStamp [
	"Build a #change leaf node from a ChangeRecord. The label is the LOCAL name only
	(e.g. the bare selector) -- the enclosing class and package are already shown as
	parent tiles. Identity for cross-ref/diff/browse comes from methodClassName /
	methodSelector, NOT the label, so shortening the label is safe."
	| node cls sel src typ lbl auth stampStr prior selStr |
	typ := aRecord type.
	cls := [aRecord methodClassName] on: Error do: [:e | nil].
	sel := [aRecord methodSelector] on: Error do: [:e | nil].
	src := [aRecord string] on: Error do: [:e | ''].
	stampStr := [aRecord stamp] on: Error do: [:e | nil].
	auth := (stampStr notNil and: [stampStr notEmpty])
		ifTrue: [(stampStr findTokens: ' ') ifEmpty: [nil] ifNotEmpty: [:t | t first]]
		ifFalse: [nil].
	prior := self priorSourceFor: aRecord.
	selStr := (sel ifNil: ['?']) asString.
	lbl := typ caseOf: {
		[#method] -> [selStr].
		[#methodRemoval] -> ['- ', selStr].
		[#classDefinition] -> ['(definition)'].
		[#classComment] -> ['(comment)'].
		[#doIt] -> ['doIt: ', ((src ifNil: ['']) copyReplaceAll: (String with: Character cr) with: ' ') truncateWithElipsisTo: 48].
	} otherwise: [selStr].
	node := SWAChangeNode new
		kind: #change;
		changeType: typ;
		methodClassName: (cls ifNotNil: [:c | c asString]);
		methodSelector: sel;
		sourceText: src;
		priorSource: prior;
		timeStamp: aTimeStamp;
		author: auth;
		label: lbl;
		yourself.
	^ node
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 12:04'
}
SWAChangeParser >> openTreemapForRoot: aRootNode [
	"Open a SWAPane-wrapped treemap of a change tree, with the shared
	Back/Browse/Show/Depth/Full chrome and a progress bar over build+layout."
	| treemap overlay panel window total done |
	total := (aRootNode estimatedNodeCount max: 1) * 2.
	treemap := SWAChangeTreemapMorph on: aRootNode.
	treemap extent: 1000 @ 800.
	('Change map: ', aRootNode name)
		displayProgressFrom: 0 to: total during: [:bar |
			bar value: 'Building nodes...'.
			done := 0.
			aRootNode prewarmDo: [:n |
				done := done + 1.
				(done \\ 64 = 0) ifTrue: [bar value: done]].
			bar value: 'Laying out treemap...'.
			treemap layoutProgress: [:n |
				done := done + 1.
				(done \\ 64 = 0) ifTrue: [bar value: (done min: total)]].
			treemap ensureLayout.
			treemap layoutProgress: nil.
			bar value: total].
	overlay := SWAChangeTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.
	panel := SWAPane on: treemap.
	window := panel openInWindow.
	window setLabel: 'Change Treemap: ', aRootNode name.
	panel enforceMinimumWindowWidth.
	window extent: 1000 @ 800.
	^ window
]

{
	#category : #grouping,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 15:05'
}
SWAChangeParser >> packageNameForClassNamed: aBaseClassNameOrNil [
	"The class's current category in the image (used as its package). Answer
	'Unpackaged' for classes the image no longer knows."
	| cat |
	aBaseClassNameOrNil ifNil: [^ 'Unpackaged'].
	cat := SystemOrganization categoryOfElement: aBaseClassNameOrNil asSymbol.
	^ cat ifNil: ['Unpackaged'] ifNotNil: [:c | c asString]
]

{
	#category : #grouping,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:56'
}
SWAChangeParser >> priorSourceFor: aRecord [
	"The source of the version immediately preceding aRecord (a method change), read
	from the sources/changes file via the pointer ChangeRecord>>prior returns.
	Answer nil when there is no prior (a brand-new method) or it can't be read."
	| prior fileIndex pos srcFile |
	aRecord type == #method ifFalse: [^ nil].
	prior := [aRecord prior] on: Error do: [:e | nil].
	(prior isKindOf: Array) ifFalse: [^ nil].
	fileIndex := prior at: 1.
	pos := prior at: 2.
	^ [srcFile := SourceFiles at: fileIndex.
	   srcFile ifNil: [nil] ifNotNil: [
		srcFile position: pos.
		srcFile nextChunk]] on: Error do: [:e | nil]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:53'
}
SWAChangeParser >> saveNodeFor: aRecord in: sortedBoundaries cache: aDict [
	"Answer a shared #save SWAChangeNode for the boundary enclosing aRecord.
	Boundaries are identified by file position; aDict memoizes one node per
	boundary so all records under the same save share it. Records that precede
	every boundary in the scanned region fall under a synthetic 'session' node."
	| pos enclosing |
	pos := aRecord position.
	enclosing := nil.
	sortedBoundaries do: [:assoc |
		assoc key <= pos ifTrue: [enclosing := assoc]].
	enclosing ifNil: [
		^ aDict at: #session ifAbsentPut: [
			SWAChangeNode new kind: #save; label: 'session (start)'; yourself]].
	^ aDict at: enclosing key ifAbsentPut: [
		SWAChangeNode new
			kind: #save;
			timeStamp: enclosing value timeStamp;
			label: enclosing value label;
			yourself]
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:57'
}
SWAChangeParser >> scanBoundariesFrom: startPos to: stopPos [
	"Raw-scan the file region for ----SNAPSHOT----/----QUIT----/----QUIT/NOSAVE----/
	----STARTUP---- markers. Answer a SortedCollection of associations
	(filePosition -> node) sorted by position, each node a fresh #save
	SWAChangeNode carrying the marker's kind and TimeStamp. A change at position P
	belongs to the last boundary whose position <= P.

	A real marker sits at the START of a line (preceded by CR/LF) and is
	immediately followed by a brace payload beginning with a digit (the date),
	e.g. ----SNAPSHOT----{8 July 2026 . 1:02:50 pm}. Both guards reject the false
	positives that arise when a change's own source text mentions the marker
	strings (as this very class's comment does)."
	| f text base result kinds |
	result := OrderedCollection new.
	kinds := #('----SNAPSHOT----' '----QUIT/NOSAVE----' '----QUIT----' '----STARTUP----').
	f := FileStream readOnlyFileNamed: self fileName.
	[f position: startPos.
	 base := startPos.
	 text := f next: (stopPos - startPos)] ensure: [f close].
	kinds do: [:marker | | idx |
		idx := 1.
		[idx := text indexOfSubCollection: marker startingAt: idx.
		 idx > 0] whileTrue: [| after braceEnd stamp node payload atLineStart prev |
			after := idx + marker size.
			atLineStart := idx = 1 or: [
				prev := text at: idx - 1.
				prev = Character cr or: [prev = Character lf]].
			(atLineStart and: [after <= text size and: [(text at: after) = ${]])
				ifTrue: [
					braceEnd := text indexOf: $} startingAt: after.
					(braceEnd > after and: [(text at: after + 1) isDigit]) ifTrue: [
						payload := text copyFrom: after to: braceEnd.
						stamp := self timeStampFromMarker: payload.
						stamp ifNotNil: [
							node := SWAChangeNode new
								kind: #save;
								timeStamp: stamp;
								label: (marker copyReplaceAll: '----' with: ''), ' ',
									stamp asTime print24;
								yourself.
							result add: (base + idx - 1 -> node)]]].
			idx := after]].
	^ result asSortedCollection: [:a :b | a key <= b key]
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:52'
}
SWAChangeParser >> scanRecordsFrom: startPos to: stopPos [
	"Answer the ChangeRecords in the region, using the system ChangeList scanner."
	| cl f |
	cl := ChangeList new.
	f := FileStream readOnlyFileNamed: self fileName.
	[cl scanFile: f from: startPos to: stopPos] ensure: [f close].
	^ cl changeList
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:54'
}
SWAChangeParser >> scanStartForTailBytes: nBytesOrNil [
	"File position to start scanning from. nil scans the whole file; otherwise
	only the last nBytes (enough to cover a recent interval cheaply). We back up
	to the next chunk terminator so we never start mid-chunk."
	| sz start f |
	sz := (FileStream readOnlyFileNamed: self fileName) size.
	nBytesOrNil ifNil: [^ 0].
	start := 0 max: sz - nBytesOrNil.
	start = 0 ifTrue: [^ 0].
	"Advance to just after the next '! ' terminator so scanning starts clean."
	f := FileStream readOnlyFileNamed: self fileName.
	[f position: start.
	 [f atEnd not and: [f peek ~= $!]] whileTrue: [f next].
	 f atEnd ifFalse: [f next].
	 start := f position] ensure: [f close].
	^ start
]

{
	#category : #recovery,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:37'
}
SWAChangeParser >> signaturesFrom: startPos to: stopPos [
	"Set of change signatures for the records in this parser's file in [start,stop]."
	| set |
	set := Set new.
	(self scanRecordsFrom: startPos to: stopPos) do: [:rec |
		(self changeSignatureFor: rec) ifNotNil: [:sig | set add: sig]].
	^ set
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:51'
}
SWAChangeParser >> timeStampFromMarker: aString [
	"Parse the {8 July 2026 . 1:02:50 pm} payload of a boundary marker into a
	TimeStamp. Answer nil if it cannot be parsed."
	| inner |
	inner := aString copyReplaceAll: ' . ' with: ' '.
	inner := (inner copyWithout: ${) copyWithout: $}.
	^ [TimeStamp fromString: inner withBlanksTrimmed]
		on: Error do: [:e | nil]
]

{
	#category : #public,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:54'
}
SWAChangeParser >> treeForLastDays: nDays [
	"Build a time tree of the changes made in the last nDays. The scan region is a
	tail of the file sized to comfortably cover the interval; the time window is
	enforced exactly by [fromTime, toTime]."
	| now start tailBytes |
	now := TimeStamp now.
	start := TimeStamp fromSeconds: now asSeconds - (nDays * 24 * 60 * 60).
	self fromTime: start to: nil.
	"~2 MB per day is a very generous upper bound for interactive images."
	tailBytes := (nDays + 1) * 3000000.
	^ self buildTreeTailBytes: tailBytes
		rootLabel: 'Changes: last ', nDays printString, ' days'
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:53'
}
SWAChangeParser >> weekLabelFor: aDate [
	"A label for the ISO-ish week containing aDate: the Monday that starts it."
	| monday |
	monday := aDate subtractDays: (aDate weekdayIndex - 2 \\ 7).
	^ 'Week of ', monday mmddyyyy
]
