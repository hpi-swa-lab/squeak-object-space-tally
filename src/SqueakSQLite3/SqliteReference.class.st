Class {
	#name : #SqliteReference,
	#superclass : #ExternalStructure,
	#category : #'SqueakSQLite3-Core-Support'
}

{
	#category : #'field definition',
	#'squeak_changestamp' : 'cf 11/22/2005 21:38'
}
SqliteReference class >> fields [
	"self defineFields"
	^ #((value 'void*'))
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'cf 11/22/2005 21:58'
}
SqliteReference class >> initialize [
	"SqliteReference initialize"
	self defineFields
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'mva 10/11/2016 01:28'
}
SqliteReference >> value [
	"This method was automatically generated. See SqliteReference class>>fields."
	^ExternalData fromHandle: (handle pointerAt: 1) type: ExternalType void asPointerType
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'mva 10/11/2016 01:28'
}
SqliteReference >> value: anObject [
	"This method was automatically generated. See SqliteReference class>>fields."
	handle pointerAt: 1 put: anObject getHandle.
]
