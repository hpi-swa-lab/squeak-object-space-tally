Class {
	#name : #GitHubAPI,
	#superclass : #Object,
	#instVars : [
		'baseUrl',
		'authToken'
	],
	#classVars : [
		'AuthToken'
	],
	#category : #'SWA-GitHub'
}

{
	#category : #authentication,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI class >> authToken [

	"Kept in a class variable so it survives in the image, like GitS keeps its credentials."
	^ AuthToken
]

{
	#category : #authentication,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI class >> authToken: aStringOrNil [

	AuthToken := aStringOrNil ifNotNil: [:token | token withBlanksTrimmed ifEmpty: [nil]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:22'
}
GitHubAPI class >> baseUrl [

	^ 'https://api.github.com'
]

{
	#category : #authentication,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI class >> forgetAuthToken [

	AuthToken := nil
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:54'
}
GitHubAPI class >> ownerAndRepositoryFromUrl: aString [

	"Parse owner and repository from an HTTPS or SSH GitHub URL.
	Handles e.g. https://github.com/owner/repo, https://github.com/owner/repo.git,
	and git@github.com:owner/repo.git. Answers an Array {owner. repository} or nil."
	| string marker rest parts owner repo |
	string := aString withBlanksTrimmed.
	marker := 'github.com'.
	(string includesSubstring: marker) ifFalse: [^ nil].
	rest := string copyFrom: ((string indexOfSubCollection: marker) + marker size) to: string size.
	(rest notEmpty and: [(rest first = $/) or: [rest first = $:]]) ifTrue: [
		rest := rest allButFirst].
	parts := (rest copyUpTo: $?) findTokens: '/'.
	parts size < 2 ifTrue: [^ nil].
	owner := parts first.
	repo := parts second.
	(repo endsWith: '.git') ifTrue: [repo := repo copyFrom: 1 to: repo size - 4].
	(owner isEmpty or: [repo isEmpty]) ifTrue: [^ nil].
	^ {owner. repo}
]

{
	#category : #authentication,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI class >> requestAuthToken [

	self authToken: (UIManager default requestPassword: 'GitHub API token').
	^ AuthToken
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:22'
}
GitHubAPI class >> withAuthToken: aString [

	| api |
	api := self new.
	api authToken: aString.
	^ api
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:22'
}
GitHubAPI >> allPullRequestCommentsForOwner: owner repository: repository number: pullRequestNumber [

	| issueComments reviewComments |
	issueComments := self pullRequestCommentsForOwner: owner repository: repository number: pullRequestNumber.
	reviewComments := self pullRequestReviewCommentsForOwner: owner repository: repository number: pullRequestNumber.
	^ issueComments, reviewComments
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI >> authToken [

	^ authToken ifNil: [self class authToken]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI >> authToken: aString [

	"Remember it in the image too, so a token entered once outlives this API instance."
	authToken := aString.
	self class authToken: aString
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:06'
}
GitHubAPI >> configureRequest: aWebRequest [

	aWebRequest headerAt: 'Accept' put: 'application/vnd.github+json'.
	aWebRequest headerAt: 'X-GitHub-Api-Version' put: '2022-11-28'.
	aWebRequest headerAt: 'User-Agent' put: 'Squeak-GitHubAPI'.
	self authToken ifNotNil: [:token |
		aWebRequest headerAt: 'Authorization' put: 'Bearer ', token].
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubAPI >> decodeBase64ContentFrom: aJsonObject [

	| encoded |
	encoded := aJsonObject at: 'content' ifAbsent: [^ ''].
	^ (Base64MimeConverter mimeDecodeToChars: encoded readStream) upToEnd
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubAPI >> encodedPath: aPath [

	^ ((aPath findTokens: '/') collect: [:each | each encodeForHTTP]) joinSeparatedBy: '/'
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 13:29'
}
GitHubAPI >> fileContentForOwner: owner repository: repository path: path ref: ref [

	| apiPath |
	apiPath := '/repos/', owner, '/', repository, '/contents/', (self encodedPath: path).
	ref ifNotNil: [apiPath := apiPath, '?ref=', ref encodeForHTTP].
	^ self decodeBase64ContentFrom: (self getJsonAt: apiPath)
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:25'
}
GitHubAPI >> getAllJsonAt: apiPath [

	| page results pageResults |
	page := 1.
	results := OrderedCollection new.
	[
		pageResults := self getJsonAt: (self pagedPathFor: apiPath page: page).
		pageResults isEmpty
	] whileFalse: [
		results addAll: pageResults.
		page := page + 1].
	^ results asArray
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:23'
}
GitHubAPI >> getJsonAt: apiPath [

	| response |
	response := WebClient new
		httpGet: self class baseUrl, apiPath
		do: [:request | self configureRequest: request].
	response isSuccess ifFalse: [
		self error: 'GitHub API request failed (', response code asString, '): ', response status].
	^ Json new readFrom: response content readStream
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/12/2026 15:07'
}
GitHubAPI >> graphqlQuery: queryString variables: aJsonObject [

	"GitHub grants no unauthenticated GraphQL budget at all, so ask rather than fail obscurely."
	| payload response result errors |
	self authToken ifNil: [
		self class requestAuthToken ifNil: [self error: 'GitHub GraphQL needs an API token.']].
	payload := Json render: (JsonObject new
		at: 'query' put: queryString;
		at: 'variables' put: aJsonObject;
		yourself).
	response := WebClient new
		httpPost: 'https://api.github.com/graphql'
		content: payload
		type: 'application/json'
		do: [:request | self configureRequest: request].
	response isSuccess ifFalse: [
		self error: 'GitHub GraphQL request failed (', response code asString, '): ', response status].
	result := Json new readFrom: response content readStream.
	errors := result at: 'errors' ifAbsent: [nil].
	errors ifNotNil: [
		self error: 'GitHub GraphQL error: ', errors printString].
	^ result at: 'data'
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:25'
}
GitHubAPI >> pagedPathFor: apiPath page: pageNumber [

	| separator |
	separator := (apiPath includes: $?) ifTrue: ['&'] ifFalse: ['?'].
	^ apiPath, separator, 'per_page=100&page=', pageNumber asString
]

{
	#category : #private,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubAPI >> postJsonAt: apiPath content: aJsonString [

	| response |
	response := WebClient new
		httpPost: self class baseUrl, apiPath
		content: aJsonString
		type: 'application/vnd.github+json'
		do: [:request | self configureRequest: request].
	response isSuccess ifFalse: [
		self error: 'GitHub API request failed (', response code asString, '): ', response status].
	^ Json new readFrom: response content readStream
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:25'
}
GitHubAPI >> pullRequestCommentsForOwner: owner repository: repository number: pullRequestNumber [

	"Fetch discussion comments for the pull request from the issue comments endpoint."
	^ self getAllJsonAt: '/repos/', owner, '/', repository, '/issues/', pullRequestNumber asString, '/comments'
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/25/2026 18:25'
}
GitHubAPI >> pullRequestReviewCommentsForOwner: owner repository: repository number: pullRequestNumber [

	"Fetch inline review comments for the pull request from the review comments endpoint."
	^ self getAllJsonAt: '/repos/', owner, '/', repository, '/pulls/', pullRequestNumber asString, '/comments'
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 15:53'
}
GitHubAPI >> pullRequestsForOwner: owner repository: repository [

	"All pull requests (open and closed) for the repository."
	^ self getAllJsonAt: '/repos/', owner, '/', repository, '/pulls?state=all'
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 14:05'
}
GitHubAPI >> replyToReviewCommentForOwner: owner repository: repository number: pullRequestNumber commentId: commentId body: bodyString [

	| apiPath payload |
	apiPath := '/repos/', owner, '/', repository, '/pulls/', pullRequestNumber asString, '/comments/', commentId asString, '/replies'.
	payload := Json render: (JsonObject new at: 'body' put: bodyString; yourself).
	^ self postJsonAt: apiPath content: payload
]

{
	#category : #api,
	#'squeak_changestamp' : 'SqueakXR 6/26/2026 16:33'
}
GitHubAPI >> resolveReviewThreadForOwner: owner repository: repository number: pullRequestNumber commentDatabaseId: commentDatabaseId [

	"Resolve the review thread that contains the given comment."
	| threadId query |
	threadId := self
		reviewThreadIdForOwner: owner
		repository: repository
		number: pullRequestNumber
		commentDatabaseId: commentDatabaseId.
	threadId ifNil: [self error: 'Could not find review thread for comment.'].
	query := 'mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}'.
	^ self graphqlQuery: query variables: (JsonObject new
		at: 'threadId' put: threadId;
		yourself)
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 18:20'
}
GitHubAPI >> resolvedCommentIdsForOwner: owner repository: repository number: pullRequestNumber [

	"Answer a Set of comment databaseIds belonging to resolved review threads.
	Paginate through all review threads, since a pull request may have more than one page."
	| query cursor resolvedIds |
	query := 'query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$after){pageInfo{hasNextPage endCursor} nodes{isResolved comments(first:100){nodes{databaseId}}}}}}}'.
	resolvedIds := Set new.
	cursor := nil.
	[
		| data reviewThreads threads pageInfo |
		data := self graphqlQuery: query variables: (JsonObject new
			at: 'owner' put: owner;
			at: 'repo' put: repository;
			at: 'number' put: pullRequestNumber;
			at: 'after' put: cursor;
			yourself).
		reviewThreads := (((data at: 'repository') at: 'pullRequest') at: 'reviewThreads').
		threads := reviewThreads at: 'nodes'.
		threads do: [:thread |
			(thread at: 'isResolved') ifTrue: [
				((thread at: 'comments') at: 'nodes') do: [:comment |
					resolvedIds add: (comment at: 'databaseId')]]].
		pageInfo := reviewThreads at: 'pageInfo'.
		(pageInfo at: 'hasNextPage') ifFalse: [^ resolvedIds].
		cursor := pageInfo at: 'endCursor'.
	] repeat
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 18:59'
}
GitHubAPI >> reviewThreadIdForOwner: owner repository: repository number: pullRequestNumber commentDatabaseId: commentDatabaseId [

	"Answer the GraphQL node id of the review thread containing the given comment, or nil.
	Paginate through all review threads, since a pull request may have more than one page."
	| query cursor |
	query := 'query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$after){pageInfo{hasNextPage endCursor} nodes{id comments(first:100){nodes{databaseId}}}}}}}'.
	cursor := nil.
	[
		| data reviewThreads threads pageInfo |
		data := self graphqlQuery: query variables: (JsonObject new
			at: 'owner' put: owner;
			at: 'repo' put: repository;
			at: 'number' put: pullRequestNumber;
			at: 'after' put: cursor;
			yourself).
		reviewThreads := (((data at: 'repository') at: 'pullRequest') at: 'reviewThreads').
		threads := reviewThreads at: 'nodes'.
		threads do: [:thread |
			((thread at: 'comments') at: 'nodes') do: [:comment |
				(comment at: 'databaseId') = commentDatabaseId ifTrue: [
					^ thread at: 'id']]].
		pageInfo := reviewThreads at: 'pageInfo'.
		(pageInfo at: 'hasNextPage') ifFalse: [^ nil].
		cursor := pageInfo at: 'endCursor'.
	] repeat
]
