"
A SWACodeNode whose subject is a PackageInfo. Children are SWACodeClassNodes for the package's classes.
"
Class {
	#name : #SWACodePackageNode,
	#superclass : #SWACodeNode,
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodePackageNode class >> named: aPackageName [
	"Build a package node for the named package, e.g. 'SWA-SpaceTally'."
	^ self on: (PackageInfo named: aPackageName)
]

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodePackageNode >> browse [
	^ subject browse
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodePackageNode >> buildChildren [
	"One SWACodeClassNode per class in the package, sorted by name."
	| classes |
	classes := subject classes asSortedCollection: [:a :b | a name <= b name].
	^ (classes collect: [:cls | SWACodeClassNode on: cls parent: self]) asOrderedCollection
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:59'
}
SWACodePackageNode >> clusterGraph [
	"UML-ish class diagram using subgraph clusters: each class is a cluster box
	(label on TOP) containing one node per method, stacked vertically in declared
	order (instance then static). Methods stay individually clickable -> browse
	method. Each cluster has a hidden TOP anchor; the inheritance edge leaves a
	subclass from its top anchor and points (hollow arrowhead, UML) up at the
	superclass cluster, so arrows exit the TOP of the box. rankdir=TB so labels
	honour labelloc=t. Edges are orthogonal. Answer { dotString. ids. truncated }."
	| dot ids classNodes byName externalIds topAnchorIds |
	classNodes := self children.
	byName := Dictionary new.
	classNodes do: [:cn | byName at: cn name put: cn].
	ids := IdentityDictionary new.
	externalIds := Dictionary new.
	topAnchorIds := Dictionary new.
	dot := WriteStream on: String new.
	dot nextPutAll: 'digraph classes {'; nextPut: Character lf.
	dot nextPutAll: '  rankdir=TB;'; nextPut: Character lf.
	dot nextPutAll: '  compound=true;'; nextPut: Character lf.
	dot nextPutAll: '  splines=ortho;'; nextPut: Character lf.
	dot nextPutAll: '  node [shape=box, fontname="Helvetica", fontsize=9];'; nextPut: Character lf.
	classNodes do: [:cn | | topAnchor methods chain prev |
		ids at: cn put: cn dotId.
		topAnchor := 'top', cn dotId.
		topAnchorIds at: cn name put: topAnchor.
		dot
			nextPutAll: '  subgraph cluster_'; nextPutAll: cn dotId; nextPutAll: ' {'; nextPut: Character lf;
			nextPutAll: '    label="'; nextPutAll: (SWACodeNode dotEscape: cn name); nextPutAll: '";'; nextPut: Character lf;
			nextPutAll: '    labelloc=t;'; nextPut: Character lf;
			nextPutAll: '    style=filled; fillcolor="#eef6ee"; fontname="Helvetica-Bold";'; nextPut: Character lf;
			nextPutAll: '    '; nextPutAll: topAnchor; nextPutAll: ' [shape=point, style=invis, width=0];'; nextPut: Character lf.
		methods := cn methodNodes.
		methods do: [:m |
			ids at: m put: m dotId.
			dot
				nextPutAll: '    '; nextPutAll: m dotId;
				nextPutAll: ' [label="'; nextPutAll: (m isStatic ifTrue: ['$'] ifFalse: ['']);
				nextPutAll: (SWACodeNode dotEscape: m name, ' (', m loc printString, ')');
				nextPutAll: '", style=filled, fillcolor="'; nextPutAll: (m isStatic ifTrue: ['#e6d5f5'] ifFalse: ['#ffffff']);
				nextPutAll: '"];'; nextPut: Character lf].
		"rankdir=TB: source is HIGHER. Put the top anchor first, then methods in
		declared order, so the anchor is at the very top (just under the label) and
		methods stack below it. Inheritance edges leave from this top anchor."
		chain := (Array with: topAnchor), (methods collect: [:m | m dotId]).
		prev := nil.
		chain do: [:nodeId |
			prev ifNotNil: [
				dot nextPutAll: '    '; nextPutAll: prev; nextPutAll: ' -> '; nextPutAll: nodeId;
					nextPutAll: ' [style=invis, weight=100];'; nextPut: Character lf].
			prev := nodeId].
		dot nextPutAll: '  }'; nextPut: Character lf].
	classNodes do: [:cn | | superName superTarget ltail |
		superName := cn superclassName.
		superName ifNotNil: [
			superTarget := (topAnchorIds includesKey: superName)
				ifTrue: [topAnchorIds at: superName]
				ifFalse: [externalIds at: superName ifAbsentPut: [
					| eid |
					eid := 'ext', externalIds size printString.
					dot
						nextPutAll: '  '; nextPutAll: eid;
						nextPutAll: ' [label="'; nextPutAll: (SWACodeNode dotEscape: superName);
						nextPutAll: '", style="filled,dashed", fillcolor="#f0f0f0"];';
						nextPut: Character lf.
					eid]].
			"Edge from subclass top anchor up to the superclass (cluster border via
			lhead). Hollow UML arrowhead points at the super."
			ltail := (topAnchorIds includesKey: superName)
				ifTrue: [', lhead=cluster_', (byName at: superName) dotId]
				ifFalse: [''].
			dot
				nextPutAll: '  '; nextPutAll: (topAnchorIds at: cn name);
				nextPutAll: ' -> '; nextPutAll: superTarget;
				nextPutAll: ' [arrowhead=onormal, ltail=cluster_'; nextPutAll: cn dotId;
				nextPutAll: ltail; nextPutAll: '];'; nextPut: Character lf]].
	dot nextPutAll: '}'; nextPut: Character lf.
	^ { dot contents. ids. false }
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:03'
}
SWACodePackageNode >> inheritanceGraph [
	"Build a Graphviz DOT graph showing the package's classes as boxes with
	child -> superclass arrows (UML-style, rankdir=BT so roots sit on top).
	Superclasses outside the package are drawn as light 'external' boxes.
	Answer { dotString. ids. truncated } for GraphvizPane click mapping."
	| dot ids classNodes byName externalIds |
	classNodes := self children.   "SWACodeClassNodes"
	byName := Dictionary new.
	classNodes do: [:cn | byName at: cn name put: cn].
	ids := IdentityDictionary new.
	externalIds := Dictionary new.
	dot := WriteStream on: String new.
	dot nextPutAll: 'digraph inheritance {'; nextPut: Character lf.
	dot nextPutAll: '  rankdir=BT;'; nextPut: Character lf.
	dot nextPutAll: '  node [shape=box, fontname="Helvetica", fontsize=10];'; nextPut: Character lf.
	"In-package class boxes."
	classNodes do: [:cn |
		ids at: cn put: cn dotId.
		cn dotNodeStatementOn: dot].
	"Edges to superclasses; synthesize external boxes for out-of-package supers."
	classNodes do: [:cn | | superName targetId |
		superName := cn superclassName.
		superName ifNotNil: [
			targetId := (byName includesKey: superName)
				ifTrue: [(byName at: superName) dotId]
				ifFalse: [externalIds at: superName ifAbsentPut: [
					| eid |
					eid := 'ext', externalIds size printString.
					dot
						nextPutAll: '  '; nextPutAll: eid;
						nextPutAll: ' [label="'; nextPutAll: (SWACodeNode dotEscape: superName);
						nextPutAll: '", style="filled,dashed", fillcolor="#f0f0f0"];';
						nextPut: Character lf.
					eid]].
			dot
				nextPutAll: '  '; nextPutAll: cn dotId;
				nextPutAll: ' -> '; nextPutAll: targetId;
				nextPutAll: ' [arrowhead=onormal];'; nextPut: Character lf]].
	dot nextPutAll: '}'; nextPut: Character lf.
	^ { dot contents. ids. false }
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodePackageNode >> kind [
	^ #package
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodePackageNode >> name [
	^ subject packageName
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:09'
}
SWACodePackageNode >> openClusterGraph [
	"UML-ish class diagram with subgraph clusters (each method is its own box
	inside a class cluster). Click a method box -> browse that method."
	^ self
		openGraph: self clusterGraph
		engine: 'dot'
		label: 'Code Map: ', self name, '  (UML clusters)'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:03'
}
SWACodePackageNode >> openInheritanceGraph [
	"Open the class inheritance graph (child -> superclass arrows, roots on top)."
	^ self
		openGraph: self inheritanceGraph
		engine: 'dot'
		label: 'Code Map: ', self name, '  (inheritance)'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:09'
}
SWACodePackageNode >> openRecordGraph [
	"UML class diagram with record boxes (methods inside one box per class).
	Click a class box -> browse the class."
	^ self
		openGraph: self recordGraph
		engine: 'dot'
		label: 'Code Map: ', self name, '  (UML records)'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:12'
}
SWACodePackageNode >> recordGraph [
	"UML-style class diagram using DOT 'record' shapes: one box per class with its
	methods listed inside (instance methods, then static class-side methods),
	left-justified. Edges are inheritance (child -> superclass, rankdir=BT) drawn
	orthogonally. Each record is a single clickable node -> browse the class.
	Answer { dotString. ids. truncated }."
	| dot ids classNodes byName externalIds |
	classNodes := self children.
	byName := Dictionary new.
	classNodes do: [:cn | byName at: cn name put: cn].
	ids := IdentityDictionary new.
	externalIds := Dictionary new.
	dot := WriteStream on: String new.
	dot nextPutAll: 'digraph classes {'; nextPut: Character lf.
	dot nextPutAll: '  rankdir=BT;'; nextPut: Character lf.
	dot nextPutAll: '  splines=ortho;'; nextPut: Character lf.
	dot nextPutAll: '  node [shape=record, fontname="Helvetica", fontsize=10];'; nextPut: Character lf.
	classNodes do: [:cn |
		ids at: cn put: cn dotId.
		dot
			nextPutAll: '  '; nextPutAll: cn dotId;
			nextPutAll: ' [label="{'; nextPutAll: cn recordLabel;
			nextPutAll: '}", style=filled, fillcolor="#cde8cd"];'; nextPut: Character lf].
	classNodes do: [:cn | | superName targetId |
		superName := cn superclassName.
		superName ifNotNil: [
			targetId := (byName includesKey: superName)
				ifTrue: [(byName at: superName) dotId]
				ifFalse: [externalIds at: superName ifAbsentPut: [
					| eid |
					eid := 'ext', externalIds size printString.
					dot
						nextPutAll: '  '; nextPutAll: eid;
						nextPutAll: ' [label="'; nextPutAll: (SWACodeNode dotEscape: superName);
						nextPutAll: '", shape=box, style="filled,dashed", fillcolor="#f0f0f0"];';
						nextPut: Character lf.
					eid]].
			dot
				nextPutAll: '  '; nextPutAll: cn dotId;
				nextPutAll: ' -> '; nextPutAll: targetId;
				nextPutAll: ' [arrowhead=onormal];'; nextPut: Character lf]].
	dot nextPutAll: '}'; nextPut: Character lf.
	^ { dot contents. ids. false }
]
