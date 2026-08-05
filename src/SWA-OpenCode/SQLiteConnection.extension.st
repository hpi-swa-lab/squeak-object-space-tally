Extension { #name : #SQLiteConnection }

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:51'
}
SQLiteConnection >> openReadOnly [
	"Open with SQLITE_OPEN_READONLY. Because #withResultForQuery:do: and
	#execute:args:do: only open when #isOpen is false, opening eagerly here is
	enough to keep the whole connection read-only for its lifetime."
	reference := SqliteLibrary default openReadOnly: fileName.
	sessionStamp := self class currentSessionStamp.
	self register
]

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:23'
}
SQLiteConnection class >> readOnlyFileNamed: aString [
	"A connection that can never write to the file -- for analysing databases that
	belong to somebody else."
	^ self new
		fileName: aString;
		openReadOnly;
		yourself
]
