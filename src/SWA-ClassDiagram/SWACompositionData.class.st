"
Which domain classes each class holds in its instance variables, read from what its methods store into them. Works on NAMES, not bindings, so it reads code from git as well as the image, and persists as JSON:

	{ ""format"": ""SWACompositionData/1"", ""name"": ..., ""associations"": { className: { ivarName: [targetClassName, ""1"" or ""*""] } } }
"
Class {
	#name : #SWACompositionData,
	#superclass : #Object,
	#instVars : [
		'name',
		'associations',
		'incoming',
		'generated',
		'maxDegree'
	],
	#category : #'SWA-ClassDiagram',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> associationsOf: aClass [
	^ self associationsOf: aClass resolver: (self resolverFor: aClass)
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> associationsOf: aClass resolver: aBlock [
	"ivarName -> { targetClassName. multiplicity }. In an untyped language what the
	methods store is the only static evidence there is: 'camera := SRAvatarCamera new'
	names a type, whereas 'avatar: anAvatar' names nothing a tool can trust."
	| ivars result |
	ivars := aClass allInstVarNames.
	result := Dictionary new.
	{aClass. aClass classSide} do: [:behavior |
		behavior selectors do: [:selector |
			(self parse: (behavior sourceCodeAt: selector) asString in: behavior) ifNotNil: [:methodNode |
				methodNode nodesDo: [:node |
					self record: node into: result ivars: ivars resolver: aBlock]]]].
	^ result
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> classOf: aNode resolver: aBlock [
	| name |
	name := self variableNameOf: aNode.
	(name isNil or: [name isEmpty or: [name first isUppercase not]]) ifTrue: [^ nil].
	^ aBlock value: name
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> containerNames [
	"Holding an OrderedCollection is not a relationship with OrderedCollection; the
	association wanted is to the element type, found from what gets added."
	^ #(Array OrderedCollection Set IdentitySet Dictionary IdentityDictionary Bag
		SortedCollection WeakArray WeakSet) asSet
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> domainClassNamesIn: aNode resolver: aBlock [
	"Every class named under aNode that is neither a value type nor a container, for
	when the outermost send says nothing, as in '(1 to: n) collect: [:i | SRFastCube new]'."
	| found |
	found := Set new.
	aNode nodesDo: [:each |
		(self classOf: each resolver: aBlock) ifNotNil: [:class |
			((self isValueType: class) or: [self containerNames includes: class name asSymbol])
				ifFalse: [found add: class name asString]]].
	^ found
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> fromClasses: aCollection named: aString [
	"Analyse every class in aCollection, live or from a SWACodeSnapshot."
	| data |
	data := self new setName: aString generated: true.
	aCollection do: [:each | data addAssociations: (self associationsOf: each) forClassNamed: each name asString].
	^ data
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> fromFile: aPath [
	^ self fromJsonString: (FileStream readOnlyFileNamed: aPath) contentsOfEntireFile
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> fromJson: aJsonObject [
	| data |
	data := self new setName: (aJsonObject at: 'name' ifAbsent: ['?']) generated: false.
	(aJsonObject at: 'associations' ifAbsent: [Dictionary new]) keysAndValuesDo: [:className :ivars | | dict |
		dict := Dictionary new.
		ivars keysAndValuesDo: [:ivar :pair | dict at: ivar put: {pair first asString. pair second asString}].
		data addAssociations: dict forClassNamed: className].
	^ data
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> fromJsonString: aString [
	^ self fromJson: (Json readFrom: aString readStream)
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> imageClassNamed: aString [
	^ (Smalltalk at: aString asSymbol ifAbsent: [nil]) ifNotNil: [:global |
		global isBehavior ifTrue: [global] ifFalse: [nil]]
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> isManyIn: aNode resolver: aBlock [
	aNode nodesDo: [:each |
		(each isKindOf: MessageNode) ifTrue: [
			(#(collect: select: reject: with:collect: copyWith:) includes: each selector key)
				ifTrue: [^ true]].
		(self classOf: each resolver: aBlock) ifNotNil: [:class |
			(self containerNames includes: class name asSymbol) ifTrue: [^ true]]].
	^ false
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> isValueType: aClass [
	"Value-like classes stay rows in the attribute compartment. Anything from the FFI
	bindings counts too: an RlMatrix ivar is a buffer, not a relationship with raylib."
	| category |
	(self valueTypeNames includes: aClass name asSymbol) ifTrue: [^ true].
	(aClass name beginsWith: 'Rl') ifTrue: [^ true].
	category := aClass category.
	^ category notNil
		and: [(category includesSubstring: 'Raylib') or: [category includesSubstring: 'OpenXR']]
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> parse: aString in: aBehavior [
	"Code from git may name ivars and classes the image no longer has. Resuming the
	notification with false leaves them unbound instead of declaring them in Undeclared."
	| context |
	context := (aBehavior respondsTo: #liveClass)
		ifTrue: [aBehavior liveClass ifNil: [aBehavior isMeta ifTrue: [Object class] ifFalse: [Object]]]
		ifFalse: [aBehavior].
	^ [[Parser new parse: aString class: context]
		on: UndeclaredVariableNotification do: [:notification | notification resume: false]]
			on: Error do: [:e | nil]
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> record: aNode into: aDictionary ivars: ivarNames resolver: aBlock [
	"Two shapes are worth reading: an assignment to an ivar, and an #add: sent TO an
	ivar -- the latter being the only way to learn a collection's element type, since
	the assignment itself only ever says OrderedCollection."
	| name |
	(aNode isKindOf: AssignmentNode) ifTrue: [
		name := self variableNameOf: aNode variable.
		(name notNil and: [ivarNames includes: name])
			ifTrue: [self recordAssignment: aNode value for: name into: aDictionary resolver: aBlock].
		^ self].
	(aNode isKindOf: MessageNode) ifFalse: [^ self].
	(#(add: addAll: addFirst: addLast: at:put:) includes: aNode selector key) ifFalse: [^ self].
	name := self variableNameOf: aNode receiver.
	(name notNil and: [ivarNames includes: name]) ifFalse: [^ self].
	aNode arguments do: [:arg |
		(self domainClassNamesIn: arg resolver: aBlock) do: [:each |
			aDictionary at: name put: {each. '*'}]].
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> recordAssignment: aValueNode for: anIvarName into: aDictionary resolver: aBlock [
	| target inner |
	target := self classOf: (self rootReceiverOf: aValueNode) resolver: aBlock.
	target ifNotNil: [
		(self isValueType: target) ifTrue: [^ self].
		(self containerNames includes: target name asSymbol)
			ifFalse: [^ aDictionary at: anIvarName put: {target name asString. '1'}]].
	inner := self domainClassNamesIn: aValueNode resolver: aBlock.
	inner size = 1 ifTrue: [
		aDictionary
			at: anIvarName
			put: {inner anyOne. (self isManyIn: aValueNode resolver: aBlock) ifTrue: ['*'] ifFalse: ['1']}].
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> resolverFor: aClass [
	"Class names resolve in the snapshot a class came from first, then in the image."
	(aClass respondsTo: #snapshot) ifFalse: [^ [:className | self imageClassNamed: className]].
	^ [:className |
		(aClass snapshot classNamed: className) ifNil: [self imageClassNamed: className]]
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> rootReceiverOf: aNode [
	"Down the receiver chain, so 'SRHand left avatar: self' answers the node for SRHand."
	| current |
	current := aNode.
	[(current isKindOf: MessageNode) or: [current isKindOf: CascadeNode]]
		whileTrue: [current := current receiver].
	^ current
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData class >> valueTypeNames [
	"Without these almost every edge would point at Vector3 or Color and say nothing."
	^ #(Vector3 Vector2 Quaternion Matrix4x4 Color Point Rectangle Form Symbol String
		ByteString Number Integer Float Fraction Boolean Character Date Time Interval
		Association WriteStream ReadStream Semaphore Process) asSet
]

{
	#category : #analysis,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:17'
}
SWACompositionData class >> variableNameOf: aNode [
	"Squeak wraps each use of a variable in a VariableUsageNode."
	| node |
	node := ((aNode respondsTo: #isVariableUsage) and: [aNode isVariableUsage])
		ifTrue: [aNode realNode]
		ifFalse: [aNode].
	^ (node isKindOf: VariableNode) ifTrue: [node name asString] ifFalse: [nil]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWACompositionData >> addAssociations: aDictionary forClassNamed: aClassName [
	aDictionary isEmpty ifTrue: [^ self].
	associations at: aClassName put: aDictionary.
	incoming := nil.
	maxDegree := nil.
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> asJsonString [
	| assocs dict |
	assocs := Dictionary new.
	associations keysAndValuesDo: [:className :ivars | | dict2 |
		dict2 := Dictionary new.
		ivars keysAndValuesDo: [:ivar :pair | dict2 at: ivar put: pair asArray].
		assocs at: className put: dict2].
	dict := Dictionary new
		at: 'format' put: 'SWACompositionData/1';
		at: 'name' put: name;
		at: 'associations' put: assocs;
		yourself.
	^ String streamContents: [:stream | dict jsonWriteOn: stream]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> associationCount [
	^ associations inject: 0 into: [:sum :each | sum + each size]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> associationsForClassNamed: aClassName [
	^ associations at: aClassName ifAbsent: [Dictionary new]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> classNames [
	| names |
	names := associations keys asSet.
	associations do: [:ivars | ivars do: [:pair | names add: pair first]].
	^ names
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> degreeForKey: aKey [
	"Classes aKey is associated with, either way; nil for anything that is not a class key."
	| degree |
	(self isClassKey: aKey) ifFalse: [^ nil].
	degree := (self usesFor: aKey) size + (self usedByFor: aKey) size.
	^ degree = 0 ifTrue: [nil] ifFalse: [degree]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> isClassKey: aKey [
	^ aKey notNil and: [(aKey includesSubstring: '>>') not and: [(aKey includesSubstring: ' ') not]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> isGenerated [
	"Analysed for the view showing it, rather than loaded from a file."
	^ generated == true
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> linksForKey: aKey [
	"score -> partner key, in the form SWADatasetMetric>>linksForKey: answers."
	aKey ifNil: [^ #()].
	^ ((self associationsForClassNamed: aKey) values collect: [:pair | 1.0 -> pair first]) asArray
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> locForKey: aKey [
	"Gives every association link the same width; there is no size to an association."
	^ 8
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWACompositionData >> maxDegree [
	^ maxDegree ifNil: [maxDegree := self maxOf: #degreeForKey:]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> maxOf: aSelector [
	^ self classNames inject: 1 into: [:max :each | max max: ((self perform: aSelector with: each) ifNil: [0])]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> name [
	^ name
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> printOn: aStream [
	aStream nextPutAll: 'SWACompositionData('; nextPutAll: (name ifNil: ['?']); nextPutAll: ', ';
		print: self associationCount; nextPutAll: ' associations)'.
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> roleColorForKey: aKey [
	"Hue says which way a class's associations point -- blue: held by others, orange:
	holds others, magenta: both. Saturation and brightness grow with how many."
	| uses usedBy degree strength hue |
	(self degreeForKey: aKey) ifNil: [^ nil].
	uses := (self usesFor: aKey) size.
	usedBy := (self usedByFor: aKey) size.
	degree := uses + usedBy.
	strength := (degree + 1) ln / (self maxDegree + 1) ln.
	hue := (210 + (uses / degree * 180)) \\ 360.
	^ Color h: hue s: 0.35 + (strength * 0.5) v: 0.55 + (strength * 0.4)
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> setName: aString generated: aBoolean [
	name := aString.
	generated := aBoolean.
	associations := Dictionary new.
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> usedByFor: aClassName [
	incoming ifNil: [
		incoming := Dictionary new.
		associations keysAndValuesDo: [:className :ivars |
			ivars do: [:pair | (incoming at: pair first ifAbsentPut: [Set new]) add: className]]].
	^ incoming at: aClassName ifAbsent: [#()]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> usedByForKey: aKey [
	| count |
	(self isClassKey: aKey) ifFalse: [^ nil].
	count := (self usedByFor: aKey) size.
	^ count = 0 ifTrue: [nil] ifFalse: [count]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> usesFor: aClassName [
	"The distinct classes aClassName holds: two ivars holding an SRHand are one class used."
	^ ((self associationsForClassNamed: aClassName) values collect: [:pair | pair first]) asSet
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:25'
}
SWACompositionData >> usesForKey: aKey [
	| count |
	(self isClassKey: aKey) ifFalse: [^ nil].
	count := (self usesFor: aKey) size.
	^ count = 0 ifTrue: [nil] ifFalse: [count]
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:16'
}
SWACompositionData >> writeToFile: aPath [
	(FileStream forceNewFileNamed: aPath)
		nextPutAll: self asJsonString;
		close.
]
