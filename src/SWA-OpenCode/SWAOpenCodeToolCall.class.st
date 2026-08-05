"
One tool invocation an agent made inside an opencode session, reduced to the
fields that say WHAT IT TOUCHED and WHEN. Built by SWAOpenCodeHistory from a
`part` row; see SWAOpenCodeDb for why the tool's output is never loaded.

THE POINT of this class is #targetKey plus #accessKind: a tool call is
reinterpreted as a READ or a WRITE of a named thing, so that a whole
conversation history becomes an access log that can colour a map of the code.

Two kinds of target coexist, and in this workspace the second one dominates:

	#file    a filesystem path -- read / edit / write / apply_patch.
	#method  a Smalltalk method, keyed 'Class>>selector'
	#class   a Smalltalk class, keyed 'Class'
	         -- squeak_get_source_code / squeak_write_method_code /
	            squeak_write_class_code / squeak_list_methods, and their xr_ twins.

That second family is why this data belongs in SWA at all: 'Class>>selector' is
already the Code Map's `crossRefKey`, so an agent's edits land on the very same
tiles without any translation layer. In the squeak project the ratio is stark --
765 file reads and 494 file writes against 7100 method/class reads and 6100
method/class writes. The agent barely touches files here; it edits the image.

Calls that name no durable target (bash, grep, glob, evaluate, todowrite,
question, task) answer a nil #targetKey. They are still real events with real
timestamps, so they still appear in the timeline and in the per-session tallies;
they just cannot decorate a map.
"
Class {
	#name : #SWAOpenCodeToolCall,
	#superclass : #Object,
	#instVars : [
		'session',
		'tool',
		'status',
		'startMillis',
		'endMillis',
		'filePath',
		'className',
		'selector',
		'actionName',
		'pattern',
		'command'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #classification,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall class >> readingTools [
	"Tools that LOOK at a named target without changing it. `squeak_list_methods`
	and `squeak_list_classes` are reads of a class -- browsing a class's protocol is
	how an agent decides what to change next, and leaving it out would make the
	'looked at but never touched' question unanswerable."
	^ #(#read #squeak_get_source_code #squeak_list_methods
		#xr_get_source_code #xr_list_methods) asSet
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:30'
}
SWAOpenCodeToolCall class >> session: aSession fields: anArray [
	"anArray is one row of SWAOpenCodeDb>>toolPartFieldPaths, in that order."
	^ self new setSession: aSession fields: anArray
]

{
	#category : #classification,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall class >> writingTools [
	"Tools whose whole purpose is to CHANGE the target. `squeak_write_method_code`
	with action #delete counts as a write: removing a method is an edit of it, and
	an access map that hid deletions would hide exactly the changes you cannot
	recover by looking at the current image."
	^ #(#edit #write #apply_patch
		#squeak_write_method_code #squeak_write_class_code
		#xr_write_method_code #xr_write_class_code) asSet
]

{
	#category : #classification,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> accessKind [
	"#read, #write, or #other. A FAILED call is still an access attempt but changed
	nothing, so an errored write is demoted to a read: it read enough of the target
	to fail on it."
	(self class writingTools includes: tool)
		ifTrue: [^ status == #error ifTrue: [#read] ifFalse: [#write]].
	(self class readingTools includes: tool) ifTrue: [^ #read].
	^ #other
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> actionName [
	"#add / #modify / #delete / #rename for the squeak_write_* tools, else nil."
	^ actionName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> command [
	"The bash command line, truncated to 400 characters at load time."
	^ command
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:38'
}
SWAOpenCodeToolCall >> details [
	| d |
	d := Dictionary new.
	d at: #tool put: tool.
	d at: #status put: status.
	d at: #accessKind put: self accessKind.
	d at: #targetKind put: self targetKind.
	d at: #targetKey put: self targetKey.
	d at: #action put: actionName.
	d at: #filePath put: filePath.
	d at: #className put: className.
	d at: #selector put: selector.
	d at: #pattern put: pattern.
	d at: #command put: command.
	d at: #timeStamp put: self timeStamp.
	d at: #durationMillis put: self durationMillis.
	d at: #session put: session.
	d at: #sessionTitle put: session title.
	^ d
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> durationMillis [
	"How long the tool itself ran. 0 when opencode recorded no times (an aborted or
	never-started call)."
	(startMillis isNil or: [endMillis isNil]) ifTrue: [^ 0].
	^ (endMillis - startMillis) max: 0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> endMillis [
	^ endMillis
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> filePath [
	^ filePath
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> label [
	"A one-line description for tooltips and timeline bars."
	| t |
	t := self targetKey.
	t ifNotNil: [^ tool , ' ' , (self targetKind == #file
		ifTrue: [(t copyAfterLast: $/) ifEmpty: [t]]
		ifFalse: [t])].
	command ifNotNil: [^ tool , ' ' , (command copyReplaceAll: (String with: Character cr) with: ' ')].
	pattern ifNotNil: [^ tool , ' ' , pattern].
	^ tool asString
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> printOn: aStream [
	aStream nextPutAll: 'ToolCall('; nextPutAll: self label.
	aStream nextPutAll: ', '; nextPutAll: self accessKind.
	status == #error ifTrue: [aStream nextPutAll: ', ERROR'].
	aStream nextPut: $)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> session [
	^ session
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> setSession: aSession fields: f [
	"Positional unpacking of SWAOpenCodeDb>>toolPartFieldPaths. Kept in one place so
	that adding a path there is a two-line change here."
	session := aSession.
	tool := (f at: 1) ifNotNil: [:x | x asSymbol].
	status := (f at: 2) ifNotNil: [:x | x asSymbol].
	startMillis := f at: 3.
	endMillis := f at: 4.
	filePath := f at: 5.
	className := f at: 6.
	selector := f at: 7.
	"squeak_write_class_code names its class `name`, every other squeak tool calls
	it `class` -- normalise here so #targetKey has one rule, not two."
	className ifNil: [className := f at: 8].
	actionName := (f at: 9) ifNotNil: [:x | x asSymbol].
	pattern := f at: 10.
	command := (f at: 11) ifNotNil: [:x | x size > 400 ifTrue: [x first: 400] ifFalse: [x]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> startMillis [
	^ startMillis
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> status [
	^ status
]

{
	#category : #classification,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> targetKey [
	"The identity of the thing touched, or nil.

	For Smalltalk targets this is deliberately SWA's own `crossRefKey` spelling --
	'Class>>selector' for a method, 'Class' for a class -- so that these keys drop
	straight onto Code Map tiles with no translation. The class-side tools name
	their receiver 'Foo class' in the MCP argument, which is also exactly what the
	Code Map calls the metaclass node, so that case needs no work either.

	For files it is the absolute path as opencode recorded it."
	filePath ifNotNil: [^ filePath].
	className ifNil: [^ nil].
	^ selector
		ifNil: [className]
		ifNotNil: [className , '>>' , selector]
]

{
	#category : #classification,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> targetKind [
	"#file, #method, #class, or nil for calls that name no durable target."
	filePath ifNotNil: [^ #file].
	className ifNil: [^ nil].
	^ selector ifNil: [#class] ifNotNil: [#method]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> timeStamp [
	"When the call started, in LOCAL time -- the calendar and timeline group by day,
	and a day boundary is a local-time notion. opencode stores UTC milliseconds."
	startMillis ifNil: [^ nil].
	^ (DateAndTime fromUnixTime: startMillis // 1000) asLocal
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:31'
}
SWAOpenCodeToolCall >> tool [
	^ tool
]
