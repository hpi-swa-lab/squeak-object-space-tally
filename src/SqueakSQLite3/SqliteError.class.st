Class {
	#name : #SqliteError,
	#superclass : #ExternalStructure,
	#category : #'SqueakSQLite3-Core-Support'
}

{
	#category : #definitions,
	#'squeak_changestamp' : 'ab 12/15/2002 21:55'
}
SqliteError class >> fields [
	"self defineFields"
	^ #((value 'char*'))
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'ab 12/15/2002 22:17'
}
SqliteError class >> initialize [
	self defineFields
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'mva 10/11/2016 01:28'
}
SqliteError >> value [
	"This method was automatically generated. See SqliteError class>>fields."
	^ExternalData fromHandle: (handle pointerAt: 1) type: ExternalType char asPointerType
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'mva 10/11/2016 01:28'
}
SqliteError >> value: anObject [
	"This method was automatically generated. See SqliteError class>>fields."
	handle pointerAt: 1 put: anObject getHandle.
]
