Extension { #name : #SqliteLibrary }

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:58'
}
SqliteLibrary >> apiBindInt64: hStmt with: index with: value [
	"int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);

	The binding counterpart of #apiColumnInt64:with:. Without it, passing a
	millisecond timestamp as a query argument silently binds a wrapped 32-bit
	value, so the row you match is not the row you asked for."
	<cdecl: long 'sqlite3_bind_int64' (uint64_t long int64_t)>
	^ self externalCallFailed
]

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:58'
}
SqliteLibrary >> apiColumnInt64: hStmt with: iCol [
	"sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol);

	SQLite's native integer is 64-bit; sqlite3_column_int TRUNCATES to 32 and does
	so silently. Any Unix millisecond timestamp (~1.78e12) comes back wrapped and
	negative, which is not a rounding error but a wrong number that still looks
	like a plausible one -- opencode's session times all read as 1969."
	<cdecl: int64_t 'sqlite3_column_int64' (uint64_t long)>
	^ self externalCallFailed
]

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:23'
}
SqliteLibrary >> apiOpenV2: dbName sqlite: sqlite flags: flags vfs: vfsName [
	"int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs);

	Unlike sqlite3_open (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) this lets us
	pass SQLITE_OPEN_READONLY (1), which is what analysing somebody else's live
	database requires."
	<cdecl: long 'sqlite3_open_v2' (char* SqliteReference* long char*)>
	^ self externalCallFailed
]

{
	#category : #'*SWA-OpenCode',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:23'
}
SqliteLibrary >> openReadOnly: aString [
	"Open an existing database file for reading only. Fails (rather than creating an
	empty database) if the file is not there."
	| err ref |
	ref := SqliteReference new.
	err := self apiOpenV2: aString sqlite: ref flags: 1 vfs: nil.
	self checkErrorInteger: err.
	^ ref
]
