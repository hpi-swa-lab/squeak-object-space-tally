Class {
	#name : #SQLiteRecord,
	#superclass : #Dictionary,
	#category : #'SqueakSQLite3-Core-Public'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'ar 12/9/2011 19:19'
}
SQLiteRecord class >> names: names values: values [
	^self new names: names values: values
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'ar 12/9/2011 19:19'
}
SQLiteRecord >> doesNotUnderstand: aMessage [
	"Allow read access with common selector names"
	^self at: aMessage selector ifAbsent:[super doesNotUnderstand: aMessage].
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'ar 12/9/2011 19:20'
}
SQLiteRecord >> names: names values: values [
	names with: values do:[:n :v| self at: n put: v].

]
