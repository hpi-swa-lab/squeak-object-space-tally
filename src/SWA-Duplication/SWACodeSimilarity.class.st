"
Jaccard-similarity code-duplication detector for SWACodeMap.

Represents each method source as a SET of k-gram shingles (overlapping
sequences of k tokens) and scores a pair of methods by the Jaccard
coefficient J(A,B) = |A intersect B| / |A union B|. Verbatim copies score
1.0; a copy with one line changed keeps almost all shingles and still scores
high, so it is flagged. Paraphrase / renaming defeats it (known weakness of
the set-based method).

Reference: plagiarismchecker.net 'Jaccard similarity set-based method for
plagiarism detection'.

Instance vars:
  k         - shingle size in tokens (default 4; smaller = more sensitive)
  threshold - minimum Jaccard score to report a pair as a duplicate (default 0.7)

Typical use:
  (SWACodeSimilarity new) duplicatesInPackage: 'SWA-CodeMap'.
  SWACodeSimilarity new score: methodNodeA with: methodNodeB.
"
Class {
	#name : #SWACodeSimilarity,
	#superclass : #Object,
	#instVars : [
		'k',
		'threshold'
	],
	#category : #'SWA-Duplication',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:17'
}
SWACodeSimilarity class >> new [
	^ super new initialize
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> duplicatePairsAmong: methodNodes [
	"Pairwise Jaccard scan over a collection of SWACodeMethodNodes. Shingle sets
	are precomputed once per method (O(n) shingling) then compared O(n^2). Returns
	an Array of associations  (scoreFloat -> { nodeA. nodeB })  for every pair
	whose score >= threshold, sorted by descending score. Trivially short methods
	(no shingles) are skipped."
	| nodes shingleSets pairs |
	nodes := methodNodes asArray.
	shingleSets := nodes collect: [:n | self shinglesFor: n sourceString].
	pairs := OrderedCollection new.
	1 to: nodes size - 1 do: [:i |
		| sa |
		sa := shingleSets at: i.
		sa isEmpty ifFalse: [
			i + 1 to: nodes size do: [:j |
				| score |
				score := (self jaccardBetween: sa and: (shingleSets at: j)) asFloat.
				score >= threshold ifTrue: [
					pairs add: score -> { nodes at: i. nodes at: j }]]]].
	^ pairs asArray sort: [:p1 :p2 | p1 key >= p2 key]
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> duplicatesInPackage: aPackageName [
	"Convenience entry point: find duplicate method pairs in a package, returned as
	associations (score -> {nodeA. nodeB}) sorted by descending score."
	^ self duplicatePairsAmong: (self methodNodesInPackage: aPackageName)
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:17'
}
SWACodeSimilarity >> initialize [
	k := 4.
	threshold := 0.7
]

{
	#category : #scoring,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> jaccardBetween: setA and: setB [
	"J(A,B) = |A intersect B| / |A union B|. Two empty sets are defined as
	identical (1.0)."
	| inter union |
	(setA isEmpty and: [setB isEmpty]) ifTrue: [^ 1.0].
	inter := (setA select: [:each | setB includes: each]) size.
	union := setA size + setB size - inter.
	union = 0 ifTrue: [^ 0.0].
	^ inter / union
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:17'
}
SWACodeSimilarity >> k [
	"Shingle size in tokens."
	^ k
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:17'
}
SWACodeSimilarity >> k: anInteger [
	k := anInteger
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> methodNodesInPackage: aPackageName [
	"All SWACodeMethodNode leaves under the given package, built via the
	SWACodeMap node model."
	| root leaves collect |
	root := SWACodePackageNode named: aPackageName.
	leaves := OrderedCollection new.
	collect := nil.
	collect := [:node |
		(node isKindOf: SWACodeMethodNode)
			ifTrue: [leaves add: node]
			ifFalse: [node children do: collect]].
	collect value: root.
	^ leaves
]

{
	#category : #scanning,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> reportForPackage: aPackageName [
	"Human-readable duplicate report string for a package."
	| pairs s |
	pairs := self duplicatesInPackage: aPackageName.
	s := WriteStream on: String new.
	s nextPutAll: 'Jaccard duplicate scan: '; nextPutAll: aPackageName; cr.
	s nextPutAll: '  k='; print: k; nextPutAll: '  threshold='; print: threshold; cr.
	s nextPutAll: '  '; print: pairs size; nextPutAll: ' pair(s) >= threshold'; cr; cr.
	pairs do: [:assoc |
		s nextPutAll: '  '; nextPutAll: (assoc value first crossRefKey);
			nextPutAll: '  ~  '; nextPutAll: (assoc value second crossRefKey); cr.
		s nextPutAll: '      score = ';
			print: (assoc key * 100) rounded; nextPutAll: '%'; cr].
	^ s contents
]

{
	#category : #scoring,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> score: methodNodeA with: methodNodeB [
	"Jaccard similarity of two SWACodeMethodNodes (uses their cached source)."
	^ self scoreSource: methodNodeA sourceString with: methodNodeB sourceString
]

{
	#category : #scoring,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> scoreSource: stringA with: stringB [
	"Jaccard similarity of two raw source strings, as a Float in [0,1]."
	^ (self jaccardBetween: (self shinglesFor: stringA)
		and: (self shinglesFor: stringB)) asFloat
]

{
	#category : #shingling,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> shinglesFor: aString [
	"The k-gram shingle SET for a source string: every overlapping run of k
	tokens, joined by a separator, collected into a Set (the article's set-based
	representation). If the method has fewer than k tokens we fall back to a
	single shingle of all its tokens so short methods still compare."
	| tokens shingles |
	tokens := self tokensFor: aString.
	shingles := Set new.
	tokens size < k
		ifTrue: [
			tokens isEmpty ifFalse: [shingles add: (tokens fold: [:a :b | a, ' ', b])].
			^ shingles].
	1 to: tokens size - k + 1 do: [:i |
		| gram |
		gram := (tokens copyFrom: i to: i + k - 1) fold: [:a :b | a, ' ', b].
		shingles add: gram].
	^ shingles
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:17'
}
SWACodeSimilarity >> threshold [
	^ threshold
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:17'
}
SWACodeSimilarity >> threshold: aFloat [
	threshold := aFloat
]

{
	#category : #shingling,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:18'
}
SWACodeSimilarity >> tokensFor: aString [
	"Split source into a flat sequence of tokens. We treat runs of
	letters/digits/underscore/colon as one token (identifiers, keyword parts,
	numbers) and each other non-space character as its own token (so binary
	operators, brackets, etc. are kept). This normalises whitespace away while
	preserving code structure, so reformatting alone does not change the token
	stream."
	| tokens stream |
	tokens := OrderedCollection new.
	stream := ReadStream on: aString.
	[stream atEnd] whileFalse: [
		| c |
		c := stream next.
		c isSeparator ifFalse: [
			(c isLetter or: [c isDigit or: [c = $_ or: [c = $:]]])
				ifTrue: [
					| word |
					word := WriteStream on: String new.
					word nextPut: c.
					[stream atEnd not and: [
						(stream peek isLetter or: [stream peek isDigit
							or: [stream peek = $_ or: [stream peek = $:]]])]]
						whileTrue: [word nextPut: stream next].
					tokens add: word contents]
				ifFalse: [tokens add: (String with: c)]]].
	^ tokens asArray
]
