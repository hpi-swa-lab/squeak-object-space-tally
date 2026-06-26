"
A wrap-and-replace invocation counter for a single CompiledMethod, in the style
of Dan Ingalls' Lively Kernel profiler (tallyFunc).

Installed into a method dictionary in place of the real method; on each call it
increments #count (and accrues #ticks, elapsed ms), then forwards to the original
via #doesNotUnderstand:. When #count reaches #evictAt it UNINSTALLS itself so a
very hot method stops paying the wrapper overhead -- the count is frozen at the
eviction point and the method runs at full speed again. This keeps the whole-image
tally from freezing the system the way an unbounded wrap would.

Use SWACoverage as the front end; it installs/uninstalls a batch of these and
collects them into a Class>>selector -> count map for the Code Map's #coverage
color mode.

Instance Variables
	theClass        <Behavior>        the method's class (instance- or meta-side)
	selector        <Symbol>
	originalMethod  <CompiledMethod>  restored on uninstall
	count           <Integer>         invocations seen (frozen once evicted)
	ticks           <Integer>         accrued elapsed milliseconds
	evictAt         <Integer|nil>     uninstall after this many calls; nil = never
	evicted         <Boolean>         true once self-uninstalled
"
Class {
	#name : #SWATallyWrapper,
	#superclass : #SWAMethodWrapper,
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:25'
}
SWATallyWrapper >> onClass: aClass selector: aSelector evictAt: anIntegerOrNil [
	"A tally is just a base wrapper that opts into self-eviction: base setup (which
	includes count/evict state) plus the eviction threshold. The counting and
	eviction now live entirely in SWAMethodWrapper>>run:with:in:; this class adds NO
	per-call behaviour (the default no-op #captureIn: is exactly right)."
	self onClass: aClass selector: aSelector.
	evictAt := anIntegerOrNil
]
