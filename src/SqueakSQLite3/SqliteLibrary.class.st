Class {
	#name : #SqliteLibrary,
	#superclass : #ExternalLibrary,
	#category : #'SqueakSQLite3-Core-Support'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:53'
}
SqliteLibrary class >> default [
	^ default ifNil: [default := super new]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 4/1/2008 20:04'
}
SqliteLibrary class >> moduleName [
	"Was: ^ 'sqlite'"
	^ 'sqlite3'
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiBindDouble: stmt with: index with: double [
	"int sqlite3_bind_double(sqlite3_stmt*, int, double);"
	<cdecl: long 'sqlite3_bind_double' (uint64_t long double)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiBindInt: stmt with: index with: value [
	"int sqlite3_bind_int(sqlite3_stmt*, int, int);"
	<cdecl: long 'sqlite3_bind_int' (uint64_t long long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiBindNull: stmt with: index [
	"int sqlite3_bind_null(sqlite3_stmt*, int);"
	<cdecl: long 'sqlite3_bind_null' (uint64_t long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiBindParameterCount: pStmt [
	"int sqlite3_bind_parameter_count(sqlite3_stmt*)"
	<cdecl: long 'sqlite3_bind_parameter_count' (uint64_t)>
	^ self externalCallFailed 
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiBindText: stmt with: index with: value with: length with: destructor [
	"int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int n, void(*)(void*));"
	<cdecl: long 'sqlite3_bind_text' (uint64_t long char* long int64_t)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'cf 11/23/2005 15:31'
}
SqliteLibrary >> apiChanges: sqlite [
	"int sqlite_changes(sqlite*)"
	<cdecl: long 'sqlite3_changes' (SqliteReference)>
	^ self externalCallFailed 
]

{
	#category : #api,
	#'squeak_changestamp' : 'cf 11/23/2005 15:15'
}
SqliteLibrary >> apiClose: sqlite [
	"int sqlite3_close(sqlite3*)"
	<cdecl: long 'sqlite3_close' (SqliteReference)>
	^ self externalCallFailed 
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiColumnCount: hStmt [
	"int sqlite3_column_count(sqlite3_stmt*);"
	<cdecl: long 'sqlite3_column_count' (uint64_t)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiColumnDouble: hStmt with: iCol [
	"double sqlite3_column_double(sqlite3_stmt*, int iCol);"
	<cdecl: double 'sqlite3_column_double' (uint64_t long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiColumnInt: hStmt with: iCol [
	"int sqlite3_column_int(sqlite3_stmt*, int iCol);"
	<cdecl: long 'sqlite3_column_int' (uint64_t long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiColumnName: hStmt with: iCol [
	"char* sqlite3_column_name(sqlite3_stmt*, int iCol);"
	<cdecl: char* 'sqlite3_column_name' (uint64_t long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiColumnText: hStmt with: iCol [
	"char* sqlite3_column_int(sqlite3_stmt*, int iCol);"
	<cdecl: char* 'sqlite3_column_text' (uint64_t long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiColumnType: hStmt with: iCol [
	"int sqlite3_column_type(sqlite3_stmt*, int iCol);"
	<cdecl: long 'sqlite3_column_type' (uint64_t long)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:07'
}
SqliteLibrary >> apiErrorMessage: anSqlite [
	"const char *sqlite3_errmsg(sqlite3*)"
	<cdecl: char* 'sqlite3_errmsg' (SqliteReference)>
	^ self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiFinalize: pStmt [
	"int sqlite3_finalize(sqlite3_stmt *pStmt);"
	<cdecl: long 'sqlite3_finalize' (uint64_t)>
	^self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:11'
}
SqliteLibrary >> apiFree: anAddress [
	"void sqlite3_free(void*)"
	<cdecl: void 'sqlite3_free' (uint64_t)>
	^ self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'cf 11/23/2005 15:32'
}
SqliteLibrary >> apiFreeTable: buffer [
	"void sqlite3_free_table(char **result)"
	<cdecl: void 'sqlite3_free_table' (SqliteResultBuffer)>
	^ self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'cf 11/23/2005 15:34'
}
SqliteLibrary >> apiGetTable: anSqlite sql: sql buffer: result rows: nRows columns: nColumns error: errBuffer [
	"int sqlite3_get_table(
  sqlite*,
  char *sql,
  char ***result,
  int *nrow,
  int *ncolumn,
  char **errmsg
	)"
	<cdecl: long 'sqlite3_get_table' (SqliteReference char* SqliteResultBuffer* long* long* SqliteError*)>
	^ self externalCallFailed 
]

{
	#category : #api,
	#'squeak_changestamp' : 'cf 11/23/2005 15:35'
}
SqliteLibrary >> apiLastInsertId: sqlite [
	"long long int sqlite3_last_insert_rowid(sqlite3*)"
	<cdecl: longlong 'sqlite3_last_insert_rowid' (SqliteReference)>
	^ self externalCallFailed 
]

{
	#category : #api,
	#'squeak_changestamp' : 'cf 11/22/2005 21:59'
}
SqliteLibrary >> apiOpen: dbName sqlite: sqlite [
	"int sqlite3_open(const char*, sqlite3**);"
	<cdecl: long 'sqlite3_open' (char* SqliteReference*)>
	^ self externalCallFailed
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiPrepareV2: db with: zSql with: nByte with: ppStmt with: pzTail [
	"int sqlite3_prepare_v2(
	  sqlite3 *db,            /* Database handle */
	  const char *zSql,       /* SQL statement, UTF-8 encoded */
	  int nByte,              /* Maximum length of zSql in bytes. */
	  sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
	  const char **pzTail     /* OUT: Pointer to unused portion of zSql */
	);"
	<cdecl: long 'sqlite3_prepare_v2' (SqliteReference char* long uint64_t* uint64_t*)>
	^ self externalCallFailed 
]

{
	#category : #api,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:06'
}
SqliteLibrary >> apiStep: hStmt [
	"int sqlite3_step(sqlite3_stmt*);"
	<cdecl: long 'sqlite3_step' (uint64_t)>
	^self externalCallFailed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:58'
}
SqliteLibrary >> bindArg: arg at: index in: stmt [

	arg == true ifTrue:[^self apiBindInt: stmt with: index with: 1].
	arg == false ifTrue:[^self apiBindInt: stmt with: index with: 0].
	arg ==  nil ifTrue:[^self apiBindNull: stmt with: index].

	"int64 for the same reason #execute:args:on:do: reads int64: binding a value
	above 2^31 through sqlite3_bind_int wraps it, silently matching the wrong row."
	arg isInteger ifTrue:[^self apiBindInt64: stmt with: index with: arg].
	arg isFloat ifTrue:[^self apiBindDouble: stmt with: index with: arg].
	arg isString ifTrue:[^self apiBindText: stmt with: index with: arg with: arg size with: -1].
	(arg isKindOf: DateAndTime) ifTrue:[ | string |
		string := String streamContents:[:s|
			arg printYMDOn: s withLeadingSpace: false.
			s nextPut: $T.
			arg printHMSOn: s.
		].
		^self bindArg: string at: index in: stmt
	].
	self error: 'Cannot bind argument'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'ab 1/31/2003 16:20'
}
SqliteLibrary >> changedRows: anSqliteRef [
	^ self apiChanges: anSqliteRef
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:11'
}
SqliteLibrary >> checkError: anError [
	"anError is the char** out-parameter filled in by sqlite3_get_table.
	The message it points to is owned by sqlite and must be released
	with sqlite3_free, not with the libc free()."

	| addr message |
	(anError getHandle allSatisfy: [:i | i = 0]) ifTrue: [^ self].
	addr := (anError getHandle pointerAt: 1) getHandle.
	message := (ExternalData fromHandle: addr type: ExternalType string) fromCString.
	self apiFree: addr asInteger.
	self error: message
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'ar 12/8/2011 14:32'
}
SqliteLibrary >> checkErrorInteger: anError [
	|message|
	(anError = 0) ifTrue: [^self].
	"Get the errmsg"

	message := 'Result Code: ', anError asString.
	self error: message
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:52'
}
SqliteLibrary >> close: anSqliteRef [
	| err |
	err := self apiClose: anSqliteRef.
	self checkErrorInteger: err.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:58'
}
SqliteLibrary >> execute: query args: args on: sqliteRef do: aBlock [
	"Execute the given query, binding the arguments as needed"

	| ppStmt hStmt code colCount result value err names rval |
	ppStmt := DoubleWordArray new: 1.
	(err := self apiPrepareV2: sqliteRef with: query with: query size with: ppStmt with: nil) == 0
		ifFalse:[self error: 'sqlite3_prepare_v2 failed (', err printString, '): ',
			(self apiErrorMessage: sqliteRef)].
	hStmt := ppStmt at: 1.
	(self apiBindParameterCount: hStmt) = args size 
		ifFalse:[self error:'Argument count mismatch'].
	1 to: args size do:[:idx|
		self bindArg: (args at: idx) at: idx in: hStmt.
	].
	colCount := nil.
	[code := self apiStep: hStmt.
	code = 100] whileTrue:[
		colCount ifNil:[
			colCount := self apiColumnCount: hStmt.
			result := Array new: colCount.
			names := Array new: colCount.
			1 to: colCount do:[:i|
				names at: i put: (self apiColumnName: hStmt with: i-1) asSymbol.
			].
		].
		1 to: colCount do:[:i| | colIdx |
			colIdx := i-1.
			(self apiColumnType: hStmt with: colIdx) caseOf: {
				"int64, NOT int: sqlite3_column_int truncates to 32 bits silently,
				which turns every millisecond timestamp into a negative number."
				[1] -> [value := self apiColumnInt64: hStmt with: colIdx].
				[2] -> [value := self apiColumnDouble: hStmt with: colIdx].
				[3] -> [value := self apiColumnText: hStmt with: colIdx].
				[4] -> [self error: 'Blobs are not supported'].
				[5] -> [value := nil].
			}.
			result at: i put: value.
		].
		rval := aBlock numArgs = result size 
			ifTrue:[aBlock valueWithArguments: result]
			ifFalse:[aBlock value: (SQLiteRecord names: names values: result)].
	].
	self apiFinalize: hStmt.
	code = 101 ifFalse:[self error: 'Error code: ', code printString].
	^rval
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'ab 12/16/2002 01:30'
}
SqliteLibrary >> freeResultBuffer: aResultBuffer [
	self apiFreeTable: aResultBuffer
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'ab 12/16/2002 00:23'
}
SqliteLibrary >> lastInsertId: anSqliteRef [
	^ self apiLastInsertId: anSqliteRef
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'cf 11/23/2005 15:22'
}
SqliteLibrary >> open: aString [
	|err ref|
	ref := SqliteReference new.
	err := self apiOpen: aString sqlite: ref.
	self checkErrorInteger: err.
	^ ref
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 19:52'
}
SqliteLibrary >> resultForQuery: aString on: sqliteRef [
	|nrows ncols buffer err|
	nrows := WordArray new: 1.
	ncols := WordArray new: 1.
	err := SqliteError new.
	buffer := SqliteResultBuffer new.
	self apiGetTable: sqliteRef sql: aString buffer: buffer rows: nrows columns: ncols error: err.
	self checkError: err.
	^ SqliteResult buffer: buffer rows: nrows first columns: ncols first
]
