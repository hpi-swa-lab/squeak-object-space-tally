"
Tests for GraphvizPlainParser, covering the 'graph' and 'node' record parsing
and the inch->pixel coordinate mapping (including Y-axis flip).
"
Class {
	#name : #GraphvizPlainParserTest,
	#superclass : #TestCase,
	#category : #'SWA-Tools',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParserTest >> samplePlain [
	"Real 'dot -Tplain' output for the LR sample graph A->B, A->C, B->D, C->D, D->A."
	^ 'graph 1 2.5055 1.4139
node A 0.25 0.41386 0.5 0.5 A filled circle black lightblue
node B 1.25 1.1639 0.5 0.5 B filled circle black lightblue
node C 1.25 0.41386 0.5 0.5 C filled circle black lightblue
node D 2.2528 0.41386 0.50551 0.50551 D filled circle black lightblue
edge A B 4 0.45597 0.56204 0.59179 0.66681 0.77667 0.80943 0.93236 0.92954 solid black
edge A C 4 0.50421 0.41386 0.61135 0.41386 0.7401 0.41386 0.85955 0.41386 solid black
stop
'
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:39'
}
GraphvizPlainParserTest >> testEmptyInputYieldsNoNodes [
	| p |
	p := GraphvizPlainParser parse: '' pixelExtent: 100@100.
	self assert: p nodeRects isEmpty
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:39'
}
GraphvizPlainParserTest >> testIgnoresEdgeAndStopRecords [
	"Only 'node' records become rects; 'edge' and 'stop' are ignored."
	| p |
	p := GraphvizPlainParser parse: self samplePlain pixelExtent: 251@146.
	self deny: (p nodeRects includesKey: 'edge').
	self deny: (p nodeRects includesKey: 'stop').
	self assert: 4 equals: p nodeRects size
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParserTest >> testNodeRectMappingExact [
	"2x1 inch graph onto 200x100 px = 100 dpi. Node centered at (1,0.5) in,
	size 1x1 in. Center px = (100, 100 - 50) = 100@50. Y axis is flipped."
	| plain p rect |
	plain := 'graph 1 2 1
node X 1 0.5 1 1 X filled circle black white
stop
'.
	p := GraphvizPlainParser parse: plain pixelExtent: 200@100.
	rect := p nodeRects at: 'X'.
	self assert: (50@0 corner: 150@100) equals: rect.
	self assert: 100@50 equals: rect center
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParserTest >> testParsesAllNodes [
	| p |
	p := GraphvizPlainParser parse: self samplePlain pixelExtent: 251@146.
	self assert: 4 equals: p nodeRects size.
	self assert: (p nodeRects includesKey: 'A').
	self assert: (p nodeRects includesKey: 'B').
	self assert: (p nodeRects includesKey: 'C').
	self assert: (p nodeRects includesKey: 'D')
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParserTest >> testParsesGraphScaleAndSize [
	| p |
	p := GraphvizPlainParser parse: self samplePlain pixelExtent: 251@146.
	self assert: 1 equals: p scale.
	self assert: 2.5055 equals: p graphSize x.
	self assert: 1.4139 equals: p graphSize y
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParserTest >> testYAxisIsFlipped [
	"A node high in Graphviz coords (large Y, bottom-left origin) must map to a
	small pixel Y (top), and a low node to a large pixel Y (bottom)."
	| plain p high low |
	plain := 'graph 1 1 2
node High 0.5 1.5 0.2 0.2 High filled circle black white
node Low 0.5 0.5 0.2 0.2 Low filled circle black white
stop
'.
	p := GraphvizPlainParser parse: plain pixelExtent: 100@200.
	high := (p nodeRects at: 'High') center.
	low := (p nodeRects at: 'Low') center.
	self assert: high y < low y.
	self assert: 50 equals: high y.
	self assert: 150 equals: low y
]
