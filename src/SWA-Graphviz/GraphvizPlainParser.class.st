"
Parses the output of Graphviz 'dot -Tplain' into geometry usable for hit-testing.

Graphviz '-Tplain' format (one record per line, space-separated):
    graph SCALE WIDTH HEIGHT
    node NAME X Y WIDTH HEIGHT LABEL STYLE SHAPE COLOR FILLCOLOR
    edge TAIL HEAD N X1 Y1 ... XN YN ...
    stop

Coordinates are in inches with a bottom-left origin. This parser maps node
boxes into top-left-origin pixel coordinates given a target pixel extent
(typically the rendered PNG's width @ height), flipping the Y axis.

Usage:
    parser := GraphvizPlainParser new pixelExtent: 251@146.
    parser parse: plainText.
    parser nodeRects.   """"=> Dictionary name -> Rectangle (pixels)""""

Instance variables:
    scale       - the scale factor from the 'graph' record
    graphSize   - graph WIDTH @ HEIGHT in inches (Point)
    nodeRects   - Dictionary of nodeName (String) -> Rectangle (pixel coords)
    pixelExtent - target pixel size (Point) the inch coords are mapped onto
"
Class {
	#name : #GraphvizPlainParser,
	#superclass : #Object,
	#instVars : [
		'scale',
		'graphSize',
		'nodeRects',
		'pixelExtent'
	],
	#category : #'SWA-Graphviz',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParser class >> parse: plainText pixelExtent: aPoint [
	"Convenience: parse plainText mapping onto aPoint pixel extent. Answer the parser."
	^ self new pixelExtent: aPoint; parse: plainText; yourself
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:37'
}
GraphvizPlainParser >> graphSize [
	"Graph size in inches (width @ height) from the 'graph' record."
	^ graphSize
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:37'
}
GraphvizPlainParser >> nodeRects [
	"Dictionary mapping node name (String) -> Rectangle in pixel coordinates."
	^ nodeRects
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParser >> parse: plainText [
	"Parse 'dot -Tplain' output. Populates scale, graphSize and nodeRects.
	Node rectangles are mapped to pixelExtent with a flipped (top-left origin) Y axis.
	Answer self."
	nodeRects := Dictionary new.
	plainText lines do: [:line |
		| tokens kind |
		tokens := line findTokens: ' '.
		tokens isEmpty ifFalse: [
			kind := tokens first.
			kind = 'graph' ifTrue: [self parseGraphRecord: tokens].
			kind = 'node' ifTrue: [self parseNodeRecord: tokens]]].
	^ self
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParser >> parseGraphRecord: tokens [
	"tokens = #('graph' scale width height)"
	scale := (tokens at: 2) asNumber.
	graphSize := (tokens at: 3) asNumber @ (tokens at: 4) asNumber
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizPlainParser >> parseNodeRecord: tokens [
	"tokens = #('node' name x y width height label ...).
	Map inch coords (bottom-left origin) to pixel coords (top-left origin)."
	| name cx cy w h dpiX dpiY px py pw ph |
	name := tokens at: 2.
	cx := (tokens at: 3) asNumber.
	cy := (tokens at: 4) asNumber.
	w := (tokens at: 5) asNumber.
	h := (tokens at: 6) asNumber.
	dpiX := pixelExtent x / graphSize x.
	dpiY := pixelExtent y / graphSize y.
	px := cx * dpiX.
	py := pixelExtent y - (cy * dpiY).
	pw := w * dpiX.
	ph := h * dpiY.
	nodeRects at: name put:
		((px - (pw / 2)) @ (py - (ph / 2)) corner:
		 (px + (pw / 2)) @ (py + (ph / 2)))
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:37'
}
GraphvizPlainParser >> pixelExtent [
	^ pixelExtent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:37'
}
GraphvizPlainParser >> pixelExtent: aPoint [
	"Set the target pixel extent (width @ height) that inch coordinates map onto."
	pixelExtent := aPoint
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:37'
}
GraphvizPlainParser >> scale [
	"The scale factor reported by the 'graph' record."
	^ scale
]
