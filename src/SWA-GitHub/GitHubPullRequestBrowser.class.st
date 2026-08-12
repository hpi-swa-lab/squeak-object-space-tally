Class {
	#name : #GitHubPullRequestBrowser,
	#superclass : #Model,
	#instVars : [
		'pullRequestUrl',
		'commentTexts',
		'selectedCommentIndex',
		'api',
		'savedScrollOffset',
		'commentsScrollPane'
	],
	#category : #'SWA-GitHub'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser class >> open [

	^ ToolBuilder open: self new
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubPullRequestBrowser class >> openForPullRequestUrl: aUrlString api: aGitHubAPI [

	| browser |
	browser := self new.
	aGitHubAPI ifNotNil: [browser api: aGitHubAPI].
	browser pullRequestUrl: aUrlString.
	ToolBuilder open: browser.
	browser loadPullRequest.
	^ browser
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:13'
}
GitHubPullRequestBrowser >> api: aGitHubAPI [

	api := aGitHubAPI
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubPullRequestBrowser >> authenticate [

	GitHubAPI requestAuthToken
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:50'
}
GitHubPullRequestBrowser >> authorForComment: comment [

	| user |
	user := comment at: 'user' ifAbsent: [^ 'unknown'].
	^ user at: 'login' ifAbsent: ['unknown']
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubPullRequestBrowser >> buildAuthenticateButtonWith: builder [

	^ builder pluggableButtonSpec new
		model: self;
		label: 'Authenticate';
		help: 'Store a GitHub API token in this image. Without one, resolved conversations cannot be read.';
		action: #authenticate;
		frame: (0.8 @ 0 corner: 1 @ 0.12);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:06'
}
GitHubPullRequestBrowser >> buildCommentButtonFor: aCommentEntry with: builder [

	^ builder pluggableButtonSpec new
		model: aCommentEntry;
		label: #commentLabel;
		action: #addComment;
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:34'
}
GitHubPullRequestBrowser >> buildCommentChildrenFor: aCommentEntry with: builder [

	| children buttonSpecs |
	children := OrderedCollection with: (self buildCommentTextFor: aCommentEntry with: builder).
	buttonSpecs := OrderedCollection new.
	aCommentEntry hasButton ifTrue: [
		buttonSpecs add: (self buildOpenTargetButtonFor: aCommentEntry with: builder)].
	"Web browser button disabled: no WebBrowser implementation available in this image."
	"aCommentEntry hasHtmlUrl ifTrue: [
		buttonSpecs add: (self buildOpenInBrowserButtonFor: aCommentEntry with: builder)]."
	aCommentEntry hasHtmlUrl ifTrue: [
		buttonSpecs add: (self buildCopyLinkButtonFor: aCommentEntry with: builder)].
	aCommentEntry canComment ifTrue: [
		buttonSpecs add: (self buildCommentButtonFor: aCommentEntry with: builder)].
	aCommentEntry canResolve ifTrue: [
		buttonSpecs add: (self buildResolveButtonFor: aCommentEntry with: builder)].
	buttonSpecs isEmpty ifFalse: [
		children add: (builder pluggablePanelSpec new
			children: buttonSpecs asArray;
			layout: #horizontal;
			yourself)].
	^ children asArray
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:45'
}
GitHubPullRequestBrowser >> buildCommentPaneFor: aCommentEntry with: builder [

	^ builder pluggablePanelSpec new
		children: (self buildCommentChildrenFor: aCommentEntry with: builder);
		layout: #vertical;
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 21:45'
}
GitHubPullRequestBrowser >> buildCommentPanesWith: builder [

	commentTexts isEmpty ifTrue: [^ {self buildNoCommentsPaneWith: builder}].
	^ commentTexts collect: [:each | self buildCommentPaneFor: each with: builder]
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> buildCommentTextFor: aCommentEntry with: builder [

	^ (GSGUIUtilities buildShrinkWrapText: aCommentEntry text with: builder)
		readOnly: true;
		indicateUnacceptedChanges: false;
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 17:54'
}
GitHubPullRequestBrowser >> buildComments: builder [

	| scrollPane |
	scrollPane := builder build: (builder pluggableScrollPaneSpec new
		children: (self buildCommentPanesWith: builder);
		name: #children;
		yourself).
	scrollPane scroller layoutPolicy: TableLayout new.
	scrollPane scroller firstSubmorph
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellGap: 12;
		hResizing: #spaceFill;
		vResizing: #spaceFill.
	scrollPane
		color: Color transparent;
		borderWidth: 0.
	(scrollPane allMorphs select: [:each | each isKindOf: PluggableButtonMorph])
		do: [:button |
			button
				hResizing: #spaceFill;
				vResizing: #rigid;
				height: 28].
	scrollPane layoutChanged.
	commentsScrollPane := scrollPane.
	savedScrollOffset ifNotNil: [:offset |
		Project current addDeferredUIMessage: [
			self restoreScrollOf: scrollPane to: offset]].
	^ scrollPane
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:04'
}
GitHubPullRequestBrowser >> buildCopyLinkButtonFor: aCommentEntry with: builder [

	^ builder pluggableButtonSpec new
		model: aCommentEntry;
		label: #copyLinkLabel;
		action: #copyLink;
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 21:45'
}
GitHubPullRequestBrowser >> buildDynamicCommentsPanelWith: builder [

	| dynamicPanel |
	dynamicPanel := GSDynamicallyBuilt new
		model: self;
		buildSelector: #buildComments:;
		builder: builder;
		build.
	dynamicPanel frame: (0 @ 0.12 corner: 1 @ 1).
	^ dynamicPanel
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubPullRequestBrowser >> buildLoadButtonWith: builder [

	^ builder pluggableButtonSpec new
		model: self;
		label: 'Load';
		action: #loadPullRequest;
		frame: (0.68 @ 0 corner: 0.8 @ 0.12);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> buildNoCommentsPaneWith: builder [

	| entry |
	entry := GitHubPullRequestCommentEntry new.
	entry text: 'No comments loaded.' asText.
	^ self buildCommentPaneFor: entry with: builder
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:58'
}
GitHubPullRequestBrowser >> buildOpenInBrowserButtonFor: aCommentEntry with: builder [

	^ builder pluggableButtonSpec new
		model: aCommentEntry;
		label: #openInBrowserLabel;
		action: #openInBrowser;
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:45'
}
GitHubPullRequestBrowser >> buildOpenTargetButtonFor: aCommentEntry with: builder [

	^ builder pluggableButtonSpec new
		model: aCommentEntry;
		label: #buttonLabel;
		action: #openTarget;
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubPullRequestBrowser >> buildPullRequestUrlInputWith: builder [

	^ builder pluggableInputFieldSpec new
		model: self;
		getText: #pullRequestUrl;
		editText: #pullRequestUrl:;
		setText: #pullRequestUrl:;
		help: 'Pull request URL';
		frame: (0 @ 0 corner: 0.68 @ 0.12);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:34'
}
GitHubPullRequestBrowser >> buildResolveButtonFor: aCommentEntry with: builder [

	^ builder pluggableButtonSpec new
		model: aCommentEntry;
		label: #resolveLabel;
		action: #resolveConversation;
		yourself
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:35'
}
GitHubPullRequestBrowser >> buildTargetsByCommentIdFrom: comments owner: owner repository: repository [

	| groupedByPathAndCommit targetsById |
	groupedByPathAndCommit := Dictionary new.
	targetsById := Dictionary new.
	comments do: [:each |
		| path commitId key |
		path := self commentPathFor: each.
		commitId := self commentCommitIdFor: each.
		(path notNil and: [commitId notNil]) ifTrue: [
			key := {path. commitId}.
			(groupedByPathAndCommit at: key ifAbsentPut: [OrderedCollection new]) add: each]].
	UIManager default informUser: 'Resolving comment targets' during: [
		groupedByPathAndCommit associations
			do: [:association |
				| path commitId group fileContent |
				path := association key first.
				commitId := association key second.
				group := association value.
				[
					fileContent := api
						fileContentForOwner: owner
						repository: repository
						path: path
						ref: commitId.
					group do: [:comment |
						targetsById
							at: (comment at: 'id')
							put: (self targetForComment: comment inFileContent: fileContent)]
				] on: Error do: [:ex |
					group do: [:comment |
						targetsById at: (comment at: 'id') put: nil]]]
			displayingProgress: [:association | association key first, ' @ ', (association key second copyFrom: 1 to: ((association key second size) min: 8))]].
	^ targetsById
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubPullRequestBrowser >> buildWindow: builder [

	| windowSpec |
	windowSpec := builder pluggableWindowSpec new
		model: self;
		label: #windowTitle;
		children: OrderedCollection new;
		yourself.
	windowSpec children add: (self buildPullRequestUrlInputWith: builder).
	windowSpec children add: (self buildLoadButtonWith: builder).
	windowSpec children add: (self buildAuthenticateButtonWith: builder).
	windowSpec children add: (self buildDynamicCommentsPanelWith: builder).
	^ windowSpec
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> buildWith: builder [

	^ builder build: (self buildWindow: builder)
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> buttonActionForTarget: target [

	(target first = #method) ifTrue: [
		^ [StandardToolSet browse: target third selector: target fourth]].
	(target first = #class) ifTrue: [
		^ [StandardToolSet browseClass: target third]].
	^ nil
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> buttonLabelForTarget: target [

	(target first = #method) ifTrue: [
		^ 'Open method ', target second, '>>', target fourth asString].
	(target first = #class) ifTrue: [
		^ 'Open class ', target second].
	^ ''
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> classNameFromDefinitionLines: lines [

	| prefix |
	prefix := '#name : #'.
	lines do: [:line |
		| trimmed startIndex rest name |
		trimmed := line withBlanksTrimmed.
		startIndex := trimmed findString: prefix startingAt: 1.
		startIndex > 0 ifTrue: [
			rest := trimmed copyFrom: startIndex + prefix size to: trimmed size.
			name := (rest copyUpTo: $,) withBlanksTrimmed.
			name notEmpty ifTrue: [^ name]]].
	^ nil
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> classTargetFromDefinitionLines: lines [

	| className classObject |
	(lines first withBlanksTrimmed = 'Class {') ifFalse: [^ nil].
	className := self classNameFromDefinitionLines: lines.
	className ifNil: [^ nil].
	classObject := Smalltalk at: className asSymbol ifAbsent: [^ nil].
	^ {#class. className. classObject}
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:16'
}
GitHubPullRequestBrowser >> coloredDiffHunkText: aString [

	| lines |
	aString isEmpty ifTrue: [^ '' asText].
	lines := aString lines.
	^ GSTextUtilities joinTexts: (lines collect: [:line | self coloredDiffLineText: line])
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:19'
}
GitHubPullRequestBrowser >> coloredDiffLineText: aLine [

	| color |
	color := aLine isEmpty
		ifTrue: [Color gray]
		ifFalse: [
			aLine first = $+
				ifTrue: [Color green muchDarker]
				ifFalse: [
					aLine first = $-
						ifTrue: [Color red darker]
						ifFalse: [Color gray]]].
	^ GSTextUtilities colorText: aLine with: color
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:43'
}
GitHubPullRequestBrowser >> coloredRelevantDiffHunkTextForComment: comment [

	| diffHunk lines parsed relevantLines |
	diffHunk := comment at: 'diff_hunk' ifAbsent: [''].
	diffHunk isEmpty ifTrue: [^ '' asText].
	lines := diffHunk lines.
	lines isEmpty ifTrue: [^ '' asText].
	parsed := self parseDiffHunkHeader: lines first.
	parsed ifNil: [^ self coloredDiffHunkText: diffHunk].
	relevantLines := self
		relevantDiffLinesFrom: lines allButFirst
		forComment: comment
		oldStart: parsed first
		newStart: parsed second.
	relevantLines isEmpty ifTrue: [relevantLines := lines allButFirst].
	^ GSTextUtilities joinTexts: (relevantLines collect: [:line |
		self coloredDiffLineText: line])
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 17:50'
}
GitHubPullRequestBrowser >> commentActionForId: commentId pullRequest: parsed entry: entry [

	^ [:body |
		[
			| reply |
			reply := api
				replyToReviewCommentForOwner: parsed first
				repository: parsed second
				number: parsed third
				commentId: commentId
				body: body.
			entry appendReplyText: (self replyTextForComment: reply).
			self rebuildCommentsKeepingScroll
		] on: Error do: [:ex |
			UIManager default inform: ex messageText]]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> commentCommitIdFor: comment [

	^ comment
		at: 'commit_id'
		ifAbsent: [comment at: 'original_commit_id' ifAbsent: [nil]]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubPullRequestBrowser >> commentEntryFor: comment target: target pullRequest: parsed [

	| entry text replies commentId |
	entry := GitHubPullRequestCommentEntry new.
	text := self displayTextForComment: comment.
	replies := comment at: 'mergedReplies' ifAbsent: [#()].
	replies do: [:reply |
		text := Text streamContents: [:stream |
			stream nextPutAll: text.
			stream cr; cr.
			stream nextPutAll: (self replyTextForComment: reply)]].
	entry text: text.
	entry htmlUrl: (comment at: 'html_url' ifAbsent: [nil]).
	target ifNotNil: [
		entry buttonLabel: (self buttonLabelForTarget: target).
		entry buttonAction: (self buttonActionForTarget: target)].
	commentId := comment at: 'id' ifAbsent: [nil].
	commentId ifNotNil: [
		entry commentAction: (self commentActionForId: commentId pullRequest: parsed entry: entry).
		entry resolveAction: (self resolveActionForId: commentId pullRequest: parsed entry: entry)].
	^ entry
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:43'
}
GitHubPullRequestBrowser >> commentLineNumberFor: comment [

	| lineNumber |
	lineNumber := comment at: 'line' ifAbsent: [nil].
	lineNumber ifNil: [lineNumber := comment at: 'original_line' ifAbsent: [nil]].
	lineNumber ifNil: [lineNumber := comment at: 'start_line' ifAbsent: [nil]].
	lineNumber ifNil: [lineNumber := comment at: 'original_start_line' ifAbsent: [nil]].
	(lineNumber isNumber and: [lineNumber > 0]) ifFalse: [^ nil].
	^ lineNumber
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> commentPathFor: comment [

	^ comment at: 'path' ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> commentTexts [

	^ commentTexts
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:50'
}
GitHubPullRequestBrowser >> displayTextForComment: comment [

	| diffText body author bodyText |
	diffText := self coloredRelevantDiffHunkTextForComment: comment.
	author := self authorForComment: comment.
	body := comment at: 'body' ifAbsent: [''].
	bodyText := (GSTextUtilities bold: author), ': ', body.
	diffText isEmpty ifTrue: [^ bodyText].
	^ Text streamContents: [:stream |
		stream nextPutAll: diffText.
		stream cr; cr.
		stream nextPutAll: bodyText]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:30'
}
GitHubPullRequestBrowser >> firstMethodTargetFrom: lines startingAt: startIndex [

	| lineIndex methodTarget |
	lineIndex := startIndex.
	[lineIndex <= lines size] whileTrue: [
		methodTarget := self methodTargetFromLine: (lines at: lineIndex).
		methodTarget ifNotNil: [^ methodTarget].
		lineIndex := lineIndex + 1].
	^ nil
]

{
	#category : #'initialize-release',
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 21:48'
}
GitHubPullRequestBrowser >> initialize [

	super initialize.
	pullRequestUrl := ''.
	commentTexts := #().
	selectedCommentIndex := 0.
	api := GitHubAPI new.
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:32'
}
GitHubPullRequestBrowser >> loadPullRequest [

	| parsed comments resolvedIds visibleComments rootComments targetsById |
	parsed := self parsePullRequestUrl.
	parsed ifNil: [^ self].
	[
		comments := UIManager default
			informUser: 'Loading pull request comments'
			during: [
				api
					allPullRequestCommentsForOwner: parsed first
					repository: parsed second
					number: parsed third].
		resolvedIds := self resolvedCommentIdsFor: parsed.
		visibleComments := comments reject: [:each |
			resolvedIds includes: (each at: 'id' ifAbsent: [nil])].
		rootComments := self mergeReplies: visibleComments.
		targetsById := self
			buildTargetsByCommentIdFrom: rootComments
			owner: parsed first
			repository: parsed second.
		commentTexts := rootComments collect: [:each |
			self
				commentEntryFor: each
				target: (targetsById at: (each at: 'id') ifAbsent: [nil])
				pullRequest: parsed].
		self changed: #buildComments:
	] on: Error do: [:ex |
		UIManager default inform: ex messageText]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:53'
}
GitHubPullRequestBrowser >> mergeReplies: comments [

	| repliesByRoot roots |
	repliesByRoot := Dictionary new.
	comments do: [:each |
		| replyTo |
		replyTo := each at: 'in_reply_to_id' ifAbsent: [nil].
		replyTo ifNotNil: [
			(repliesByRoot at: replyTo ifAbsentPut: [OrderedCollection new]) add: each]].
	roots := comments reject: [:each | (each at: 'in_reply_to_id' ifAbsent: [nil]) notNil].
	^ roots collect: [:root |
		root at: 'mergedReplies' put: (repliesByRoot at: (root at: 'id') ifAbsent: [#()]).
		root]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:48'
}
GitHubPullRequestBrowser >> methodTargetFromLine: aLine [

	| trimmed index left right selector isClassSide className classObject browseClass labelClassName |
	trimmed := aLine withBlanksTrimmed.
	index := trimmed findString: '>>' startingAt: 1.
	index = 0 ifTrue: [^ nil].
	left := (trimmed copyFrom: 1 to: index - 1) withBlanksTrimmed.
	right := (trimmed copyFrom: index + 2 to: trimmed size) withBlanksTrimmed.
	selector := self selectorFromMethodPattern: (right copyUpTo: $[).
	selector ifNil: [^ nil].
	isClassSide := left endsWith: ' class'.
	className := isClassSide
		ifTrue: [left copyFrom: 1 to: left size - 6]
		ifFalse: [left].
	classObject := Smalltalk at: className asSymbol ifAbsent: [^ nil].
	browseClass := isClassSide ifTrue: [classObject class] ifFalse: [classObject].
	labelClassName := isClassSide ifTrue: [className, ' class'] ifFalse: [className].
	^ {#method. labelClassName. browseClass. selector}
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:43'
}
GitHubPullRequestBrowser >> parseDiffHunkHeader: headerLine [

	| tokens oldToken newToken oldStart newStart |
	tokens := headerLine findTokens: ' '.
	oldToken := tokens
		detect: [:each | each notEmpty and: [each first = $-]]
		ifNone: [^ nil].
	newToken := tokens
		detect: [:each | each notEmpty and: [each first = $+]]
		ifNone: [^ nil].
	oldStart := self startNumberFromDiffToken: oldToken prefix: $-.
	newStart := self startNumberFromDiffToken: newToken prefix: $+.
	(oldStart isNil or: [newStart isNil]) ifTrue: [^ nil].
	^ {oldStart. newStart}
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 21:47'
}
GitHubPullRequestBrowser >> parsePullRequestUrl [

	| normalized beforeQuery parts hostIndex owner repository kind numberString number |
	normalized := self pullRequestUrl asString withBlanksTrimmed.
	normalized isEmpty ifTrue: [
		UIManager default inform: 'Please enter a GitHub pull request URL.'.
		^ nil].
	beforeQuery := normalized copyUpTo: $? .
	parts := beforeQuery findTokens: '/'.
	hostIndex := parts indexOf: 'github.com' ifAbsent: [
		UIManager default inform: 'Please enter a URL from github.com.'.
		^ nil].
	(parts size < (hostIndex + 4)) ifTrue: [
		UIManager default inform: 'Expected URL format: https://github.com/<owner>/<repo>/pull/<number>.'.
		^ nil].
	owner := parts at: hostIndex + 1.
	repository := parts at: hostIndex + 2.
	kind := parts at: hostIndex + 3.
	numberString := parts at: hostIndex + 4.
	kind = 'pull' ifFalse: [
		UIManager default inform: 'URL must point to a pull request.'.
		^ nil].
	number := [Integer readFrom: numberString readStream]
		on: Error
		do: [
			UIManager default inform: 'Could not parse pull request number from URL.'.
			^ nil].
	^ {owner. repository. number}
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> pullRequestUrl [

	^ pullRequestUrl
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> pullRequestUrl: aString [

	pullRequestUrl := aString
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 17:49'
}
GitHubPullRequestBrowser >> rebuildCommentsKeepingScroll [

	(commentsScrollPane notNil and: [commentsScrollPane scroller notNil]) ifTrue: [
		savedScrollOffset := commentsScrollPane scroller offset y].
	self changed: #buildComments:
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:43'
}
GitHubPullRequestBrowser >> relevantDiffLinesFrom: diffLines forComment: comment oldStart: oldStart newStart: newStart [

	| lineNumber startLine rangeStart rangeEnd oldLine newLine relevant |
	lineNumber := self commentLineNumberFor: comment.
	lineNumber ifNil: [^ diffLines].
	startLine := comment at: 'start_line' ifAbsent: [nil].
	startLine isNil
		ifTrue: [
			rangeStart := (lineNumber - 3) max: 1.
			rangeEnd := lineNumber]
		ifFalse: [
			rangeStart := startLine min: lineNumber.
			rangeEnd := startLine max: lineNumber].
	oldLine := oldStart.
	newLine := newStart.
	relevant := OrderedCollection new.
	diffLines do: [:line |
		| prefix oldLineNumber newLineNumber include |
		prefix := line isEmpty ifTrue: [Character space] ifFalse: [line first].
		oldLineNumber := nil.
		newLineNumber := nil.
		prefix = $+
			ifTrue: [
				newLineNumber := newLine.
				newLine := newLine + 1]
			ifFalse: [
				prefix = $-
					ifTrue: [
						oldLineNumber := oldLine.
						oldLine := oldLine + 1]
					ifFalse: [
						oldLineNumber := oldLine.
						newLineNumber := newLine.
						oldLine := oldLine + 1.
						newLine := newLine + 1]].
		include := prefix = $-
			ifTrue: [
				oldLineNumber notNil
					and: [oldLineNumber between: rangeStart and: rangeEnd]]
			ifFalse: [
				newLineNumber notNil
					and: [newLineNumber between: rangeStart and: rangeEnd]].
		include ifTrue: [relevant add: line]].
	^ relevant asArray
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:53'
}
GitHubPullRequestBrowser >> replyTextForComment: comment [

	| body |
	body := comment at: 'body' ifAbsent: [''].
	^ (GSTextUtilities bold: (self authorForComment: comment)), ': ', body
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 17:50'
}
GitHubPullRequestBrowser >> resolveActionForId: commentId pullRequest: parsed entry: entry [

	^ [
		[
			api
				resolveReviewThreadForOwner: parsed first
				repository: parsed second
				number: parsed third
				commentDatabaseId: commentId.
			commentTexts := commentTexts copyWithout: entry.
			self rebuildCommentsKeepingScroll
		] on: Error do: [:ex |
			UIManager default inform: ex messageText]]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubPullRequestBrowser >> resolvedCommentIdsFor: parsed [

	"Resolution state is only available via GraphQL, and GitHub grants no unauthenticated
	GraphQL budget at all, so without a token every resolved comment silently comes back."
	^ [api
		resolvedCommentIdsForOwner: parsed first
		repository: parsed second
		number: parsed third]
		on: Error
		do: [:ex |
			api authToken ifNotNil: [
				UIManager default inform: 'Showing all comments, the resolved conversations could not be read:
', ex messageText].
			Set new]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 17:54'
}
GitHubPullRequestBrowser >> restoreScrollOf: scrollPane to: offset [

	scrollPane scroller hasSubmorphs ifFalse: [^ self].
	scrollPane scroller offset: scrollPane scroller offset x @ (offset max: 0).
	scrollPane setScrollDeltas.
	savedScrollOffset := nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> selectedCommentIndex [

	^ selectedCommentIndex
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> selectedCommentIndex: anInteger [

	selectedCommentIndex := anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:49'
}
GitHubPullRequestBrowser >> selectorFromMethodPattern: aString [

	| tokens first |
	tokens := aString withBlanksTrimmed findTokens: ' '.
	tokens isEmpty ifTrue: [^ nil].
	first := tokens first.
	(first includes: $:)
		ifTrue: [^ ((tokens select: [:each | each endsWith: ':']) fold: [:a :b | a, b]) asSymbol].
	(first first isLetter or: [first first = $_])
		ifTrue: [^ first asSymbol].
	^ first asSymbol
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 22:44'
}
GitHubPullRequestBrowser >> startNumberFromDiffToken: token prefix: prefixCharacter [

	| numberString |
	(token isEmpty or: [token first ~= prefixCharacter]) ifTrue: [^ nil].
	numberString := (token allButFirst) copyUpTo: $,.
	^ [Integer readFrom: numberString readStream]
		on: Error
		do: [nil]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:35'
}
GitHubPullRequestBrowser >> targetForComment: comment inFileContent: fileContent [

	| lines anchorLine lineIndex methodTarget downTarget |
	lines := fileContent lines.
	lines isEmpty ifTrue: [^ nil].
	anchorLine := self commentLineNumberFor: comment.
	anchorLine ifNil: [anchorLine := lines size].
	anchorLine := (anchorLine max: 1) min: lines size.
	lineIndex := anchorLine.
	[lineIndex >= 1] whileTrue: [
		methodTarget := self methodTargetFromLine: (lines at: lineIndex).
		methodTarget ifNotNil: [^ methodTarget].
		((lines at: lineIndex) includesSubstring: '#''squeak_changestamp'' :') ifTrue: [
			downTarget := self firstMethodTargetFrom: lines startingAt: lineIndex + 1.
			downTarget ifNotNil: [^ downTarget]].
		lineIndex := lineIndex - 1].
	^ self classTargetFromDefinitionLines: lines
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:44'
}
GitHubPullRequestBrowser >> windowTitle [

	^ 'GitHub Pull Request Browser'
]
