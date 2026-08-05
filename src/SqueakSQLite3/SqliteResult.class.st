Class {
	#name : #SqliteResult,
	#superclass : #Object,
	#instVars : [
		'buffer',
		'rows',
		'columns',
		'columnNames',
		'index'
	],
	#category : #'SqueakSQLite3-Core-Support'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'ab 12/16/2002 01:41'
}
SqliteResult class >> buffer: aResultBuffer rows: nRows columns: nColumns [
	^ self new setBuffer: aResultBuffer rows: nRows columns: nColumns
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 12/16/2002 01:58'
}
SqliteResult >> atEnd [
	^ index > (rows + 1 * columns)
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 1/29/2003 16:06'
}
SqliteResult >> columnNames [
	^ columnNames
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:10'
}
SqliteResult >> currentAddress [
	"Answer a char** pointing at the index-th slot of the char** table returned
	by sqlite3_get_table. Pointer-size safe (the original code hardwired 4 bytes)."

	| base |
	base := (buffer getHandle pointerAt: 1) getHandle.
	^ ExternalAddress
		fromAddress: base
		movedBy: index - 1 * ExternalAddress wordSize
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 12/16/2002 01:56'
}
SqliteResult >> do: aBlock [
	self reset.
	rows timesRepeat: [aBlock value: self nextRow].
	
]

{
	#category : #public,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:54'
}
SqliteResult >> free [
	SqliteLibrary default freeResultBuffer: buffer.
	buffer := nil.
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 12/16/2002 01:58'
}
SqliteResult >> nextKeysAndValuesDo: aBlock [
	self atEnd ifTrue: [self error: 'Trying to read past end of results'].
	columnNames do:
		[:ea |
		aBlock value: ea value: self nextString]
]

{
	#category : #public,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:54'
}
SqliteResult >> nextRow [
	|row|
	row := Dictionary new.
	self nextKeysAndValuesDo: [:k :v | row at: k put: v].
	^ row
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:55'
}
SqliteResult >> nextString [
	|str|
	buffer ifNil: [self error: 'Result has been freed'].
	str := self readString.
	index := index + 1.
	^ str
]

{
	#category : #public,
	#'squeak_changestamp' : 'ab 1/29/2003 16:34'
}
SqliteResult >> nextValues [
	^ columnNames collect: [:ea | self nextString]
]

{
	#category : #reading,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:55'
}
SqliteResult >> readColumns [
	columnNames := OrderedCollection new.
	columns timesRepeat: [columnNames add: self nextString]
]

{
	#category : #reading,
	#'squeak_changestamp' : 'ab 12/16/2002 01:47'
}
SqliteResult >> readString [
	^ self readStringAtAddress: (self currentAddress)
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:07'
}
SqliteResult >> readStringAtAddress: anAddress [
	"anAddress is a char**. Answer the String it points to, or nil for NULL."

	| slotType ptr |
	slotType := ExternalAddress wordSize = 8
		ifTrue: [ExternalType unsignedLongLong]
		ifFalse: [ExternalType unsignedLong].
	ptr := (ExternalData fromHandle: anAddress type: slotType) at: 1.
	ptr = 0 ifTrue: [^ nil].
	^ (ExternalData
		fromHandle: (ExternalAddress fromInteger: ptr)
		type: ExternalType string) fromCString
]

{
	#category : #public,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:55'
}
SqliteResult >> reset [
	index := 1.
	self readColumns.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:55'
}
SqliteResult >> setBuffer: aResultBuffer rows: nRows columns: nColumns [
	buffer := aResultBuffer.
	rows := nRows.
	columns := nColumns.
	self reset.
]
