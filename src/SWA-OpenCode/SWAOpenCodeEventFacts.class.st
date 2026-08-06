"
The small set of facts a project-wide event carries, for views that colour by them.

Exists because the project-wide scan (SWAOpenCodeDb>>allPartsForProject:do:) deliberately does NOT build SWAOpenCodePart objects: there are 80128 of them, and fetching each to draw a hundred day cells would cost minutes for a picture that only counts and weighs them. What the calendar actually needs to colour by is five short strings and a number, so that is what this holds.

COST IS A SHARE. opencode accounts cost per MESSAGE and every part of that message reports the same figure. Summing it over the parts would multiply the project's spend by the average part count, so #costShare is the message's cost divided among its parts and #cost is kept alongside it for reporting.

The package is resolved from the tool call's target class through the live image, so it is the package that class is in NOW -- a class that has since moved reads as its new home.
"
Class {
	#name : #SWAOpenCodeEventFacts,
	#superclass : #Object,
	#instVars : [
		'sessionId',
		'session',
		'partId',
		'messageId',
		'role',
		'cost',
		'costShare',
		'tokens',
		'tokenShare',
		'model',
		'agent',
		'className',
		'packageName',
		'part'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> agent [
	^ agent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> agent: x [
	agent := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> className [
	^ className
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> className: x [
	className := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> cost [
	^ cost
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> cost: x [
	cost := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> costShare [
	^ costShare
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> costShare: x [
	costShare := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> messageId [
	^ messageId
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> messageId: x [
	messageId := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> model [
	^ model
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> model: x [
	model := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> packageName [
	^ packageName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> packageName: x [
	packageName := x
]

{
	#category : #'on demand',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:32'
}
SWAOpenCodeEventFacts >> part [
	"The REAL SWAOpenCodePart behind this event, materialised on demand and cached.

	The project-wide scan deliberately builds none: 80128 of them to draw a hundred
	day cells would cost minutes. But the moment you SELECT one message, everything
	the Flow view can do with it -- the rendered document in the Source flap, the
	inspector's dictionary, the cost and token record of its message -- is worth the
	one query, and reimplementing any of it here would be a second, worse copy.

	Loading the owning session's parts (a few hundred rows) is exactly what the Flow
	view pays to open, and it is cached on the session, so a second selection in the
	same session is free."
	part ifNotNil: [^ part].
	(session isNil or: [partId isNil]) ifTrue: [^ nil].
	^ part := session parts detect: [:p | p id = partId] ifNone: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:31'
}
SWAOpenCodeEventFacts >> partId [
	^ partId
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:31'
}
SWAOpenCodeEventFacts >> partId: x [
	partId := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:05'
}
SWAOpenCodeEventFacts >> role [
	^ role
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:05'
}
SWAOpenCodeEventFacts >> role: x [
	role := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:31'
}
SWAOpenCodeEventFacts >> session [
	^ session
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:31'
}
SWAOpenCodeEventFacts >> session: x [
	session := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> sessionId [
	^ sessionId
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:03'
}
SWAOpenCodeEventFacts >> sessionId: x [
	sessionId := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:09'
}
SWAOpenCodeEventFacts >> tokenShare [
	^ tokenShare
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:09'
}
SWAOpenCodeEventFacts >> tokenShare: x [
	tokenShare := x
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:09'
}
SWAOpenCodeEventFacts >> tokens [
	^ tokens
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:09'
}
SWAOpenCodeEventFacts >> tokens: x [
	tokens := x
]
