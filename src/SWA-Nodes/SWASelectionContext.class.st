"
The neighbourhood of one selected class, method or instance variable, as crossRefKeys: what reaches it (senders, class references, holders by composition) and what it reaches (callees, referenced classes, held parts), up to a number of hops. The two directions are walked apart: a caller of a callee is a sibling, not a neighbour, and following both would take in most of the image.
"
Class {
	#name : #SWASelectionContext,
	#superclass : #Object,
	#instVars : [
		'hops',
		'includesTests',
		'fanOutLimit',
		'maxKeys',
		'composition',
		'roles',
		'distances',
		'classRoles',
		'skipped',
		'truncated',
		'fanIns',
		'anchorKeys',
		'scope',
		'edges',
		'edgeTargets',
		'edgeLabels',
		'partsCache',
		'anchorName'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:02'
}
SWASelectionContext class >> canAnchorOn: aKey [
	| probe |
	aKey ifNil: [^ false].
	probe := self on: aKey hops: 1 includesTests: true.
	^ (probe methodOfKey: aKey) notNil or: [(probe classOfKey: aKey) notNil or: [(probe ivarOfKey: aKey) notNil]]
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext class >> on: aKey hops: anInteger includesTests: aBoolean [
	^ self onAll: {aKey} hops: anInteger includesTests: aBoolean
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext class >> onAll: aCollectionOfKeys hops: anInteger includesTests: aBoolean [
	^ self new setAnchors: aCollectionOfKeys hops: anInteger includesTests: aBoolean
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:41'
}
SWASelectionContext class >> withMembers: aKey [
	"aKey and, when it names a class, every method of it, both sides: the context of a
	class is the context of what is in it."
	| probe class |
	probe := self on: aKey hops: 1 includesTests: true.
	class := (probe classOfKey: aKey) ifNil: [^ {aKey}].
	^ (OrderedCollection with: aKey)
		addAll: (class selectors asSortedCollection collect: [:each | probe keyOfClass: class selector: each]);
		addAll: (class classSide selectors asSortedCollection collect: [:each | probe keyOfClass: class classSide selector: each]);
		yourself
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> addCallee: aSelector of: aType into: aDictionary [
	"The method when the receiving class defines it, else just the class: the arrow goes
	to the class that receives the message, not to the superclass that implements it.
	Answers the key added, or nil."
	| method receiver key |
	receiver := aType theNonMetaClass name asString.
	method := (aType lookupSelector: aSelector) ifNil: [^ nil].
	(#(#ProtoObject #Object) includes: method methodClass theNonMetaClass name) ifTrue: [^ nil].
	key := method methodClass == aType
		ifTrue: [self keyOfClass: aType selector: aSelector]
		ifFalse: [receiver].
	aDictionary at: key put: receiver.
	^ key
]

{
	#category : #computing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:35'
}
SWASelectionContext >> addEdgeFrom: aUserKey to: aUsedKey [
	aUserKey = aUsedKey ifFalse: [edges add: aUserKey -> aUsedKey]
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext >> anchorFamilies [
	^ (anchorKeys collect: [:each | self familyOfKey: each]) asSet
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext >> anchorKey [
	"The anchor, when there is one; see #anchorLabel for a set of them."
	^ anchorKeys size = 1 ifTrue: [anchorKeys first] ifFalse: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext >> anchorKeys [
	^ anchorKeys
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:54'
}
SWASelectionContext >> anchorLabel [
	"A class with its methods is named as the class."
	| classes |
	anchorName ifNotNil: [^ anchorName].
	anchorKeys size = 1 ifTrue: [^ anchorKeys first].
	classes := (anchorKeys collect: [:each | self classNameOfKey: each]) asSet.
	(classes size = 1 and: [anchorKeys includes: classes anyOne]) ifTrue: [^ classes anyOne].
	^ anchorKeys size printString, ' changes'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:54'
}
SWASelectionContext >> anchorName: aStringOrNil [
	"What the anchors are called in the label, e.g. '7 marks'."
	anchorName := aStringOrNil
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> calleesOf: aSetOfKeys [
	"key -> the keys of aSetOfKeys that use it. The class each use goes through is kept
	in edgeTargets, see #classEdges."
	| result add kept |
	result := Dictionary new.
	edgeTargets ifNil: [edgeTargets := Dictionary new].
	add := [:key :source | (result at: key ifAbsentPut: [Set new]) add: source].
	aSetOfKeys do: [:key |
		(self methodOfKey: key) ifNotNil: [:method |
			(self calleesOfMethod: method) keysAndValuesDo: [:each :through |
				add value: each value: key.
				edgeTargets at: key -> each put: through]].
		(self classOfKey: key) ifNotNil: [:class |
			(self calleesOfClass: class) do: [:each | add value: each value: key]].
		(self ivarOfKey: key) ifNotNil: [:pair |
			(self partsOf: pair first) keysAndValuesDo: [:ivar :target |
				ivar = pair second ifTrue: [
					add value: target value: key.
					self label: 'holds' from: key to: target]]]].
	kept := self withoutGeneric: result keys asSet.
	result keys do: [:each | (kept includes: each) ifFalse: [result removeKey: each]].
	^ result
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:27'
}
SWASelectionContext >> calleesOfClass: aClass [
	"The classes its methods name and the ones it holds, not every method they send:
	for a whole class that would be most of what it touches. Its methods are still
	typed, for what the arrows say."
	| result user |
	result := Set new.
	user := aClass name asString.
	{aClass. aClass classSide} do: [:behavior |
		behavior methodsDo: [:method |
			self calleesOfMethod: method.
			(self classesNamedIn: method) do: [:each |
				result add: each name asString.
				self label: 'names' from: user to: each name asString]]].
	(self partsOf: aClass) do: [:each |
		result add: each.
		self label: 'holds' from: user to: each].
	result remove: user ifAbsent: [].
	^ result
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> calleesOfMethod: aCompiledMethod [
	"used key -> the class it is used through. A send lands where its receiver's type
	says; a receiver the code does not type gives nothing, rather than a guess. Sends to
	self and super run the class's own code, which the hierarchy already shows."
	| result class user tree temps sent |
	result := Dictionary new.
	class := aCompiledMethod methodClass.
	user := self keyOfClass: class selector: aCompiledMethod selector.
	tree := [aCompiledMethod methodNode] on: Error do: [:e | nil].
	temps := tree ifNil: [Dictionary new] ifNotNil: [self tempTypesIn: tree class: class].
	sent := aCompiledMethod messages.
	(self sendsIn: aCompiledMethod) do: [:send |
		((sent includes: send key) and: [(self isSelfOrSuper: send value) not]) ifTrue: [
			(self typeOf: send value in: class temps: temps depth: 0) ifNotNil: [:type |
				(self addCallee: send key of: type into: result) ifNotNil: [:key |
					self
						label: ((self isInstanceCreation: send key in: type) ifTrue: ['new'] ifFalse: ['calls ', send key])
						from: user to: key]]]].
	(self classesNamedIn: aCompiledMethod) do: [:each | | name |
		name := each name asString.
		result at: name put: name.
		self label: 'names' from: user to: name].
	result removeKey: class theNonMetaClass name asString ifAbsent: [].
	^ result
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:27'
}
SWASelectionContext >> callersOf: aSetOfKeys [
	"key -> the keys of aSetOfKeys it uses. A caller that names a class is typed like a
	touched method, so its arrow can say what it does with the class. Senders of the methods' selectors and
	references to the classes are found in one pass over the image; plus the accessors
	of instance variables and the composition holders."
	| wanted hits result add |
	wanted := IdentityDictionary new.
	result := Dictionary new.
	add := [:key :source | (result at: key ifAbsentPut: [Set new]) add: source].
	aSetOfKeys do: [:key |
		(self methodOfKey: key) ifNotNil: [:method |
			(wanted at: method selector ifAbsentPut: [Set new]) add: key].
		(self classOfKey: key) ifNotNil: [:class |
			(wanted at: class binding ifAbsentPut: [Set new]) add: key.
			composition ifNotNil: [
				(composition usedByFor: class name asString) do: [:holder |
					add value: holder value: key.
					self label: 'holds' from: holder to: key]]].
		(self ivarOfKey: key) ifNotNil: [:pair |
			(pair first whichSelectorsAccess: pair second) do: [:selector |
				| accessor |
				accessor := self keyOfClass: pair first selector: selector.
				add value: accessor value: key.
				self label: 'accesses' from: accessor to: key]]].
	wanted isEmpty ifTrue: [^ result].
	hits := IdentityDictionary new.
	SystemNavigation default allBehaviorsDo: [:behavior |
		behavior selectorsAndMethodsDo: [:selector :method |
			1 to: method numLiterals - 2 do: [:index | | literal |
				literal := method literalAt: index.
				(wanted includesKey: literal) ifTrue: [
					(hits at: literal ifAbsentPut: [Set new]) add: (self keyOfClass: behavior selector: selector)]]]].
	hits keysAndValuesDo: [:literal :callers |
		(literal isSymbol and: [callers size > fanOutLimit])
			ifTrue: [skipped add: '#', literal, ' (', callers size printString, ' senders)']
			ifFalse: [callers do: [:caller |
				literal isSymbol ifFalse: [
					(self methodOfKey: caller) ifNotNil: [:method | self calleesOfMethod: method]].
				(wanted at: literal) do: [:source |
					add value: caller value: source.
					self
						label: (literal isSymbol ifTrue: ['calls ', literal] ifFalse: ['names'])
						from: caller to: source]]]].
	^ result
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:27'
}
SWASelectionContext >> classEdges [
	"{user class. used class. role. label}, one per pair of classes; the role is the one
	of the end that is not an anchor, #anchor when both are. The label sums up every use
	found between the two, see #usageLabelFor:."
	| roleByPair labelsByPair classOf |
	roleByPair := Dictionary new.
	labelsByPair := Dictionary new.
	classOf := [:edge | (edgeTargets ifNotNil: [:targets | targets at: edge ifAbsent: [nil]])
		ifNil: [self classNameOfKey: edge value]].
	edges do: [:edge | | from to |
		from := self classNameOfKey: edge key.
		to := classOf value: edge.
		from = to ifFalse: [
			roleByPair at: from -> to ifAbsentPut: [
				(roles at: edge value ifAbsent: [nil]) == #anchor
					ifTrue: [(roles at: edge key ifAbsent: [nil]) == #anchor ifTrue: [#anchor] ifFalse: [#caller]]
					ifFalse: [#callee]]]].
	edgeLabels keysAndValuesDo: [:edge :labels |
		(labelsByPair at: (self classNameOfKey: edge key) -> (classOf value: edge) ifAbsentPut: [Set new])
			addAll: labels].
	^ roleByPair associations collect: [:each |
		{each key key. each key value. each value. self usageLabelFor: (labelsByPair at: each key ifAbsent: [#()])}]
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> classNameOfKey: aKey [
	"'Foo>>bar', 'Foo class>>bar', 'Foo>>#ivar', 'Foo (comment)' and 'Foo' all name Foo."
	| name |
	name := (aKey includesSubstring: '>>') ifTrue: [aKey copyUpTo: $>] ifFalse: [aKey].
	(name endsWith: ' (comment)') ifTrue: [name := name allButLast: 10].
	(name endsWith: ' class') ifTrue: [name := name allButLast: 6].
	^ name
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:58'
}
SWASelectionContext >> classOfKey: aKey [
	(aKey includesSubstring: '>>') ifTrue: [^ nil].
	^ (Smalltalk classNamed: (self classNameOfKey: aKey))
		ifNotNil: [:class | class isBehavior ifTrue: [class] ifFalse: [nil]]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> classRoleAt: aClassName [
	"The role of the nearest key in the class, as role -> distance; nil outside."
	^ classRoles at: aClassName ifAbsent: [nil]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> classes [
	^ (classRoles keys collect: [:name | Smalltalk classNamed: name]) reject: [:each | each isNil]
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> classesNamedIn: aCompiledMethod [
	| result |
	result := OrderedCollection new.
	1 to: aCompiledMethod numLiterals - 2 do: [:index | | literal |
		literal := aCompiledMethod literalAt: index.
		(literal isVariableBinding and: [literal value isBehavior])
			ifTrue: [result add: literal value theNonMetaClass]].
	^ result
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> composition: aCompositionDataOrNil [
	"Holders are read from it, so its classes are the ones a holder can be found among."
	composition := aCompositionDataOrNil
]

{
	#category : #computing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> compute [
	roles removeAll.
	distances removeAll.
	skipped removeAll.
	edges := Set new.
	edgeTargets := Dictionary new.
	edgeLabels := Dictionary new.
	truncated := false.
	anchorKeys do: [:each | self record: each role: #anchor distance: 0].
	self walk: #caller.
	self walk: #callee.
	self computeClassRoles
]

{
	#category : #computing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> computeClassRoles [
	classRoles := Dictionary new.
	roles keysAndValuesDo: [:key :role | | name distance known |
		name := self classNameOfKey: key.
		distance := distances at: key.
		known := classRoles at: name ifAbsent: [nil].
		(known isNil or: [role == #anchor or: [known key ~~ #anchor and: [distance < known value]]])
			ifTrue: [classRoles at: name put: role -> distance]]
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:58'
}
SWASelectionContext >> countFanInsOf: aCollectionOfClassNames [
	"How many classes name each class, counted in one pass over the image."
	| bindings counts |
	bindings := IdentityDictionary new.
	aCollectionOfClassNames do: [:name |
		(fanIns includesKey: name) ifFalse: [
			(Smalltalk classNamed: name) ifNotNil: [:class |
				class isBehavior ifTrue: [bindings at: class binding put: name]]]].
	bindings isEmpty ifTrue: [^ self].
	counts := Dictionary new.
	SystemNavigation default allBehaviorsDo: [:behavior | | named |
		named := IdentitySet new.
		behavior methodsDo: [:method |
			1 to: method numLiterals - 2 do: [:index |
				(bindings at: (method literalAt: index) ifAbsent: [nil]) ifNotNil: [:name | named add: name]]].
		named do: [:name | (counts at: name ifAbsentPut: [IdentitySet new]) add: behavior theNonMetaClass]].
	bindings do: [:name | fanIns at: name put: (counts at: name ifAbsent: [#()]) size]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> distanceAt: aKey [
	^ distances at: aKey ifAbsent: [nil]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:35'
}
SWASelectionContext >> edges [
	"Associations user key -> used key."
	^ edges ifNil: [#()]
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:59'
}
SWASelectionContext >> familyOfKey: aKey [
	"'SqueakXR' for a class in 'SqueakXR-Objects'."
	^ (Smalltalk classNamed: (self classNameOfKey: aKey))
		ifNotNil: [:class | class isBehavior ifTrue: [(class category ifNil: ['']) copyUpTo: $-]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> fanOutLimit: anInteger [
	"A selector with more senders or implementors than this is too generic to say
	anything about the selection, and is skipped."
	fanOutLimit := anInteger
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> hops [
	^ hops
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:24'
}
SWASelectionContext >> includesClassNamed: aClassName [
	^ classRoles includesKey: aClassName
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> includesKey: aKey [
	^ roles includesKey: aKey
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> includesTests [
	^ includesTests
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:35'
}
SWASelectionContext >> isAnchorClass: aClassName [
	"Whether something selected or changed lives in the class."
	^ (classRoles at: aClassName ifAbsent: [nil])
		ifNil: [false]
		ifNotNil: [:role | role key == #anchor]
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext >> isInAnchorFamily: aKey [
	^ self anchorFamilies includes: (self familyOfKey: aKey)
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> isInstanceCreation: aSelector in: aMetaclass [
	| method |
	aMetaclass isMeta ifFalse: [^ false].
	(#(#new #new: #basicNew #basicNew:) includes: aSelector) ifTrue: [^ true].
	method := (aMetaclass lookupSelector: aSelector) ifNil: [^ false].
	^ ((method methodClass organization categoryOfElement: aSelector) ifNil: ['']) asString
		includesSubstring: 'instance creation'
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:54'
}
SWASelectionContext >> isSelfOrSuper: aNode [
	| node |
	node := self realNodeOf: aNode.
	^ (node respondsTo: #isSelfPseudoVariable)
		and: [node isSelfPseudoVariable or: [node isSuperPseudoVariable]]
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:58'
}
SWASelectionContext >> isTestKey: aKey [
	^ (Smalltalk classNamed: (self classNameOfKey: aKey))
		ifNil: [false]
		ifNotNil: [:class | class isBehavior and: [class inheritsFrom: TestCase]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> isTruncated [
	^ truncated
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:58'
}
SWASelectionContext >> ivarOfKey: aKey [
	"{class. ivar name} for 'Foo>>#ivar', else nil."
	| index class |
	index := aKey indexOfSubCollection: '>>#'.
	index = 0 ifTrue: [^ nil].
	class := (Smalltalk classNamed: (aKey first: index - 1)) ifNil: [^ nil].
	^ {class. aKey allButFirst: index + 2}
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> keyOfClass: aBehavior selector: aSymbol [
	^ aBehavior name asString, '>>', aSymbol
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> keys [
	^ roles keys
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:13'
}
SWASelectionContext >> label [
	^ 'context of ', self anchorLabel, ': ', hops printString, (hops = 1 ifTrue: [' hop, '] ifFalse: [' hops, ']),
		classRoles size printString, ' classes, ', self memberCount printString, ' members',
		(includesTests ifTrue: [', with tests'] ifFalse: ['']),
		(truncated ifTrue: [', cut at ', maxKeys printString] ifFalse: [''])
]

{
	#category : #computing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> label: aString from: aUserKey to: aUsedKey [
	"How aUserKey uses aUsedKey: 'new', 'names', 'holds', 'accesses', or 'calls' with the
	selector."
	(edgeLabels at: aUserKey -> aUsedKey ifAbsentPut: [Set new]) add: aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> maxKeys: anInteger [
	maxKeys := anInteger
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> memberCount [
	^ (roles keys select: [:each | each includesSubstring: '>>']) size
]

{
	#category : #keys,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:58'
}
SWASelectionContext >> methodOfKey: aKey [
	| class selector |
	(aKey includesSubstring: '>>') ifFalse: [^ nil].
	selector := aKey copyAfter: $>.
	selector := selector copyAfter: $>.
	(selector isEmpty or: [selector first = $#]) ifTrue: [^ nil].
	class := Smalltalk classNamed: (aKey copyUpTo: $>).
	class ifNil: [^ nil].
	^ class compiledMethodAt: selector asSymbol ifAbsent: [nil]
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:27'
}
SWASelectionContext >> partsOf: aClass [
	"ivar name -> name of the class it holds. Cached: the typing asks for every
	instance variable it meets."
	partsCache ifNil: [partsCache := IdentityDictionary new].
	^ partsCache at: aClass ifAbsentPut: [ | associations result |
		associations := (composition notNil and: [(composition associationsForClassNamed: aClass name asString) notEmpty])
			ifTrue: [composition associationsForClassNamed: aClass name asString]
			ifFalse: [[SWACompositionData associationsOf: aClass] on: Error do: [:e | Dictionary new]].
		result := Dictionary new.
		associations keysAndValuesDo: [:ivar :pair | result at: ivar put: pair first].
		result]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> printOn: aStream [
	aStream nextPutAll: self class name; nextPutAll: '('; nextPutAll: self label; nextPutAll: ')'
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:54'
}
SWASelectionContext >> realNodeOf: aNode [
	^ (aNode notNil and: [aNode respondsTo: #realNode]) ifTrue: [aNode realNode] ifFalse: [aNode]
]

{
	#category : #computing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:24'
}
SWASelectionContext >> record: aKey role: aRole distance: anInteger [
	"Answers whether aKey is new, i.e. whether the walk goes on from it."
	(roles includesKey: aKey) ifTrue: [^ false].
	(includesTests not and: [self isTestKey: aKey]) ifTrue: [^ false].
	(aRole ~~ #anchor and: [scope notNil and: [(scope includes: (self classNameOfKey: aKey)) not]])
		ifTrue: [^ false].
	roles size >= maxKeys ifTrue: [truncated := true. ^ false].
	roles at: aKey put: aRole.
	distances at: aKey put: anInteger.
	^ true
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:54'
}
SWASelectionContext >> returnTypeOf: aMethod in: aType depth: anInteger [
	"Followed for a method whose body is one return: an accessor, or a delegation like
	SRPlane>>material ^ meshObject material."
	| tree statements |
	anInteger >= 3 ifTrue: [^ nil].
	(#(#ProtoObject #Object) includes: aMethod methodClass theNonMetaClass name) ifTrue: [^ nil].
	aMethod isReturnSelf ifTrue: [^ aType].
	aMethod isReturnField ifTrue: [
		^ aType isMeta ifTrue: [nil] ifFalse: [
			self typeOfIvar: (aMethod methodClass allInstVarNames at: aMethod returnField + 1) in: aType]].
	tree := [aMethod methodNode] on: Error do: [:e | ^ nil].
	statements := tree block statements.
	(statements size = 1 and: [statements first isKindOf: ReturnNode]) ifFalse: [^ nil].
	^ self typeOf: statements first expr in: aType temps: Dictionary new depth: anInteger + 1
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> roleAt: aKey [
	"#anchor, #caller or #callee; nil outside the context."
	^ roles at: aKey ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:24'
}
SWASelectionContext >> scope: aSetOfClassNamesOrNil [
	"The classes the view shows. The context is a subset of them; nil leaves it open,
	and the walk downstream then stays in the anchors' package families instead."
	scope := aSetOfClassNamesOrNil
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:00'
}
SWASelectionContext >> sendsIn: aCompiledMethod [
	"selector -> receiver node of every send; a cascade lends its receiver to its parts."
	| sends tree |
	sends := OrderedCollection new.
	tree := [aCompiledMethod methodNode] on: Error do: [:e |
		^ aCompiledMethod messages asArray collect: [:each | each -> nil]].
	tree nodesDo: [:node |
		(node isKindOf: CascadeNode) ifTrue: [
			node messages do: [:each | sends add: each selector key -> node receiver]].
		((node isKindOf: MessageNode) and: [node receiver notNil])
			ifTrue: [sends add: node selector key -> node receiver]].
	^ sends
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:18'
}
SWASelectionContext >> setAnchors: aCollectionOfKeys hops: anInteger includesTests: aBoolean [
	anchorKeys := aCollectionOfKeys asOrderedCollection.
	hops := anInteger.
	includesTests := aBoolean.
	fanOutLimit := 25.
	maxKeys := 400.
	roles := Dictionary new.
	distances := Dictionary new.
	classRoles := Dictionary new.
	skipped := OrderedCollection new.
	fanIns := Dictionary new.
	truncated := false.
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:35'
}
SWASelectionContext >> showsMember: aKey [
	"A member belongs in the view when it is in the context, or when its class is one
	of the anchors': that class is shown whole, at the depth the view is at."
	^ (roles includesKey: aKey) or: [self isAnchorClass: (self classNameOfKey: aKey)]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 16:57'
}
SWASelectionContext >> skipped [
	"Descriptions of the generic selectors left out, for the info line."
	^ skipped
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:54'
}
SWASelectionContext >> tempTypesIn: aMethodNode class: aClass [
	"Temporary name -> the type of what is assigned to it. Twice round, so a temp
	assigned from another temp is typed whatever the order."
	| types |
	types := Dictionary new.
	2 timesRepeat: [
		aMethodNode nodesDo: [:node | | variable |
			(node isKindOf: AssignmentNode) ifTrue: [
				variable := self realNodeOf: node variable.
				(variable isKindOf: TempVariableNode) ifTrue: [
					(self typeOf: node value in: aClass temps: types depth: 0)
						ifNotNil: [:type | types at: variable name put: type]]]]].
	^ types
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:54'
}
SWASelectionContext >> typeOf: aNode in: aClass temps: aDictionary depth: anInteger [
	"The class of what aNode evaluates to in a method run by an instance of aClass, or
	nil when the code does not say. A metaclass stands for the class itself."
	| node |
	node := (self realNodeOf: aNode) ifNil: [^ nil].
	(node isKindOf: AssignmentNode) ifTrue: [
		^ self typeOf: node value in: aClass temps: aDictionary depth: anInteger].
	(node isKindOf: CascadeNode) ifTrue: [
		^ node messages last selector key == #yourself
			ifTrue: [self typeOf: node receiver in: aClass temps: aDictionary depth: anInteger]
			ifFalse: [nil]].
	(node isKindOf: MessageNode) ifTrue: [
		^ self
			typeOfSend: node selector key
			to: (self typeOf: node receiver in: aClass temps: aDictionary depth: anInteger)
			depth: anInteger].
	(node isKindOf: TempVariableNode) ifTrue: [^ aDictionary at: node name ifAbsent: [nil]].
	(node isKindOf: InstanceVariableNode) ifTrue: [
		^ aClass isMeta ifTrue: [nil] ifFalse: [self typeOfIvar: node name in: aClass]].
	((node isKindOf: LiteralVariableNode) and: [node key isVariableBinding and: [node key value isBehavior]])
		ifTrue: [^ node key value class].
	(node respondsTo: #isSelfPseudoVariable) ifFalse: [^ nil].
	node isSelfPseudoVariable ifTrue: [^ aClass].
	node isSuperPseudoVariable ifTrue: [^ aClass superclass].
	^ nil
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:54'
}
SWASelectionContext >> typeOfIvar: anIvarName in: aClass [
	"What composition says the instance variable holds, where it is assigned."
	aClass withAllSuperclasses do: [:each |
		(#(#ProtoObject #Object) includes: each name) ifTrue: [^ nil].
		((self partsOf: each) at: anIvarName ifAbsent: [nil]) ifNotNil: [:name |
			^ (Smalltalk classNamed: name) ifNotNil: [:class | class isBehavior ifTrue: [class]]]].
	^ nil
]

{
	#category : #typing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> typeOfSend: aSelector to: aType depth: anInteger [
	"Instance creation answers an instance; #yourself and #ifNil: their receiver; any
	other method the type of its single return expression."
	| method |
	aType ifNil: [^ nil].
	(#(#yourself #ifNil: #ifNil:ifNotNil:) includes: aSelector) ifTrue: [^ aType].
	method := (aType lookupSelector: aSelector) ifNil: [^ nil].
	(self isInstanceCreation: aSelector in: aType) ifTrue: [^ aType theNonMetaClass].
	^ self returnTypeOf: method in: aType depth: anInteger
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 18:26'
}
SWASelectionContext >> usageLabelFor: aSetOfLabels [
	"'holds, new, calls rebuild, step: +2'. Naming the class says nothing more once a
	more specific use is known."
	| selectors parts |
	selectors := ((aSetOfLabels select: [:each | each beginsWith: 'calls ']) collect: [:each | each allButFirst: 6])
		asSortedCollection asArray.
	parts := OrderedCollection new.
	#('holds' 'new' 'accesses') do: [:each | (aSetOfLabels includes: each) ifTrue: [parts add: each]].
	selectors isEmpty ifFalse: [
		parts add: 'calls ', ((selectors first: (selectors size min: 2)) inject: '' into: [:all :each |
			all isEmpty ifTrue: [each] ifFalse: [all, ', ', each]]),
			(selectors size > 2 ifTrue: [' +', (selectors size - 2) printString] ifFalse: [''])].
	(parts isEmpty and: [aSetOfLabels includes: 'names']) ifTrue: [parts add: 'names'].
	^ parts inject: '' into: [:all :each | all isEmpty ifTrue: [each] ifFalse: [all, ', ', each]]
]

{
	#category : #computing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:35'
}
SWASelectionContext >> walk: aRole [
	"Every key found remembers the keys it was found from, as an edge in the direction
	of use: a caller uses the key it reached, the key uses its callee. Without a scope,
	the walk downstream only goes on inside the anchors' package families: what a
	library class uses is the library's business, not the selection's."
	| frontier |
	frontier := (anchorKeys select: [:each | roles includesKey: each]) asSet.
	1 to: hops do: [:distance | | next |
		next := Set new.
		((aRole == #caller) ifTrue: [self callersOf: frontier] ifFalse: [self calleesOf: frontier])
			keysAndValuesDo: [:key :sources | | isNew |
				isNew := self record: key role: aRole distance: distance.
				(roles includesKey: key) ifTrue: [
					sources do: [:source |
						aRole == #caller
							ifTrue: [self addEdgeFrom: key to: source]
							ifFalse: [self addEdgeFrom: source to: key]]].
				(isNew and: [aRole == #caller or: [scope notNil or: [self isInAnchorFamily: key]]])
					ifTrue: [next add: key]].
		frontier := next.
		frontier isEmpty ifTrue: [^ self]]
]

{
	#category : #relations,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/27/2026 17:24'
}
SWASelectionContext >> withoutGeneric: aSetOfKeys [
	"Leave out what lives in a class named by more classes than fanOutLimit: Color or
	OrderedCollection reach everything, so they say nothing about the selection.
	A scope already keeps the library out."
	| generic |
	scope ifNotNil: [^ aSetOfKeys].
	self countFanInsOf: ((aSetOfKeys collect: [:key | self classNameOfKey: key]) reject: [:name | roles includesKey: name]).
	generic := Set new.
	^ aSetOfKeys reject: [:key | | name |
		name := self classNameOfKey: key.
		((fanIns at: name ifAbsent: [0]) > fanOutLimit)
			and: [(roles includesKey: name) not]
			and: [(generic includes: name)
				or: [generic add: name.
					skipped add: name, ' (named by ', (fanIns at: name) printString, ' classes)'.
					true]]]
]
