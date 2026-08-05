"
I connect to sqlite3 databases.

To create an in-memory database, set the fileName to ':memory:'.  See ""http://www.sqlite.org/c3ref/open.html"" for more info.
"
Class {
	#name : #SQLiteConnection,
	#superclass : #Object,
	#instVars : [
		'reference',
		'fileName',
		'txn',
		'sessionStamp'
	],
	#classVars : [
		'SessionCanary',
		'SessionStamp'
	],
	#classInstVars : [
		'registry'
	],
	#category : #'SqueakSQLite3-Core-Public',
	#'squeak_changestamp' : 'spd 5/19/2010 14:50'
}

{
	#category : #sessions,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:51'
}
SQLiteConnection class >> currentSessionStamp [
	"A number that CHANGES whenever the image is resumed in a new OS process.
	Connections remember the stamp they were opened under; anything carrying an
	older one holds a pointer belonging to a process that no longer exists.

	WHY A CANARY AND NOT A startUp: HOOK. The obvious implementation -- bump a
	counter from #startUp: -- is unsafe here, and unsafely in the exact way that
	already cost one image: the finalization process runs at userInterruptPriority,
	ABOVE the process that walks the startUp list, so a connection can be finalized
	BEFORE any hook of ours has run. A stamp must therefore be derivable on demand,
	from the environment, with no setup having happened.

	SessionCanary is an ExternalAddress, and the VM nulls every ExternalAddress on
	snapshot. So `isNull` is a reliable 'we are in a new process' signal that is
	true from the very first message send after load. One 1-byte allocation per
	session, never freed -- the old one belonged to the old process anyway."
	(SessionCanary isNil or: [SessionCanary isNull]) ifTrue: [
		SessionCanary := ExternalAddress allocate: 1.
		SessionStamp := (SessionStamp ifNil: [0]) + 1].
	^ SessionStamp
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'ab 12/16/2002 00:27'
}
SQLiteConnection class >> fileNamed: aString [
	^ self new fileName: aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:58'
}
SQLiteConnection class >> registry [
	^ registry ifNil: [registry := WeakRegistry new]
]

{
	#category : #finalization,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:58'
}
SQLiteConnection >> actAsExecutor [
	super actAsExecutor.
	fileName := nil
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 1/31/2003 16:20'
}
SQLiteConnection >> changedRows [
	^ self isOpen
		ifTrue: [SqliteLibrary default changedRows: reference]
		ifFalse: [0]
	
]

{
	#category : #private,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:58'
}
SQLiteConnection >> close [
	self unregister.
	self isOpen ifTrue: [SqliteLibrary default close: reference].
	reference := nil.

]

{
	#category : #private,
	#'squeak_changestamp' : 'ar 12/12/2011 20:50'
}
SQLiteConnection >> commit [
	txn := false.
	self execute: 'COMMIT' args: {}.

]

{
	#category : #'prepared statements',
	#'squeak_changestamp' : 'ar 12/9/2011 19:23'
}
SQLiteConnection >> execute: query args: args [
	^Array streamContents:[:s|
		self execute: query args: args do:[:result| s nextPut: result].
	].
]

{
	#category : #'prepared statements',
	#'squeak_changestamp' : 'ar 12/12/2011 19:04'
}
SQLiteConnection >> execute: query args: args do: aBlock [

	self isOpen ifFalse: [self open].
	^SqliteLibrary default execute: query args: args on: reference do: aBlock.

]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 1/29/2003 16:37'
}
SQLiteConnection >> executeQuery: aString [
	^ self withResultForQuery: aString do:
		[:result |
		Array streamContents:
			[:s |
			result do: [:row | s nextPut: row]]]
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 12/16/2002 00:27'
}
SQLiteConnection >> fileName [
	^ fileName
]

{
	#category : #private,
	#'squeak_changestamp' : 'spd 5/19/2010 14:52'
}
SQLiteConnection >> fileName: aString [
	"* Macs (tested OS 10.6.2) require an absolute file path to the database, Windows and Ubuntu do not
	 * To create an in-memory database, pass ':memory:' as the argument."

	fileName := aString
]

{
	#category : #finalization,
	#'squeak_changestamp' : 'ab 2/22/2003 23:15'
}
SQLiteConnection >> finalize [
	self close.
]

{
	#category : #sessions,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:51'
}
SQLiteConnection >> isFromDeadSession [
	"True when this connection's sqlite3* was obtained by a PREVIOUS process, i.e.
	the image has been saved and reloaded since it was opened.

	Such a handle cannot be detected by looking at it. SqliteReference is an
	ExternalStructure, so its handle is a ByteArray, and a ByteArray survives the
	snapshot with every byte intact -- the stale pointer comes back looking exactly
	like a live one and the nil/isNull tests of doc/FFI-startUp-handles.md all pass.
	Handing it to sqlite3_close is an immediate SIGSEGV."
	reference ifNil: [^ false].
	^ sessionStamp ~= self class currentSessionStamp
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:51'
}
SQLiteConnection >> isOpen [
	"Guarded against the image having been saved and reloaded. The byte test alone
	is NOT enough: the handle is a ByteArray, so its bytes survive a snapshot and a
	pointer from a dead process passes it (see #isFromDeadSession). Answering false
	here is what makes #close skip sqlite3_close, and what makes the next query
	reopen instead of crashing the VM."
	^ reference notNil
		and: [self isFromDeadSession not
		and: [reference getHandle anySatisfy: [:i | i > 0]]]
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 12/16/2002 00:34'
}
SQLiteConnection >> lastInsertId [
	^ self isOpen
		ifTrue: [SqliteLibrary default lastInsertId: reference]
		ifFalse: [0]
	
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:51'
}
SQLiteConnection >> open [
	reference := SqliteLibrary default open: fileName.
	sessionStamp := self class currentSessionStamp.
	self register.

]

{
	#category : #finalization,
	#'squeak_changestamp' : 'ab 2/22/2003 22:31'
}
SQLiteConnection >> register [
	self class registry add: self
]

{
	#category : #private,
	#'squeak_changestamp' : 'ar 12/12/2011 20:51'
}
SQLiteConnection >> rollback [
	txn := false.
	self execute: 'ROLLBACK' args: {}.

]

{
	#category : #private,
	#'squeak_changestamp' : 'ar 12/12/2011 20:50'
}
SQLiteConnection >> transact [
	txn := true.
	self execute: 'BEGIN TRANSACTION' args: {}.

]

{
	#category : #public,
	#'squeak_changestamp' : 'ar 12/12/2011 20:51'
}
SQLiteConnection >> transaction: aBlock [
	"Wrap the given block inside a transaction"
	| result |
	txn ifNotNil:[^aBlock value].
	[self transact.
	result := aBlock value.
	self commit.
	] ifCurtailed:[self rollback].
	^result
]

{
	#category : #finalization,
	#'squeak_changestamp' : 'ab 2/22/2003 22:32'
}
SQLiteConnection >> unregister [
	self class registry remove: self ifAbsent: []
]

{
	#category : #public,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:58'
}
SQLiteConnection >> withResultForQuery: aString do: aBlock [
	|result|
	self isOpen ifFalse: [self open].
	result := SqliteLibrary default resultForQuery: aString on: reference.
	^ [aBlock value: result] ensure: [result free]
]
