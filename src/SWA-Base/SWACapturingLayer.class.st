"
Context-oriented reentrancy guard for the SWAMethodWrapper instrumentation family, emulated with a process-specific dynamic variable.

CONCEPT (COP): capturing is a LAYER that is ACTIVE by default. Every wrapped method's #run:with:in: consults the layer: if active it captures/counts/evicts, otherwise it just forwards. The instrumentation's OWN machinery (install/loop/log/uninstall, and each capture hook body) runs inside #withoutCapturing: -- i.e. the classic COP `withoutLayers(Capturing)` -- so any wrapped method it touches falls straight through instead of recursing.

WHY DYNAMIC (process-specific) instead of a global class var: wrapping the WHOLE live Morphic UI means several processes (World redraw, stepping morphs, XR world) run wrapped methods CONCURRENTLY. A single global boolean lets one process's guard suppress another's capture, and one process's ensure:-restore clobbers a value another process changed -- a shared-mutable-state race that showed up as Message>(nil)/ByteSymbol DNU crashes. A DynamicVariable binds the layer state per-process for the dynamic extent of the block (value:during: saves/restores via ensure:), so each process has its own correctly-nested view.

The stored value is a SUPPRESSION DEPTH (Integer). 0 or absent = layer ACTIVE (capture). > 0 = SUPPRESSED (inside our own machinery). Depth counting makes nested #withoutCapturing: correct.
"
Class {
	#name : #SWACapturingLayer,
	#superclass : #DynamicVariable,
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #layer,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:47'
}
SWACapturingLayer class >> isActive [
	"True if the capturing layer is currently ACTIVE in this process (no suppression
	in effect) -- i.e. a wrapper reaching here should capture/count/evict. This is the
	guard #run:with:in: consults."
	^ self suppressionDepth = 0
]

{
	#category : #layer,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:47'
}
SWACapturingLayer class >> reset [
	"Force the capturing layer back to ACTIVE in this process by removing any
	suppression binding. Call before/after a run so a crash or stray suppression can't
	leave wrappers permanently passing through in this process."
	Processor activeProcess environmentRemoveKey: self ifAbsent: []
]

{
	#category : #layer,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:47'
}
SWACapturingLayer class >> suppressionDepth [
	"Current capturing-suppression depth for THIS process (0 / absent = layer active).
	Read directly from the active process environment -- no #value default dispatch --
	so the hot path stays as cheap as possible."
	^ Processor activeProcess environmentAt: self ifAbsent: [0]
]

{
	#category : #layer,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:47'
}
SWACapturingLayer class >> whileCapturing: aBlock [
	"COP `withLayers(Capturing)` / the MEASURING WINDOW: run aBlock with the
	capturing layer forced ACTIVE (suppression depth 0) for its dynamic extent in
	THIS process, restoring the previous depth afterwards. The runner opens this ONLY
	around the actual code under test (e.g. #testCase run) so the wrapped methods that
	code exercises -- AT ANY DEPTH -- capture, while the surrounding machinery stays
	suppressed via #withoutCapturing:."
	^ self value: 0 during: aBlock
]

{
	#category : #layer,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:47'
}
SWACapturingLayer class >> withoutCapturing: aBlock [
	"COP `withoutLayers(Capturing)`: run aBlock with the capturing layer DEACTIVATED
	for its dynamic extent in THIS process, restoring the previous depth afterwards.
	Use around ALL instrumentation-framework code -- capture hooks, the runner loop,
	the logger, install/uninstall -- so wrapped methods it touches fall straight
	through their wrappers instead of recursing. Re-entrant safe: depth counts, so
	nested #withoutCapturing: nest correctly and each restores its own level."
	^ self value: self suppressionDepth + 1 during: aBlock
]
