"
A SWACodeNode whose subject is a method-category Symbol within a class. Children are SWACodeMethodNodes. 'isStatic' is true for class-side (metaclass) categories, treated like UML 'static' members.
"
Class {
	#name : #SWACodeCategoryNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'isStatic',
		'metaClass'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> browse [
	"Browse the owning class (categories have no standalone browser)."
	^ self classNode ifNotNil: [:cn | cn browse]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> buildChildren [
	"One SWACodeMethodNode per selector in this category, sorted by selector."
	| selectors |
	selectors := (metaClass organization listAtCategoryNamed: subject)
		asSortedCollection: [:a :b | a <= b].
	^ (selectors collect: [:sel |
		(SWACodeMethodNode on: (metaClass >> sel) methodReference parent: self)
			isStatic: self isStatic;
			yourself]) asOrderedCollection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> isStatic [
	^ isStatic == true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> isStatic: aBoolean [
	isStatic := aBoolean
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> kind [
	^ #category
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> metaClass [
	^ metaClass
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> metaClass: aClass [
	"The class or metaclass whose category this node represents (instance side
	for normal categories, the metaclass for static/class-side categories)."
	metaClass := aClass
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeCategoryNode >> name [
	"The category name; class-side categories get a 'class>>' prefix (UML static)."
	^ self isStatic
		ifTrue: ['class>>', subject asString]
		ifFalse: [subject asString]
]
