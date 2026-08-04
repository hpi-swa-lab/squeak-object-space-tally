Class {
	#name : #GitHubPullRequestCommentEntry,
	#superclass : #Object,
	#instVars : [
		'text',
		'buttonLabel',
		'buttonAction',
		'htmlUrl',
		'commentAction',
		'resolveAction'
	],
	#category : #'SWA-GitHub'
}

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubPullRequestCommentEntry >> addComment [

	| body |
	self canComment ifFalse: [^ self].
	body := UIManager default
		multiLineRequest: 'Enter your comment'
		centerAt: Sensor cursorPoint
		initialAnswer: ''
		answerHeight: 200.
	(body isNil or: [body withBlanksTrimmed isEmpty]) ifTrue: [^ self].
	commentAction value: body
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:16'
}
GitHubPullRequestCommentEntry >> appendReplyText: aReplyText [

	text := Text streamContents: [:stream |
		stream nextPutAll: text.
		stream cr; cr.
		stream nextPutAll: aReplyText]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> buttonAction [

	^ buttonAction
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> buttonAction: aBlock [

	buttonAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> buttonLabel [

	^ buttonLabel ifNil: ['']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> buttonLabel: aString [

	buttonLabel := aString
]

{
	#category : #testing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubPullRequestCommentEntry >> canComment [

	^ commentAction notNil
]

{
	#category : #testing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubPullRequestCommentEntry >> canResolve [

	^ resolveAction notNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubPullRequestCommentEntry >> commentAction [

	^ commentAction
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubPullRequestCommentEntry >> commentAction: aBlock [

	commentAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubPullRequestCommentEntry >> commentLabel [

	^ 'Comment'
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:04'
}
GitHubPullRequestCommentEntry >> copyLink [

	self hasHtmlUrl ifTrue: [Clipboard clipboardText: htmlUrl]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:04'
}
GitHubPullRequestCommentEntry >> copyLinkLabel [

	^ 'Copy link'
]

{
	#category : #testing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> hasButton [

	^ buttonAction notNil and: [buttonLabel notNil and: [buttonLabel notEmpty]]
]

{
	#category : #testing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:58'
}
GitHubPullRequestCommentEntry >> hasHtmlUrl [

	^ htmlUrl notNil and: [htmlUrl notEmpty]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:58'
}
GitHubPullRequestCommentEntry >> htmlUrl [

	^ htmlUrl
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:58'
}
GitHubPullRequestCommentEntry >> htmlUrl: aString [

	htmlUrl := aString
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:58'
}
GitHubPullRequestCommentEntry >> openInBrowser [

	self hasHtmlUrl ifTrue: [
		WebBrowser defaultOrNil ifNotNil: [:browser | browser openOnUrl: htmlUrl]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:58'
}
GitHubPullRequestCommentEntry >> openInBrowserLabel [

	^ 'Open in web browser'
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> openTarget [

	self hasButton ifTrue: [buttonAction value]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubPullRequestCommentEntry >> resolveAction [

	^ resolveAction
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubPullRequestCommentEntry >> resolveAction: aBlock [

	resolveAction := aBlock
]

{
	#category : #actions,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubPullRequestCommentEntry >> resolveConversation [

	self canResolve ifTrue: [resolveAction value]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubPullRequestCommentEntry >> resolveLabel [

	^ 'Resolve'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> text [

	^ text
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubPullRequestCommentEntry >> text: aText [

	text := aText
]
