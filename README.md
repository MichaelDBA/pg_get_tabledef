# pg_get_tabledef
PostgreSQL PL/PGSQL function that generates table DDL for the given schema/table.

(c) 2021 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported @ michaeldba@sqlexec.com

Comments and suggestions are very welcome and will have my highest priority in addressing.  If possible, please provide example create table SQL.

## History
**pg_get_tabledef** was considered in the early days (PostgreSQL 8.2), but was ultimately cast aside due to supposed complexities involved when compared to pg_dump and different PG versions.  So since that time, everybody has been writing their own take on what getting table DDL should look like.  This is just one more attempt at it, which in my opinion, is the best one out there as far as I can tell at the present time.
<br/><br/>
I must give credits to some of the folks that provided code snippets that I used when starting to work on this project.  Here is the reference: https://stackoverflow.com/questions/2593803/how-to-generate-the-create-table-sql-statement-for-an-existing-table-in-postgr
<br/>

## Limitations
The current version works with PostgreSQL versions, 10+, mostly due to changes in partitioning from inheritance to declarative that started in PG v10.  I might have time at some point to make it work for v9.6 and lower.


## Overview
This function handles these types of objects:
* column defaults
* user-defined data types
* check constraints
* primary and foreign keys
* indexes
* triggers
* Partitioned tables including their partitions

There are multiple ways to call this function where the differences are only related to whether Foreign Keys and/or Triggers are included.  Here is a description of each parameter:

<pre>in_schema  Required: schema name</pre>
<pre>in_table   Required: table name</pre>
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
select * from public.pg_get_tabledef('myschema','mytable');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', 'FKEYS_EXTERNAL');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', 'FKEYS_EXTERNAL', 'INCLUDE_TRIGGERS');
<br/><br/>

## psql formatting
You can avoid column headers and plus signs at the end of each line by specifying the **-At** parameters:

psql mydatabase  -At
<br/><br/>
psql mydatabase  -At -c "select pg_get_tabledef('myschema','mytable', 'FKEYS_EXTERNAL')"

