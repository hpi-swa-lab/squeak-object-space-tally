"
A Morph that renders a Graphviz DOT graph to a PNG (via the external 'dot' command) and displays it as an image. It also parses Graphviz '-Tplain' output to recover node bounding boxes, so mouse clicks can be hit-tested against individual nodes.

Usage:
    (GraphvizMorph fromDot: 'digraph G { A -> B; B -> C; }') openInWorld

Set a per-node click handler:
    morph onNodeClick: [:nodeName | Transcript showln: 'clicked ', nodeName].

Instance variables:
    dotSource  - the DOT graph string
    nodeRects  - Dictionary mapping node name (String) -> Rectangle (in morph-local pixels)
    graphScale - scale factor reported by 'dot -Tplain'
    graphSize  - graph size in inches (Point) from 'dot -Tplain'
    nodeAction - a one-arg block evaluated with the clicked node name
"
Class {
	#name : #GraphvizMorph,
	#superclass : #ImageMorph,
	#instVars : [
		'dotSource',
		'nodeRects',
		'graphScale',
		'graphSize',
		'nodeAction',
		'panHandler',
		'engine',
		'fieldRects',
		'fieldAction',
		'selectionRect',
		'selectionColor',
		'menuAction',
		'markers',
		'markerAction',
		'relaxesEdgeLabels'
	],
	#category : #'SWA-Graphviz',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:47'
}
GraphvizMorph class >> edgeLabelRelaxationScript [
	"A gvpr pass that moves headlabel positions out of whatever they overlap:
	node boxes, cluster labels, arrow tips, each other, and the edge splines
	themselves. Writes only head_lp, so node and record-row geometry is untouched
	and the diagram''s click maps stay valid.
	ARGV[0] iterations (default 300), ARGV[1] spring constant (default 0.02)."
	^ '// fixheadlabels.gvpr -- force-directed de-overlap of edge head/tail labels.
//
// dot positions headlabel/taillabel purely trigonometrically from
// labeldistance + labelangle + the direction of the last spline segment, with
// zero collision detection.  So labels land inside the head node''s box, and
// sibling edges arriving at the same node stack their labels on top of each
// other.
//
// This pass leaves dot''s layout alone and just relaxes the label positions:
// each label is a particle held by a weak spring to where dot put it, and
// pushed out of any box it overlaps (other labels, and all node boxes).
//
// Usage:
//   dot -Tdot g.dot | gvpr -c -f fixheadlabels.gvpr | neato -n2 -Tpng -o g.png
//
// ARGV[0] iterations (default 300)   ARGV[1] spring constant (default 0.02)

BEGIN {
    double CHARW = 0.55;     // avg glyph width / font size
    double LINEH = 1.25;     // line height / font size
    double PAD   = 3.0;      // extra clearance around every box
    // keep-out zone around each arrow tip; deliberately wide and flat so the
    // least-penetration rule slides a label *along* its edge, not off it
    double ARROWW = 22.0;
    double ARROWH = 6.0;
    // edge splines are obstacles too, else a label sits ON the line it belongs
    // to and reads as struck through.  A segment always pushes PERPENDICULAR,
    // so the label steps off the line instead of sliding along it.
    double SEGT  = 2.0;      // half-thickness of an edge line
    double SEGMIN = 5.0;     // ignore segments shorter than this
    double DAMP  = 0.35;     // how much of the computed force to apply per step

    int    ITER = 300;
    double KSPRING = 0.02;

    // label particles
    int    N = 0;
    edge_t EA[int];
    double LX[int], LY[int], LW[int], LH[int], AX[int], AY[int];

    // fixed obstacles.  OA = which axis a label may escape along:
    //   0 = whichever penetration is smaller, 1 = x only, 2 = y only
    int    M = 0;
    double OX[int], OY[int], OW[int], OH[int];
    int    OA[int];

    // drawing bounds, used as walls
    int    HASBB = 0;
    double BBX0, BBY0, BBX1, BBY1;
}

BEG_G {
    if (ARGC > 0) ITER    = (int)ARGV[0];
    if (ARGC > 1) KSPRING = (double)ARGV[1];
    if ($G.bb != "")
        HASBB = (sscanf($G.bb, "%lf,%lf,%lf,%lf", &BBX0, &BBY0, &BBX1, &BBY1) == 4);
}

N {
    if ($.pos != "") {
        double nx, ny;
        if (sscanf($.pos, "%lf,%lf", &nx, &ny) == 2) {
            double nw = 54.0, nh = 36.0;
            if ($.width  != "") nw = (double)$.width  * 72.0;
            if ($.height != "") nh = (double)$.height * 72.0;
            OX[M] = nx; OY[M] = ny; OW[M] = nw; OH[M] = nh; OA[M] = 0; M++;
        }
    }
}

E {
    string lab = $.headlabel;
    if (lab != "" && $.head_lp != "") {
        double lx, ly;
        if (sscanf($.head_lp, "%lf,%lf", &lx, &ly) == 2) {
            double fs = 14.0;
            if ($.labelfontsize != "")  fs = (double)$.labelfontsize;
            else if ($.fontsize != "")  fs = (double)$.fontsize;

            EA[N] = $;
            LX[N] = lx;  LY[N] = ly;
            AX[N] = lx;  AY[N] = ly;              // anchor: dot''s choice
            LW[N] = length(lab) * fs * CHARW;
            LH[N] = fs * LINEH;
            N++;
        }
    }
    // the arrowhead is an obstacle too -- a label must not sit on the tip.
    // escape axis = the axis the edge arrives along, so the label slides
    // *along* its own edge instead of being flung off it.
    if ($.pos != "") {
        double tx, ty, lastx, lasty;
        if (sscanf($.pos, "e,%lf,%lf", &tx, &ty) == 2) {
            int    sp = rindex($.pos, " ");
            lastx = tx; lasty = ty;
            if (sp >= 0) sscanf(substr($.pos, sp + 1), "%lf,%lf", &lastx, &lasty);
            double adx = tx - lastx;  if (adx < 0) adx = -adx;
            double ady = ty - lasty;  if (ady < 0) ady = -ady;
            OX[M] = tx; OY[M] = ty; OW[M] = ARROWW; OH[M] = ARROWH;
            OA[M] = (adx >= ady) ? 1 : 2;
            M++;
        }

        // the spline itself.  Consecutive control points are collinear in runs
        // for splines=ortho, so merge each run into one box: fewer obstacles,
        // and a long straight leg pushes as one thing rather than in pieces.
        string parts[int];
        int np = tokens($.pos, parts);
        double px[int], py[int];
        int k, npts = 0;
        for (k = 0; k < np; k++) {
            double qx, qy;
            string t = parts[k];
            // the "e,"/"s," tokens are the arrow endpoints and come FIRST, out
            // of path order; they are already covered by the arrowhead box
            if (index(t, "e,") == 0 || index(t, "s,") == 0) continue;
            if (sscanf(t, "%lf,%lf", &qx, &qy) == 2) {
                if (npts == 0 || px[npts-1] != qx || py[npts-1] != qy) {
                    px[npts] = qx; py[npts] = qy; npts++;
                }
            }
        }
        k = 0;
        while (k + 1 < npts) {
            int horiz = ((px[k+1] - px[k] < 0 ? px[k] - px[k+1] : px[k+1] - px[k])
                      >= (py[k+1] - py[k] < 0 ? py[k] - py[k+1] : py[k+1] - py[k]));
            int e2 = k + 1;
            while (e2 + 1 < npts) {
                int h2 = ((px[e2+1] - px[e2] < 0 ? px[e2] - px[e2+1] : px[e2+1] - px[e2])
                       >= (py[e2+1] - py[e2] < 0 ? py[e2] - py[e2+1] : py[e2+1] - py[e2]));
                if (h2 != horiz) break;
                e2++;
            }
            double sw = px[e2] - px[k];  if (sw < 0) sw = -sw;
            double sh = py[e2] - py[k];  if (sh < 0) sh = -sh;
            if ((horiz ? sw : sh) >= SEGMIN) {
                OX[M] = (px[k] + px[e2]) / 2.0;
                OY[M] = (py[k] + py[e2]) / 2.0;
                if (horiz) { OW[M] = sw; OH[M] = SEGT; OA[M] = 2; }
                else       { OW[M] = SEGT; OH[M] = sh; OA[M] = 1; }
                M++;
            }
            k = e2;
        }
    }
}

END_G {
    int it, i, j;
    double fx[int], fy[int];

    // --- cluster *labels* are obstacles as well (the cluster box itself
    //     is not: labels are allowed to live inside a cluster) ----------
    graph_t sg;
    for (sg = fstsubg($G); sg; sg = nxtsubg(sg)) {
        if (sg.label != "" && sg.lp != "") {
            double cx, cy;
            if (sscanf(sg.lp, "%lf,%lf", &cx, &cy) == 2) {
                double cfs = 14.0;
                if (sg.fontsize != "") cfs = (double)sg.fontsize;
                OX[M] = cx; OY[M] = cy;
                OW[M] = length(sg.label) * cfs * CHARW;
                OH[M] = cfs * LINEH;
                OA[M] = 0;
                M++;
            }
        }
    }

    // --- broad phase: a label is held near its anchor by the spring, so an
    //     obstacle further than REACH from it can never be touched.  Adding
    //     edge splines multiplied the obstacle count; without this cull the
    //     inner loop below grows with the whole drawing instead of the
    //     neighbourhood.  NB is flat: neighbours of label i are NB[i*M + c].
    int NB[int], NC[int];
    double REACH = 240.0;
    for (i = 0; i < N; i++) {
        NC[i] = 0;
        for (j = 0; j < M; j++) {
            double gx = AX[i] - OX[j];  if (gx < 0) gx = -gx;
            double gy = AY[i] - OY[j];  if (gy < 0) gy = -gy;
            if (gx <= REACH + (LW[i] + OW[j]) / 2.0
             && gy <= REACH + (LH[i] + OH[j]) / 2.0) {
                NB[i * M + NC[i]] = j;
                NC[i] = NC[i] + 1;
            }
        }
    }

    for (it = 0; it < ITER; it++) {

        for (i = 0; i < N; i++) { fx[i] = 0.0; fy[i] = 0.0; }

        // --- weak spring back to where dot wanted the label -----------
        for (i = 0; i < N; i++) {
            fx[i] = fx[i] + KSPRING * (AX[i] - LX[i]);
            fy[i] = fy[i] + KSPRING * (AY[i] - LY[i]);
        }

        // --- label <-> label repulsion (box overlap only) -------------
        for (i = 0; i < N; i++) {
            for (j = i + 1; j < N; j++) {
                double dx = LX[i] - LX[j];
                double dy = LY[i] - LY[j];
                double ox = (LW[i] + LW[j]) / 2.0 + PAD - (dx < 0 ? -dx : dx);
                double oy = (LH[i] + LH[j]) / 2.0 + PAD - (dy < 0 ? -dy : dy);
                if (ox > 0.0 && oy > 0.0) {
                    // separate along the axis of least penetration
                    double sep;
                    if (oy <= ox) {
                        sep = (dy >= 0.0 ? 1.0 : -1.0) * oy / 2.0;
                        fy[i] = fy[i] + sep;  fy[j] = fy[j] - sep;
                    } else {
                        sep = (dx >= 0.0 ? 1.0 : -1.0) * ox / 2.0;
                        fx[i] = fx[i] + sep;  fx[j] = fx[j] - sep;
                    }
                }
            }
        }

        // --- label <-> obstacle repulsion (obstacles are immovable) ---
        for (i = 0; i < N; i++) {
            int c;
            for (c = 0; c < NC[i]; c++) {
                j = NB[i * M + c];
                double ndx = LX[i] - OX[j];
                double ndy = LY[i] - OY[j];
                double nox = (LW[i] + OW[j]) / 2.0 + PAD - (ndx < 0 ? -ndx : ndx);
                double noy = (LH[i] + OH[j]) / 2.0 + PAD - (ndy < 0 ? -ndy : ndy);
                if (nox > 0.0 && noy > 0.0) {
                    int ax = OA[j];
                    if (ax == 0) ax = (noy <= nox) ? 2 : 1;
                    if (ax == 2) fy[i] = fy[i] + (ndy >= 0.0 ? noy : -noy);
                    else         fx[i] = fx[i] + (ndx >= 0.0 ? nox : -nox);
                }
            }
        }

        for (i = 0; i < N; i++) {
            LX[i] = LX[i] + DAMP * fx[i];
            LY[i] = LY[i] + DAMP * fy[i];
            // the renderer sizes the canvas from node positions and never from
            // edge labels, so a label pushed past the bb is simply cut off
            if (HASBB) {
                double hw = LW[i] / 2.0, hh = LH[i] / 2.0;
                if (LX[i] - hw < BBX0) LX[i] = BBX0 + hw;
                if (LX[i] + hw > BBX1) LX[i] = BBX1 - hw;
                if (LY[i] - hh < BBY0) LY[i] = BBY0 + hh;
                if (LY[i] + hh > BBY1) LY[i] = BBY1 - hh;
            }
        }
    }

    for (i = 0; i < N; i++)
        EA[i].head_lp = sprintf("%.2f,%.2f", LX[i], LY[i]);
}
'
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph class >> fromDot: aDotString [
	"Create a GraphvizMorph rendering the given DOT source string."
	^ self new setDot: aDotString
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> addCustomMenuItems: aCustomMenu hand: aHandMorph [
	"Add Graphviz-specific items to the halo / control menu."
	super addCustomMenuItems: aCustomMenu hand: aHandMorph.
	aCustomMenu addLine.
	aCustomMenu add: 'choose engine... (' , self engine , ')'
		target: self selector: #chooseEngine.
	aCustomMenu add: 'show DOT source' target: self selector: #showDotSource.
	aCustomMenu add: 'edit DOT source...' target: self selector: #editDotSource.
	aCustomMenu add: 'rerender' target: self selector: #render
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> availableEngines [
	"The Graphviz layout engines offered in the halo menu."
	^ #('dot' 'neato' 'fdp' 'sfdp' 'circo' 'twopi' 'osage' 'patchwork')
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> chooseEngine [
	"Let the user pick a layout engine, then re-render."
	| choice |
	choice := UIManager default
		chooseFrom: self availableEngines
		values: self availableEngines
		title: 'Layout engine (current: ' , self engine , ')'.
	choice ifNil: [^ self].
	self engine: choice.
	self render
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> dotSource [
	"The current DOT source string."
	^ dotSource
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:35'
}
GraphvizMorph >> drawMarkersOn: aCanvas [
	"Draw each marker as a ring: hollow when not set, filled with its colour when set."
	| origin |
	markers ifNil: [^ self].
	origin := self bounds origin.
	markers do: [:assoc |
		| rect filled markerColor |
		rect := (assoc value first) translateBy: origin.
		filled := assoc value second.
		markerColor := assoc value third.
		aCanvas
			fillOval: rect
			color: (filled ifTrue: [markerColor] ifFalse: [Color transparent])
			borderWidth: 1
			borderColor: (filled ifTrue: [markerColor muchDarker] ifFalse: [Color gray: 0.55])].
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:17'
}
GraphvizMorph >> drawOn: aCanvas [
	"Draw the layout image (super), then, if an element is selected, frame it with a
	blue selection border via the shared SWASelectionPainter (same feedback the
	treemap uses). The enclosing scroll/zoom pane transforms this canvas, so the
	frame tracks the graph as it pans and zooms."
	super drawOn: aCanvas.
	self drawMarkersOn: aCanvas.
	selectionRect ifNotNil: [:r |
		SWASelectionPainter
			selectionFrameOn: aCanvas
			rect: (r translateBy: self bounds origin)
			color: self selectionColor]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> editDotSource [
	"Open an editor on the DOT source; accepting (cmd-s) re-renders the graph."
	UIManager default
		edit: (self dotSource ifNil: [''])
		label: 'Edit DOT source - accept (cmd-s) to rerender'
		accept: [:newText | self setDot: newText asString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:21'
}
GraphvizMorph >> engine [
	"The Graphviz layout engine to use (e.g. 'dot', 'neato', 'fdp', 'sfdp', 'circo', 'twopi'). Defaults to 'dot'."
	^ engine ifNil: [engine := 'dot']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:21'
}
GraphvizMorph >> engine: aString [
	"Set the Graphviz layout engine (e.g. 'dot', 'neato', 'fdp', 'sfdp', 'circo', 'twopi')."
	engine := aString
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:43'
}
GraphvizMorph >> fieldAt: aWorldPoint [
	"Answer the record sub-field hit by aWorldPoint as an Association
	nodeName -> fieldIndex (0-based, top-to-bottom), or nil. fieldRects are in
	morph-local pixel coordinates, so subtract our origin. Fields are contiguous
	within a node, so first containment wins."
	| local |
	fieldRects isNil ifTrue: [^ nil].
	local := aWorldPoint - self bounds origin.
	fieldRects do: [:assoc |
		((assoc value second) containsPoint: local)
			ifTrue: [^ assoc key -> (assoc value first)]].
	^ nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph >> handlesMouseDown: evt [
	^ true
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:42'
}
GraphvizMorph >> layoutCommandFrom: dotFile to: pngFile and: jsonFile gvpr: gvprFile [
	"The shell command producing both outputs. Still ONE invocation when the edge-label
	pass is on: the layout runs as -Tdot, gvpr rewrites head_lp in the stream, and
	neato -n2 only renders the positions it is handed, so nothing is laid out twice."
	| eng |
	eng := self engine.
	self relaxesEdgeLabels ifFalse: [
		^ eng, ' -Tpng -o ', pngFile, ' -Tjson -o ', jsonFile, ' ', dotFile].
	^ eng, ' -Tdot ', dotFile,
		' | gvpr -c -f ', gvprFile,
		' | neato -n2 -Tpng -o ', pngFile, ' -Tjson -o ', jsonFile
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:17'
}
GraphvizMorph >> markerAt: aWorldPoint [
	"Answer the key of the marker badge hit by aWorldPoint, or nil."
	| local |
	markers isNil ifTrue: [^ nil].
	local := aWorldPoint - self bounds origin.
	markers do: [:assoc |
		((assoc value first) containsPoint: local) ifTrue: [^ assoc key]].
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:17'
}
GraphvizMorph >> markers: aCollectionOrNil [
	"Clickable circular badges drawn over the layout image, as a collection of
	Associations anyKey -> Array { rect. isFilled. aColor }. Rects are in the same
	morph-local pixel space as nodeRects / fieldRects, so the owner can position a
	badge off a record sub-field rect."
	markers := aCollectionOrNil.
	self changed.
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:20'
}
GraphvizMorph >> mouseDown: evt [
	"Right-click (yellow button) with a menuAction set -> fire the context menu.
	Otherwise hit-test the click: marker badges first, since they sit inside the field
	rect that would otherwise swallow them; then, if a fieldAction is set and the click lands in a
	record sub-field, fire it with nodeName -> fieldIndex; else if a node is hit and
	a nodeAction is set, fire that with the node name; else pan (if a panHandler is
	set) or fall back to default behavior (e.g. dragging via halo)."
	| field node |
	(evt yellowButtonPressed and: [menuAction notNil])
		ifTrue: [^ menuAction value: evt].
	markerAction ifNotNil: [
		(self markerAt: evt cursorPoint) ifNotNil: [:key | ^ markerAction value: key]].
	fieldAction ifNotNil: [
		field := self fieldAt: evt cursorPoint.
		field ifNotNil: [^ fieldAction value: field]].
	node := self nodeAt: evt cursorPoint.
	(node notNil and: [nodeAction notNil])
		ifTrue: [^ nodeAction value: node].
	panHandler ifNotNil: [^ panHandler panBackgroundDown: evt from: self].
	super mouseDown: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:23'
}
GraphvizMorph >> mouseMove: evt [
	"Forward drags to the panHandler (for background panning)."
	panHandler ifNotNil: [^ panHandler panBackgroundMove: evt from: self].
	super mouseMove: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:23'
}
GraphvizMorph >> mouseUp: evt [
	"Forward drag end to the panHandler (for background panning)."
	panHandler ifNotNil: [^ panHandler panBackgroundUp: evt from: self].
	super mouseUp: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph >> nodeAt: aWorldPoint [
	"Answer the name of the node whose rectangle contains aWorldPoint, or nil.
	nodeRects are in morph-local pixel coordinates, so subtract our origin."
	| local |
	nodeRects isNil ifTrue: [^ nil].
	local := aWorldPoint - self bounds origin.
	nodeRects keysAndValuesDo: [:name :rect |
		(rect containsPoint: local) ifTrue: [^ name]].
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:18'
}
GraphvizMorph >> nodeRectsAvailable [
	"Answer whether node rectangles have been parsed (a graph is loaded)."
	^ nodeRects notNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:43'
}
GraphvizMorph >> onFieldClick: aBlock [
	"Set a one-argument block evaluated with the clicked record sub-field as an
	Association nodeName -> fieldIndex (0-based). Takes precedence over the plain
	node action when the click lands inside a record field."
	fieldAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:17'
}
GraphvizMorph >> onMarkerClick: aBlock [
	"Set a one-argument block evaluated with the key of the clicked marker badge.
	Takes precedence over the field and node actions, since a badge sits inside the
	field rect that would otherwise swallow the click."
	markerAction := aBlock.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:42'
}
GraphvizMorph >> onMenuRequest: aBlock [
	"Set a one-argument block evaluated with the triggering event when the user
	right-clicks (yellow button) the graph background, so an owner can pop up a
	context menu."
	menuAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/18/2026 10:54'
}
GraphvizMorph >> onNodeClick: aBlock [
	"Set a one-argument block to be evaluated with the clicked node's name (a String)."
	nodeAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:22'
}
GraphvizMorph >> panHandler: anObject [
	"Optional object notified of background (non-node) mouse drags so an
	enclosing pane can implement panning. It must understand
	#panBackgroundDown:from:, #panBackgroundMove:from:, #panBackgroundUp:from:.
	When nil, background clicks fall back to default Morph behavior."
	panHandler := anObject
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizMorph >> parsePlain: plainText withForm: form [
	"Delegate to GraphvizPlainParser to turn 'dot -Tplain' output into node
	rectangles in pixel coordinates matching the rendered form."
	| parser |
	parser := GraphvizPlainParser parse: plainText pixelExtent: form extent.
	graphScale := parser scale.
	graphSize := parser graphSize.
	nodeRects := parser nodeRects
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> rectForNode: aDotId [
	"The whole-node pixel rectangle for the node with the given dot id, or nil."
	nodeRects ifNil: [^ nil].
	^ nodeRects at: aDotId ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> rectForNode: aDotId field: aFieldIndex [
	"The pixel rectangle of record sub-field aFieldIndex (0-based) of the node with
	the given dot id, or nil if there is no such field."
	fieldRects ifNil: [^ nil].
	fieldRects do: [:assoc |
		(assoc key = aDotId and: [assoc value first = aFieldIndex])
			ifTrue: [^ assoc value second]].
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:42'
}
GraphvizMorph >> relaxesEdgeLabels [
	"Whether to run the gvpr de-overlap pass over edge head labels. Defaults to
	whether the graph has any, since the pass costs a second process and can only
	move what it finds."
	^ relaxesEdgeLabels
		ifNil: [dotSource notNil and: [dotSource includesSubstring: 'headlabel']]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:42'
}
GraphvizMorph >> relaxesEdgeLabels: aBooleanOrNil [
	"Force the edge-label de-overlap pass on or off; nil restores the default."
	relaxesEdgeLabels := aBooleanOrNil
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:42'
}
GraphvizMorph >> render [
	"Run the external layout engine (self engine, e.g. 'dot') to produce a PNG plus
	a -Tjson layout. Load the PNG as our image and parse the JSON into node
	rectangles AND per-field (record compartment) rectangles via GraphvizJsonParser.
	JSON is used instead of -Tplain: it is properly structured (no whitespace-token
	fragility) and carries record sub-field geometry, enabling sub-node clicks.
	The .dot file is written with LF line endings since the engine rejects bare CRs.

	Both outputs come from ONE invocation. The engine lays the graph out once either
	way, and OSProcess blocks the whole image while it runs -- forking does not help --
	so a second call would double a stall that is already seconds long on a large graph.
	See #layoutCommandFrom:to:and:gvpr: for the edge-label variant, which stays one
	invocation by piping -Tdot through gvpr into neato -n2."
	| dir dotFile pngFile jsonFile gvprFile form jsonText eng parser |
	eng := self engine.
	dir := FileDirectory default fullNameFor: 'graphvizmorph'.
	dotFile := dir, '.dot'.
	pngFile := dir, '.png'.
	jsonFile := dir, '.json'.
	gvprFile := dir, '.gvpr'.
	(FileStream forceNewFileNamed: dotFile) nextPutAll: dotSource withUnixLineEndings; close.
	self relaxesEdgeLabels ifTrue: [
		(FileStream forceNewFileNamed: gvprFile)
			nextPutAll: self class edgeLabelRelaxationScript withUnixLineEndings; close].
	(OSProcess waitForCommand: (self
		layoutCommandFrom: dotFile to: pngFile and: jsonFile gvpr: gvprFile)) exitStatus = 0
			ifFalse: [^ self error: eng, ' failed'].
	"A pipeline reports only its LAST stage, so a failing dot or gvpr leaves
	neato exiting 0 on empty input."
	(FileDirectory default fileExists: pngFile)
		ifFalse: [^ self error: eng, ' produced no image'].
	form := PNGReadWriter formFromFileNamed: pngFile.
	self image: form.
	jsonText := (FileStream fileNamed: jsonFile) contentsOfEntireFile.
	parser := GraphvizJsonParser parse: jsonText pixelExtent: form extent.
	graphScale := parser scale.
	graphSize := parser graphSize.
	nodeRects := parser nodeRects.
	fieldRects := parser fieldRects
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> selectionColor [
	^ selectionColor ifNil: [Color blue]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> selectionColor: aColor [
	"The color of the selection frame (default blue)."
	selectionColor := aColor.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> selectionRect: aRectangleOrNil [
	"Set the morph-local pixel rectangle to frame as the persistent selection
	(or nil to clear), and redraw. Coordinates are in the same local pixel space
	as nodeRects / fieldRects."
	selectionRect = aRectangleOrNil ifTrue: [^ self].
	selectionRect := aRectangleOrNil.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 10:50'
}
GraphvizMorph >> setDot: aDotString [
	"Set the DOT source and (re)render the graph."
	dotSource := aDotString.
	self render.
	^ self
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> showDotSource [
	"Open a read-only-ish editor window displaying the current DOT source."
	UIManager default
		edit: (self dotSource ifNil: [''])
		label: 'DOT source (', self engine, ')'
]
