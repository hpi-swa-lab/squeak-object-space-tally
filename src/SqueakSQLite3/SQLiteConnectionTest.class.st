Class {
	#name : #SQLiteConnectionTest,
	#superclass : #TestCase,
	#instVars : [
		'db'
	],
	#category : #'SqueakSQLite3-Tests'
}

{
	#category : #running,
	#'squeak_changestamp' : 'ar 12/8/2011 14:40'
}
SQLiteConnectionTest >> databaseFileName [
	"Macs (tested OS X 6.2) require absolute file paths to the database, Windows and Ubuntu do not"
	
	^ FileDirectory default fullNameFor: self databaseName.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'spd 5/19/2010 14:32'
}
SQLiteConnectionTest >> databaseName [
	^'sqlite_test_database.db'
	

]

{
	#category : #accessing,
	#'squeak_changestamp' : 'tbn 1/25/2010 20:06'
}
SQLiteConnectionTest >> defaultTestClass [
	^SQLiteConnection 
]

{
	#category : #running,
	#'squeak_changestamp' : 'spd 5/19/2010 14:36'
}
SQLiteConnectionTest >> setUp [
	super setUp.
	
	db := self defaultTestClass fileNamed: self databaseFileName.
]

{
	#category : #running,
	#'squeak_changestamp' : 'ar 12/8/2011 14:40'
}
SQLiteConnectionTest >> tearDown [
	db close.
	FileDirectory default deleteFileNamed: self databaseName.
	super tearDown
]

{
	#category : #testing,
	#'squeak_changestamp' : 'tbn 1/25/2010 20:28'
}
SQLiteConnectionTest >> testInstanceCreation [
 
	self 
		assert: db notNil;
		assert: db class = self defaultTestClass;
		deny: (self defaultTestClass registry includes: db).
	

]

{
	#category : #testing,
	#'squeak_changestamp' : 'ar 1/4/2012 10:50'
}
SQLiteConnectionTest >> testPreparedStatements [

	(db execute: 'select * from sqlite_master' args: {}) ifEmpty:[
		db execute: 'create table employee (id INTEGER PRIMARY KEY, name TEXT, created DATE)'
			args: {}.
	].
	db execute: 'insert into employee values (?, ?, ?)' 
		args: {1. 'Adam'. DateAndTime now}.
	db execute: 'insert into employee values (?, ?, ?)' 
		args: {2. 'Eve'. nil}.
	db execute: 'select id, name from employee where name = ?' args: {'Adam'} do:[:id :name|
		self assert: id = 1.
		self assert: name = 'Adam'.
	].

	db execute: 'select * from employee where name = ?' args: {'Eve'} do:[:id :name :created|
		self assert: id = 2.
		self assert: name = 'Eve'.
		self assert: created = nil.
	].

]

{
	#category : #testing,
	#'squeak_changestamp' : 'tbn 1/25/2010 20:28'
}
SQLiteConnectionTest >> testRegistration [

	db open.
	
	self assert: (self defaultTestClass registry includes: db).	
	
	db close.
	
	self deny: (self defaultTestClass registry includes: db).	
]

{
	#category : #testing,
	#'squeak_changestamp' : 'tbn 1/25/2010 20:54'
}
SQLiteConnectionTest >> testTableCreation [
	|sql|
	db open.	
	sql := 'CREATE TABLE ABC (ID INTEGER PRIMARY KEY, Name TEXT)'.
	db executeQuery: sql.
	db withResultForQuery: 'select * from sqlite_master;' do: [:each | 
		self assert: sql = (each nextRow at: 'sql')] 
	 
]

{
	#category : #testing,
	#'squeak_changestamp' : 'tbn 1/25/2010 21:03'
}
SQLiteConnectionTest >> testUseDatabase [
	|s1 s2 s3 arrayOfDicts|
	s1 := 'create table employee (id, name)'.
	s2 := 'insert into employee values (1, ''Adam'')'.
	s3 := 'insert into employee values (2, ''Eve'')'.
	(Array with: s1 with: s2 with: s3)
		do: [:sql | db  executeQuery: sql].
	
	arrayOfDicts := db executeQuery: 'SELECT * FROM employee'.
	self assert: arrayOfDicts size = 2.
	self assert: (arrayOfDicts first at: 'name') = 'Adam'
	
]
