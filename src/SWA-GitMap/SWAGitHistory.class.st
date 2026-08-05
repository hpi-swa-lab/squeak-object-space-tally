"
Builds a SWAGitNode tree out of a GitS repository's commit history -- the git
counterpart of SWAChangeParser (which reads the image's own .changes file).

	SWAGitHistory openLastCommits: 40.
	(SWAGitHistory onWorkingCopyNamed: 'squeak-object-space-tally')
		treeForLastCommits: 40.

How it works. GitS already knows how to turn a pair of commits into Monticello
patch operations: GSGitWorkingCopy>>changeSetsFromCommit:toCommit: answers
GSChangeSets whose GSCodeChanges each carry an MCAddition / MCModification /
MCRemoval over an MCMethodDefinition, MCClassDefinition or MCOrganizationDefinition,
plus the owning MCPackage. So for every commit we diff it against its FIRST PARENT
and get exactly the set of method-level edits that commit introduced -- no text
parsing, no shelling out to git.

That yields the tree

	root -> month -> day -> commit -> package -> class -> change

with a leaf per changed method. Leaf weight is DIFF SIZE (changed lines), inherited
from SWAChangeNode: a modification diffs against MCModification>>obsoletion (the
exact parent-commit body), an addition weighs its whole body, a removal weighs the
body it deleted. So a tile's area is how much that commit actually rewrote.

Cost is roughly 50 ms per commit (the diff walks two git trees), so the openers put
a progress bar over the scan and #maxCommits defaults to 50.

Merge commits are diffed against their first parent only, i.e. the map shows what a
merge brought in relative to the branch it landed on -- the same convention as
`git log --first-parent -p`.
"
Class {
	#name : #SWAGitHistory,
	#superclass : #Object,
	#instVars : [
		'workingCopy',
		'commits',
		'maxCommits',
		'sinceDate',
		'packagePattern',
		'rootLabel'
	],
	#category : #'SWA-GitMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #repositories,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> chooseWorkingCopy [
	"Ask which repository to map. Answers nil if cancelled, and skips the question
	entirely when there is only one."
	| wcs names index |
	wcs := self workingCopies asArray.
	wcs isEmpty ifTrue: [
		self inform: 'No git working copies open in this image.
Open one from the Git Browser first.'.
		^ nil].
	wcs size = 1 ifTrue: [^ wcs first].
	names := wcs collect: [:wc | [wc name] on: Error do: [:e | '?']].
	index := UIManager default chooseFrom: names title: 'Which repository?'.
	^ index = 0 ifTrue: [nil] ifFalse: [wcs at: index]
]

{
	#category : #defaults,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory class >> defaultMaxCommits [
	"How many commits back the openers scan by default. Each commit costs a
	two-tree git diff (~50 ms here), so this is a time budget, not a limit of the
	tool -- pass an explicit count to go deeper."
	^ 50
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:03'
}
SWAGitHistory class >> initialize [
	"Register the Apps-menu entry for the git map, alongside the other SWA tools.
	Idempotent: removes any prior entry for this receiver first.

		SWAGitHistory initialize"
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Git Map'.
		{self. #open}.
		'Open a treemap of a git repository''s commit history' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> on: aGSGitWorkingCopy [
	^ self new workingCopy: aGSGitWorkingCopy; yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> onWorkingCopyNamed: aString [
	"	SWAGitHistory onWorkingCopyNamed: 'squeak-object-space-tally'	"
	^ self on: (self workingCopies
		detect: [:wc | ([wc name] on: Error do: [:e | nil]) = aString]
		ifNone: [self error: 'no git working copy named ', aString printString])
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> open [
	"World-menu entry: ask for the repository and how far back, then map it."
	| wc n |
	wc := self chooseWorkingCopy ifNil: [^ nil].
	n := UIManager default
		request: 'How many commits back from HEAD?'
		initialAnswer: self defaultMaxCommits printString.
	(n isNil or: [n isEmpty]) ifTrue: [^ nil].
	^ (self on: wc) maxCommits: n asInteger; open
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> openLastCommits: n [
	"Map the last n commits of a repository (asking which one if several are open).

		SWAGitHistory openLastCommits: 40."
	| wc |
	wc := self chooseWorkingCopy ifNil: [^ nil].
	^ (self on: wc) maxCommits: n; open
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> openLastDays: nDays [
	"Map every commit authored in the last nDays (still capped by
	#defaultMaxCommits worth of scanning, so a very busy week stays openable)."
	| wc |
	wc := self chooseWorkingCopy ifNil: [^ nil].
	^ (self on: wc)
		sinceDate: (Date today subtractDays: nDays);
		maxCommits: (self defaultMaxCommits max: 200);
		open
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> openOn: aGSGitWorkingCopy lastCommits: n [
	^ (self on: aGSGitWorkingCopy) maxCommits: n; open
]

{
	#category : #repositories,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory class >> workingCopies [
	"Every GitS working copy this image knows about, name-sorted. These are live
	objects, not a registry read -- GSGitWorkingCopy instances ARE the repositories
	the image has open."
	^ (GSGitWorkingCopy allInstances
		select: [:wc | [wc repositoryExists] on: Error do: [:e | false]])
		asSortedCollection: [:a :b |
			([a name] on: Error do: [:e | '?']) <= ([b name] on: Error do: [:e | '?'])]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitHistory >> addCommit: aCommit to: aRootNode index: anIndexDict lastLeaves: lastLeafByKey [
	"Bucket one commit's code changes into  month -> day -> commit -> package ->
	class -> change  under aRootNode. Commits that touched no mapped code (or
	nothing matching the package filter) contribute no tile at all.

	Because commits arrive oldest-first, lastLeafByKey lets each leaf point back at
	the previous change to the SAME method inside the window (#prevInScope, for
	navigation) and flag that older leaf as #superseded -- so the status colouring
	shows at a glance which changes were later overwritten."
	| ts date monthNode dayNode commitNode changes |
	changes := (self codeChangesForCommit: aCommit) select: [:ch |
		self matchesPackageFilter: ([ch package name asString] on: Error do: [:e | nil])].
	changes isEmpty ifTrue: [^ self].
	ts := self timeStampOf: aCommit.
	date := ts asDate.
	monthNode := self childNamed: date year * 100 + date monthIndex kind: #month
		label: date monthName, ' ', date year printString
		under: aRootNode index: anIndexDict at: ts.
	dayNode := self childNamed: date mmddyyyy kind: #day
		label: date weekday, ' ', date mmddyyyy
		under: monthNode index: anIndexDict at: ts.
	commitNode := self childNamed: ([aCommit hexHash] on: Error do: [:e | aCommit hash]) kind: #commit
		label: (self commitLabelFor: aCommit)
		under: dayNode index: anIndexDict at: ts.
	commitNode
		commit: aCommit;
		hexHash: ([aCommit hexHash] on: Error do: [:e | nil]);
		commitMessage: (self summaryOf: aCommit);
		author: ([aCommit author name] on: Error do: [:e | nil]).
	changes do: [:ch |
		| leaf packageLabel packageNode className leafParent key |
		leaf := self leafFor: ch commit: aCommit at: ts.
		leaf ifNotNil: [
			packageLabel := leaf packageName ifNil: ['(unpackaged)'].
			packageNode := self childNamed: packageLabel kind: #package label: packageLabel
				under: commitNode index: anIndexDict at: ts.
			className := self baseClassNameFrom: leaf methodClassName.
			leafParent := className
				ifNil: [packageNode]
				ifNotNil: [:cn |
					self childNamed: cn kind: #class label: cn
						under: packageNode index: anIndexDict at: ts].
			self attachLeaf: leaf under: leafParent.
			key := leaf crossRefKey.
			key ifNotNil: [
				(lastLeafByKey at: key ifAbsent: [nil]) ifNotNil: [:prev |
					prev markSuperseded.
					leaf prevInScope: prev].
				lastLeafByKey at: key put: leaf]]]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> attachLeaf: aLeaf under: aParentNode [
	| kids |
	kids := aParentNode children asOrderedCollection.
	kids add: aLeaf.
	aParentNode children: kids
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> baseClassNameFrom: aNameOrNil [
	"Group instance- and class-side changes under ONE class tile: strip a trailing
	' class'. (The leaf keeps the metaclass name, so its crossRefKey stays
	'Foo class>>bar' and still matches the Code Map.)"
	| n |
	aNameOrNil ifNil: [^ nil].
	n := aNameOrNil asString withBlanksTrimmed.
	^ (n endsWith: ' class')
		ifTrue: [(n copyFrom: 1 to: n size - 6) withBlanksTrimmed]
		ifFalse: [n]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:59'
}
SWAGitHistory >> branchName [
	"The checked-out branch, short. GitS namespaces its refs per image
	('refs/squeak/<imageHash>/heads/main'), and #headRefBasename answers the
	literal 'HEAD', so we take the last segment of the symbolic HEAD target."
	| target |
	target := [workingCopy currentSymbolicHeadTarget] on: Error do: [:e | nil].
	target ifNil: [^ 'HEAD'].
	target := target asString.
	^ ((target findTokens: '/') ifEmpty: [#('HEAD')]) last
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitHistory >> buildTree [
	"The root SWAGitNode for the configured window, with a progress bar over the
	commit scan (the expensive part)."
	| list root |
	list := self commitsToScan.
	list isEmpty ifTrue: [^ self buildTreeProgress: nil].
	('Reading ', list size printString, ' commits of ', self rootLabel)
		displayProgressFrom: 0 to: list size during: [:bar |
			root := self buildTreeProgress: [:i :c | bar value: i]].
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitHistory >> buildTreeProgress: aTwoArgBlockOrNil [
	"Scan #commitsToScan and answer the root SWAGitNode. aTwoArgBlockOrNil, if
	given, is sent index and commit before each diff -- diffing a commit costs a
	git tree walk (tens of ms), so the openers use this to drive a progress bar."
	| root index lastLeafByKey list |
	list := self commitsToScan.
	root := SWAGitNode new kind: #root; label: self rootLabel; yourself.
	index := IdentityDictionary new.
	lastLeafByKey := Dictionary new.
	list doWithIndex: [:aCommit :i |
		aTwoArgBlockOrNil ifNotNil: [aTwoArgBlockOrNil value: i value: aCommit].
		self addCommit: aCommit to: root index: index lastLeaves: lastLeafByKey].
	list isEmpty ifFalse: [root timeStamp: (self timeStampOf: list first)].
	root children isEmpty ifTrue: [
		root label: self rootLabel, '  (no code changes in ', list size printString, ' commits)'].
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> childNamed: aKey kind: aKind label: aLabel under: aParentNode index: anIndexDict at: aTimeStamp [
	"Find-or-create a container child of aParentNode identified by aKey.
	anIndexDict maps parentNode -> (key -> childNode), so this is O(1) per lookup
	instead of a scan of the (potentially large) sibling list.

	Containers get a timeStamp on FIRST creation, i.e. the earliest change they
	hold. That is what makes the recency colouring work above the leaf level."
	| perParent |
	perParent := anIndexDict at: aParentNode ifAbsentPut: [Dictionary new].
	^ perParent at: aKey ifAbsentPut: [
		| child kids |
		child := SWAGitNode new kind: aKind; label: aLabel; timeStamp: aTimeStamp; yourself.
		kids := aParentNode children asOrderedCollection.
		kids add: child.
		aParentNode children: kids.
		child]
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> codeChangesForCommit: aCommit [
	"The GSCodeChanges this commit introduced relative to its FIRST parent --
	i.e. what `git log --first-parent -p` would show for it. GitS does the real
	work: it materialises both trees through the code mapper and answers Monticello
	patch operations, so we get method-level granularity for free.

	The root commit (no parents) is diffed against nothing, so its whole tree
	arrives as additions -- correct, but big."
	| parent changeSets |
	changeSets := [
		parent := aCommit parents isEmpty ifTrue: [nil] ifFalse: [aCommit firstParent].
		workingCopy changeSetsFromCommit: parent toCommit: aCommit]
			on: Error do: [:e | ^ #()].
	^ changeSets
		inject: OrderedCollection new
		into: [:acc :cs |
			(cs isKindOf: GSCodeChangeSet)
				ifTrue: [acc addAll: ([cs changes] on: Error do: [:e | #()])].
			acc]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitHistory >> commitLabelFor: aCommit [
	"Tile label for a commit: abbreviated hash + subject line, as in git log --oneline."
	| hash |
	hash := [aCommit hexHash copyFrom: 1 to: 7] on: Error do: [:e | '???????'].
	^ hash, '  ', ((self summaryOf: aCommit) truncateWithElipsisTo: 56)
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> commitsToScan [
	"The commits to diff, OLDEST FIRST. GitCommit>>ancestors answers the
	first-parent-inclusive ancestry newest-first (and includes HEAD itself), so we
	take the window off the front and reverse -- chronological order is what lets
	the builder chain each method's versions and mark superseded ones."
	| anc |
	commits ifNotNil: [^ commits].
	workingCopy ifNil: [^ commits := #()].
	anc := [workingCopy headCommit ancestors] on: Error do: [:e | ^ commits := #()].
	anc ifNil: [^ commits := #()].
	maxCommits ifNotNil: [anc := anc first: (maxCommits min: anc size)].
	sinceDate ifNotNil: [
		anc := anc select: [:c |
			[c author timeStamp asDate >= sinceDate] on: Error do: [:e | true]]].
	^ commits := anc asArray reversed
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> initialize [
	super initialize.
	maxCommits := self class defaultMaxCommits
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> labelPrefixFor: anOperationKind [
	"Diff-style sigil on the tile label so the operation is readable without
	relying on colour: '+' added, '-' removed, nothing for a modification."
	anOperationKind == #added ifTrue: [^ '+ '].
	anOperationKind == #removed ifTrue: [^ '- '].
	^ ''
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> leafFor: aCodeChange commit: aCommit at: aTimeStamp [
	"Turn one GSCodeChange into a #change leaf. Answers nil for a change we cannot
	make sense of (so the caller skips it).

	The three definition kinds map onto the Change Map's vocabulary so the shared
	view keeps working: a method becomes #method (or #methodRemoval when deleted),
	a class definition becomes #classDefinition, a category reshuffle #organization.

	priorSource is the diff BASELINE and is where git beats the changes file: a
	modification carries MCModification>>obsoletion, the byte-exact body as of the
	parent commit."
	| op defn opKind changeType src prior clsName sel label |
	op := [aCodeChange operation] on: Error do: [:e | nil].
	op ifNil: [^ nil].
	defn := [op definition] on: Error do: [:e | nil].
	defn ifNil: [^ nil].
	opKind := self operationKindOf: op.
	prior := opKind == #modified
		ifTrue: [self sourceOf: ([op obsoletion] on: Error do: [:e | nil])]
		ifFalse: [nil].
	(defn isKindOf: MCMethodDefinition)
		ifTrue: [
			clsName := [defn fullClassName asString] on: Error do: [:e | defn className asString].
			sel := [defn selector] on: Error do: [:e | nil].
			changeType := opKind == #removed ifTrue: [#methodRemoval] ifFalse: [#method].
			src := opKind == #removed ifTrue: [nil] ifFalse: [self sourceOf: defn].
			opKind == #removed ifTrue: [prior := self sourceOf: defn].
			label := (self labelPrefixFor: opKind), (sel ifNil: ['?']) asString]
		ifFalse: [
			(defn isKindOf: MCClassDefinition)
				ifTrue: [
					clsName := [defn className asString] on: Error do: [:e | nil].
					sel := nil.
					changeType := #classDefinition.
					src := opKind == #removed ifTrue: [nil] ifFalse: [self sourceOf: defn].
					opKind == #removed ifTrue: [prior := self sourceOf: defn].
					label := (self labelPrefixFor: opKind), '(class definition)']
				ifFalse: [
					clsName := nil.
					sel := nil.
					changeType := #organization.
					src := self sourceOf: defn.
					label := (self labelPrefixFor: opKind), '(organization)']].
	^ SWAGitNode new
		kind: #change;
		changeType: changeType;
		operationKind: opKind;
		methodClassName: clsName;
		methodSelector: sel;
		sourceText: src;
		priorSource: prior;
		timeStamp: aTimeStamp;
		author: ([aCommit author name] on: Error do: [:e | nil]);
		commit: aCommit;
		hexHash: ([aCommit hexHash] on: Error do: [:e | nil]);
		commitMessage: (self summaryOf: aCommit);
		packageName: ([aCodeChange package name asString] on: Error do: [:e | nil]);
		label: label;
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> matchesPackageFilter: aPackageNameOrNil [
	packagePattern ifNil: [^ true].
	aPackageNameOrNil ifNil: [^ false].
	^ packagePattern match: aPackageNameOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> maxCommits [
	^ maxCommits
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:00'
}
SWAGitHistory >> maxCommits: anIntegerOrNil [
	"How many commits back from HEAD to scan; nil = all of them.
	Invalidates the cached commit window."
	maxCommits := anIntegerOrNil.
	commits := nil
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory >> open [
	"Build the configured window and open it."
	^ self openTreemapForRoot: self buildTree
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:58'
}
SWAGitHistory >> openTreemapForRoot: aRootNode [
	"Open a SWAPane-wrapped git treemap, with a progress bar over node prewarm and
	layout (the tree itself is already built at this point)."
	| treemap panel window total done |
	total := (aRootNode estimatedNodeCount max: 1) * 2.
	treemap := SWAGitTreemapMorph on: aRootNode.
	treemap workingCopy: workingCopy.
	treemap extent: 1000 @ 800.
	('Git map: ', aRootNode name)
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
	panel := SWAPane on: treemap.
	panel wireOverlayFor: treemap.
	window := panel openInWindow.
	window setLabel: 'Git Map: ', aRootNode name.
	panel enforceMinimumWindowWidth.
	window extent: 1000 @ 800.
	^ window
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> operationKindOf: anMCPatchOperation [
	"#added / #modified / #removed for a Monticello patch operation."
	(anMCPatchOperation isKindOf: MCAddition) ifTrue: [^ #added].
	(anMCPatchOperation isKindOf: MCRemoval) ifTrue: [^ #removed].
	^ #modified
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> packagePattern: aStringOrNil [
	"Keep only changes whose Monticello package name matches this glob
	(e.g. 'SWA-*'). nil = every package in the repository."
	packagePattern := aStringOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:59'
}
SWAGitHistory >> rootLabel [
	rootLabel ifNotNil: [^ rootLabel].
	workingCopy ifNil: [^ 'git'].
	^ ([workingCopy name] on: Error do: [:e | 'git'])
		, ([' @ ', self branchName] on: Error do: [:e | ''])
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> rootLabel: aString [
	rootLabel := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:00'
}
SWAGitHistory >> sinceDate: aDateOrNil [
	"Ignore commits authored before aDate. Combines with #maxCommits (both apply)."
	sinceDate := aDateOrNil.
	commits := nil
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> sourceOf: aDefinitionOrNil [
	"Source text of any Monticello definition, guarded. MCMethodDefinition answers
	the method body; GitS adds #source to the class and organization definitions
	too, with #definitionString as the older fallback."
	aDefinitionOrNil ifNil: [^ nil].
	^ [aDefinitionOrNil source asString]
		on: Error do: [:e |
			[aDefinitionOrNil definitionString asString] on: Error do: [:e2 | nil]]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> summaryOf: aCommit [
	"The commit's subject line (first line of the message), never nil."
	| msg |
	msg := [aCommit message] on: Error do: [:e | nil].
	msg ifNil: [^ ''].
	^ (msg lines ifEmpty: [#('')]) first withBlanksTrimmed
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:55'
}
SWAGitHistory >> timeStampOf: aCommit [
	"The commit's AUTHOR time as a TimeStamp (author, not committer: a rebase
	rewrites the committer date but keeps the moment the work was done)."
	^ [aCommit author timeStamp asTimeStamp] on: Error do: [:e | TimeStamp now]
]

{
	#category : #public,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:56'
}
SWAGitHistory >> treeForLastCommits: n [
	"	(SWAGitHistory onWorkingCopyNamed: 'squeak-object-space-tally')
			treeForLastCommits: 40	"
	self maxCommits: n.
	commits := nil.
	^ self buildTree
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> workingCopy [
	^ workingCopy
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 10:54'
}
SWAGitHistory >> workingCopy: aGSGitWorkingCopy [
	workingCopy := aGSGitWorkingCopy
]
