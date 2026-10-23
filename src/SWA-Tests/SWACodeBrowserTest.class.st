Class {
	#name : #SWACodeBrowserTest,
	#superclass : #TestCase,
	#instVars : [
		'browser'
	],
	#category : #'SWA-Tests'
}

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> setUp [
	browser := SWACodeBrowser new.
	browser setRoot: (SWACodeRootNode new addPackages: 'SWA-Widgets'; yourself).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:11'
}
SWACodeBrowserTest >> testABroaderPackageStaysSelected [
	browser setRoot: (SWACodeRootNode new addPackages: 'SWA'; yourself).
	browser packageIndex: (browser packageList findFirst: [:each | each asString = 'SWA']).
	browser classIndex: (browser classList findFirst: [:each | each asString = 'SWASplitter']).
	self assert: 'SWA' equals: (browser packageList at: browser packageIndex) asString.
	browser methodIndex: 1.
	self assert: 'SWA' equals: (browser packageList at: browser packageIndex) asString.
	browser packageIndex: 0.
	browser selectNodeForKey: 'SWASplitter'.
	self deny: 'SWA' = (browser packageList at: browser packageIndex) asString.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testAClassShowsItsDefinition [
	browser selectNodeForKey: 'SWASplitter'.
	self assert: (browser selectedSourceString asString includesSubstring: 'subclass: #SWASplitter').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowserTest >> testAllCategoriesListsEveryMethodAndStaysSelected [
	browser selectNodeForKey: 'SWASplitter'.
	self assert: '-- all --' equals: (browser categoryList first) asString.
	self assert: browser methodList isEmpty.
	browser categoryIndex: 1.
	self assert: 1 equals: browser categoryIndex.
	self assert: (browser methodList anySatisfy: [:each | each asString = 'resizeAction:']).
	browser methodIndex: (browser methodList findFirst: [:each | each asString = 'resizeAction:']).
	self assert: 1 equals: browser categoryIndex.
	self assert: 'SWASplitter>>resizeAction:' equals: browser selectedNode crossRefKey.
	browser categoryIndex: 2.
	self deny: 1 = browser categoryIndex.
	browser selectNodeForKey: 'SWAMarksListMorph'.
	self assert: 0 equals: browser categoryIndex.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testClassSideMethodSwitchesToTheClassSide [
	browser selectNodeForKey: 'SWASplitter class>>horizontal'.
	self assert: #class equals: browser side.
	self assert: (browser methodList anySatisfy: [:each | each asString = 'horizontal']).
	browser side: #instance.
	self deny: (browser methodList anySatisfy: [:each | each asString = 'horizontal']).
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testClickingTheSelectionAgainSelectsTheColumnLeftOfIt [
	browser selectNodeForKey: 'SWASplitter>>resizeAction:'.
	browser methodIndex: 0.
	self assert: (browser selectedNode isKindOf: SWACodeCategoryNode).
	browser categoryIndex: 0.
	self assert: 'SWASplitter' equals: browser selectedNode name.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testQuestionMarkShowsTheClassComment [
	browser selectNodeForKey: 'SWAMarksListMorph'.
	browser side: #comment.
	self assert: (browser selectedNode isKindOf: SWACodeCommentNode).
	self assert: browser categoryList isEmpty.
	self assert: (browser selectedSourceString asString includesSubstring: 'Marks panel').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testSearchFiltersTheLists [
	browser searchFor: 'Splitter'.
	self assert: (browser classList collect: [:each | each asString]) asArray equals: #('SWASplitter').
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testSelectingAMethodPointsEveryColumnAtIt [
	browser selectNodeForKey: 'SWASplitter>>resizeAction:'.
	self assert: 'SWA-Widgets' equals: (browser packageList at: browser packageIndex) asString.
	self assert: 'SWASplitter' equals: (browser classList at: browser classIndex) asString.
	self assert: browser categoryIndex > 0.
	self assert: 'resizeAction:' equals: (browser methodList at: browser methodIndex) asString.
]

{
	#category : #tests,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowserTest >> testSwitchingViewsKeepsTheSelection [
	| map pane |
	map := SWACodeTreemapMorph on: browser rootNode.
	map extent: 600 @ 400.
	pane := SWAPane on: map.
	map selectNodeForKey: 'SWASplitter>>resizeAction:'.
	pane switchToCodeView: #browser.
	self assert: (pane view isKindOf: SWACodeBrowser).
	self assert: 'SWASplitter>>resizeAction:' equals: pane view selectedNode crossRefKey.
	pane view selectNodeForKey: 'SWASplitter class>>horizontal'.
	pane switchToCodeView: #codeMap.
	self assert: pane view == map.
	self assert: 'SWASplitter class>>horizontal' equals: map selectedNode crossRefKey.
]
