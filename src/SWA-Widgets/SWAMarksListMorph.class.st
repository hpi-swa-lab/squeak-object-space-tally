"
A plain multi-select list used in the SWAPane Marks panel. It carries NO event overrides -- it exists only as a MARKER type so the global SWAMarksClickFilter can recognise 'a click over a marks list' and rewrite the VM's emulated Ctrl+click (yellow button) back into a normal Ctrl+Red left-click that reaches selection. See SWAMarksClickFilter.
"
Class {
	#name : #SWAMarksListMorph,
	#superclass : #AlternatePluggableListMorphOfMany,
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}
