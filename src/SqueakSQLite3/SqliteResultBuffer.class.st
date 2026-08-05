Class {
	#name : #SqliteResultBuffer,
	#superclass : #ExternalStructure,
	#category : #'SqueakSQLite3-Core-Support'
}

{
	#category : #'field definition',
	#'squeak_changestamp' : 'ab 12/16/2002 00:35'
}
SqliteResultBuffer class >> fields [
	"self defineFields"
	^ #((value 'void*'))
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'ab 1/14/2003 15:28'
}
SqliteResultBuffer class >> initialize [
	self defineFields
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'mva 10/11/2016 01:28'
}
SqliteResultBuffer >> value [
	"This method was automatically generated. See SqliteResultBuffer class>>fields."
	^ExternalData fromHandle: (handle pointerAt: 1) type: ExternalType void asPointerType
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'mva 10/11/2016 01:28'
}
SqliteResultBuffer >> value: anObject [
	"This method was automatically generated. See SqliteResultBuffer class>>fields."
	handle pointerAt: 1 put: anObject getHandle.
]
