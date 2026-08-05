Extension { #name : #SWADataset }

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWADataset class >> openCodeAccessFrom: aSWAOpenCodeAccessData named: aName [
	"An #openCodeAccess dataset over an agent's tool-call log (see
	SWAOpenCodeAccessData) -- the bridge that lets opencode conversations colour a
	Code Map."
	^ self new
		kind: #openCodeAccess;
		name: aName;
		source: aSWAOpenCodeAccessData;
		yourself
]
