# pg_get_tabledef
**pg_get_tabledef** is a PostgreSQL PL/PGSQL function that generates table DDL for the given schema/table.

(c) 2021-2022 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported by creating an issue here, https://github.com/MichaelDBA/pg_get_tabledef/issues/new/choose.
<br/>
Please provide example code along with issues reported if possible.
<br/>

## History
**pg_get_tabledef** was considered in the early days (PostgreSQL 8.2), but was ultimately cast aside due to supposed complexities involved when compared to pg_dump and different PG versions.  So since that time, everybody has been writing their own take on what getting table DDL should look like.  This is just one more attempt at it, which is one of the best as far as I can tell.
<br/><br/>
I must give credits to some of the folks that provided code snippets that I used when I started to work on this project.  Since that time I have added a lot more areas  that most closely mimics the output of **pg_dump**.  Here is the reference: https://stackoverflow.com/questions/2593803/how-to-generate-the-create-table-sql-statement-for-an-existing-table-in-postgr
<br/>

## Limitations
No ACL information is returned.

## Overview
This function handles these types of objects:
* column defaults
* user-defined data types
* SET and WITH clause storage parameters
* check constraints
* primary and foreign keys
* indexes
* tablespaces for tables and indexes
* triggers (not trigger functions)
* Partitioned tables including their partitions (declarative and inheritance-based)
* Temporary and unlogged tables

There are multiple ways to call this function where the differences are only related to whether Foreign Keys and/or Triggers are included and what format.  Here is a description of each parameter:

<pre>in_schema  Required: schema name</pre>
<pre>in_table   Required: table name</pre>
<pre>verbose    Required: boolean - default=false, useful for debuggin</pre>
<pre>FKEY ENUM  Optional: Default=FKEYS_INTERNAL  Enumeration: 'FKEYS_INTERNAL', 'FKEYS_EXTERNAL', 'FKEYS_COMMENTED', 'FKEYS_NONE'</pre>
<pre>TRIG ENUM  Optional: Default=NO_TRIGGERS     Enumeration: 'INCLUDE_TRIGGERS', 'NO_TRIGGERS'</pre>

With respect to the Foreign Key enumerations:
<br/>
INTERNAL - part of table create statement
<br/>
EXTERNAL - ALTER TABLE ADD FOREIGN KEY statement
<br/>
COMMENTED - EXTERNAL, commented out
<br/><br/>
## Examples
select * from public.pg_get_tabledef('myschema','mytable', false);
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'FKEYS_EXTERNAL');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'FKEYS_EXTERNAL', 'INCLUDE_TRIGGERS');
<br/><br/>

## psql formatting
You can avoid column headers and plus signs at the end of each line by specifying the **-At** parameters:

psql mydatabase  -At
<br/><br/>
psql mydatabase  -At -c "select pg_get_tabledef('myschema','mytable', false, 'FKEYS_EXTERNAL')"

