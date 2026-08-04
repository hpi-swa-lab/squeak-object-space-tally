Class {
	#name : #GitHubRepositoryPicker,
	#superclass : #Model,
	#instVars : [
		'api',
		'owner',
		'repository',
		'pullRequests',
		'selectedIndex'
	],
	#category : #'SWA-GitHub'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker class >> open [

	^ ToolBuilder open: self new
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> api [

	^ api
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:01'
}
GitHubRepositoryPicker >> authenticate [

	| token |
	token := UIManager default request: 'Enter your GitHub API token' initialAnswer: (api authToken ifNil: ['']).
	token ifNil: [^ self].
	api authToken: (token withBlanksTrimmed ifEmpty: [nil])
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:01'
}
GitHubRepositoryPicker >> buildAuthenticateButtonWith: builder [

	^ builder pluggableButtonSpec new
		model: self;
		label: 'Authenticate';
		action: #authenticate;
		frame: (0.82 @ 0 corner: 1 @ 0.1);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:01'
}
GitHubRepositoryPicker >> buildChooseFromGitSButtonWith: builder [

	^ builder pluggableButtonSpec new
		model: self;
		label: 'Choose GitHub repository in GitS';
		action: #chooseFromGitS;
		frame: (0.34 @ 0 corner: 0.58 @ 0.1);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:01'
}
GitHubRepositoryPicker >> buildChooseFromUrlButtonWith: builder [

	^ builder pluggableButtonSpec new
		model: self;
		label: 'Choose GitHub repository from URL';
		action: #chooseFromUrl;
		frame: (0.58 @ 0 corner: 0.82 @ 0.1);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> buildPullRequestListWith: builder [

	^ builder pluggableListSpec new
		model: self;
		list: #pullRequestList;
		getIndex: #selectedIndex;
		setIndex: #selectedIndex:;
		autoDeselect: false;
		frame: (0 @ 0.1 corner: 1 @ 1);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:01'
}
GitHubRepositoryPicker >> buildRepositoryFieldWith: builder [

	^ builder pluggableInputFieldSpec new
		model: self;
		getText: #repositoryLabel;
		readOnly: true;
		frame: (0 @ 0 corner: 0.34 @ 0.1);
		yourself
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:01'
}
GitHubRepositoryPicker >> buildWindow: builder [

	| windowSpec |
	windowSpec := builder pluggableWindowSpec new
		model: self;
		label: #windowTitle;
		children: OrderedCollection new;
		yourself.
	windowSpec children add: (self buildRepositoryFieldWith: builder).
	windowSpec children add: (self buildChooseFromGitSButtonWith: builder).
	windowSpec children add: (self buildChooseFromUrlButtonWith: builder).
	windowSpec children add: (self buildAuthenticateButtonWith: builder).
	windowSpec children add: (self buildPullRequestListWith: builder).
	^ windowSpec
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> buildWith: builder [

	^ builder build: (self buildWindow: builder)
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> chooseFromGitS [

	| repos labels choice parsed |
	repos := self gitSGitHubRepositories.
	repos isEmpty ifTrue: [^ UIManager default inform: 'No GitS repositories with a GitHub origin found.'].
	labels := repos collect: [:assoc | assoc key, ' (', assoc value, ')'].
	choice := UIManager default chooseFrom: labels values: repos.
	choice ifNil: [^ self].
	parsed := GitHubAPI ownerAndRepositoryFromUrl: choice value.
	parsed ifNil: [^ UIManager default inform: 'Could not parse GitHub URL.'].
	self selectOwner: parsed first repository: parsed second
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> chooseFromUrl [

	| url parsed |
	url := UIManager default request: 'Enter the GitHub repository URL' initialAnswer: 'https://github.com/'.
	(url isNil or: [url withBlanksTrimmed isEmpty]) ifTrue: [^ self].
	parsed := GitHubAPI ownerAndRepositoryFromUrl: url.
	parsed ifNil: [^ UIManager default inform: 'Could not parse GitHub repository URL.'].
	self selectOwner: parsed first repository: parsed second
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> gitSGitHubRepositories [

	^ (GSGitWorkingCopy registry values
		select: [:wc |
			(wc remoteNames includes: 'origin')
				and: [((wc unitOfWork remoteUrl: 'origin') ifNil: ['']) includesSubstring: 'github.com']]
		thenCollect: [:wc | wc name -> (wc unitOfWork remoteUrl: 'origin')]) asArray
]

{
	#category : #'initialize-release',
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> initialize [

	super initialize.
	api := GitHubAPI new.
	pullRequests := #().
	selectedIndex := 0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> listLabelFor: pr [

	| creator |
	creator := (pr at: 'user' ifAbsent: [nil])
		ifNil: ['unknown']
		ifNotNil: [:user | user at: 'login' ifAbsent: ['unknown']].
	^ '#', (pr at: 'number') asString, ' [', (pr at: 'state'), '] ', (pr at: 'title'), ' â ', creator
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> loadPullRequests [

	[
		| prs |
		prs := UIManager default
			informUser: 'Loading pull requests'
			during: [api pullRequestsForOwner: owner repository: repository].
		pullRequests := self sortPullRequests: prs.
		selectedIndex := 0.
		self changed: #pullRequestList.
		self changed: #selectedIndex
	] on: Error do: [:ex |
		UIManager default inform: ex messageText]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> openPullRequest: pr [

	GitHubPullRequestBrowser
		openForPullRequestUrl: (pr at: 'html_url')
		api: api
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> pullRequestList [

	^ pullRequests collect: [:each | self listLabelFor: each]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> repositoryLabel [

	owner ifNil: [^ '(no repository selected)'].
	^ owner, '/', repository
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> selectOwner: anOwner repository: aRepository [

	owner := anOwner.
	repository := aRepository.
	self changed: #repositoryLabel.
	self loadPullRequests
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> selectedIndex [

	^ selectedIndex
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> selectedIndex: anInteger [

	selectedIndex := anInteger.
	self changed: #selectedIndex.
	(anInteger between: 1 and: pullRequests size) ifTrue: [
		self openPullRequest: (pullRequests at: anInteger)]
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:55'
}
GitHubRepositoryPicker >> sortPullRequests: prs [

	^ (prs asSortedCollection: [:a :b |
		| aOpen bOpen |
		aOpen := (a at: 'state') = 'open'.
		bOpen := (b at: 'state') = 'open'.
		aOpen = bOpen
			ifTrue: [(a at: 'number') < (b at: 'number')]
			ifFalse: [aOpen]]) asArray
]

{
	#category : #toolbuilder,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubRepositoryPicker >> windowTitle [

	^ 'GitHub Repository Picker'
]
