# pg_get_tabledef
**pg_get_tabledef** is a PostgreSQL PL/PGSQL function that generates table DDL for the given schema/table.

(c) 2021-2025 SQLEXEC LLC
<br/>
MIT license is conveyed accordingly.
<br/>
Bugs can be reported by creating an issue here.
<br/>
Please provide PG version and example code along with issues reported if possible.
<br/>

## History
**pg_get_tabledef** was considered in the early days (PostgreSQL 8.2), but was ultimately cast aside due to supposed complexities involved when compared to pg_dump and different PG versions.  So since that time, everybody has been writing their own take on what getting table DDL should look like.  This is just one more attempt at it, which is one of the best as far as I can tell.
<br/><br/>
I must give credits to some of the folks that provided code snippets that I used when I started to work on this project.  Since that time I have added a lot more areas  that most closely mimics the output of **pg_dump**.  Here is that original reference: https://stackoverflow.com/questions/2593803/how-to-generate-the-create-table-sql-statement-for-an-existing-table-in-postgr
<br/><br/>
Version 2.0 and higher provides Access Control Lists (ACLs) like owner, grants, policies
<br/><br/>
This function is also used in another github repo for cloning schemas: https://github.com/denishpatel/pg-clone-schema
<br/>

**Sequences, Serial, and Identity**<br/>
Serial is treated the same way as sequences are with explicit sequence definitions.  Although you can create a serial column with the **serial** keyword, when you export it through pg_dump, it loses its **serial** definition and looks like a plain sequence.  This is necessary since it cannot be assumed that we can match a serial column to a specific sequence definition name.  This is consistent with how **pg_dump** handles it.
<br/><br/>

## Limitations
* No support for PG Versions 9.5 and older.

## Overview
This function handles these types of objects:
* column defaults
* user-defined data types
* arrays
* SET and WITH clause storage parameters
* check constraints
* primary and foreign keys
* table and column comments
* indexes
* tablespaces for tables and indexes
* triggers (not trigger functions)
* Partitioned tables including their partitions (declarative and inheritance-based)
* Temporary and unlogged tables
* Access Control Lists (ACLs) information like owner, DCL (grants), and policies (RLS, row level security)

There are multiple ways to call this function where the differences are mostly related to whether Foreign Keys and/or Triggers are included and what format.  Here is a description of each parameter:

<pre>in_schema    TEXT  Required: schema name</pre>
<pre>in_table     TEXT  Required: table name</pre>
<pre>verbose      BOOL  Required: Default=false,                useful for debugging when set to True</pre>
<pre>FKEY         ENUM  Optional: Default=FKEYS_INTERNAL        Enumeration: 'FKEYS_INTERNAL', 'FKEYS_EXTERNAL', 'FKEYS_COMMENTED', 'FKEYS_NONE'</pre>
<pre>TRIG         ENUM  Optional: Default=NO_TRIGGERS           Enumeration: 'INCLUDE_TRIGGERS', 'NO_TRIGGERS'</pre>
<pre>PKEY         ENUM  Optional: Default=internal def          Enumeration: 'PKEY_EXTERNAL'</pre>
<pre>COMMENTS     ENUM  Optional: Default=no comments           Enumeration: 'COMMENTS'</pre>
<pre>SHOWPARTS    ENUM  Optional: Default=no partition info     Enumeration: 'SHOWPARTS'</pre>
<pre>ACL_OWNER    ENUM  Optional: Default=no owner acl          Enumeration: 'ACL_OWNER'</pre>
<pre>ACL_DCL      ENUM  Optional: Default=no grants/owner acls  Enumeration: 'ACL_DCL'</pre>
<pre>ACL_POLICIES ENUM  Optional: Default=no policy acls        Enumeration: 'ACL_POLICIES'</pre>

With respect to the Primary and Foreign Key enumerations:
<br/>
INTERNAL - part of table create statement
<br/>
EXTERNAL - ALTER TABLE ADD PRIMAMRY KEY/FOREIGN KEY statement
<br/><br/>
With regard to ACL parameters (new in version 2), ACL_DCL shows GRANT statements in addition to the ALTER TABLE statement for setting the owner which can be done separately as a single statement with ACL_OWNER.  To  include all ACLs, you must specify ACL_DCL and ACL_POLICIES.
<br/><br/>
## Examples
select * from public.pg_get_tabledef('myschema','mytable', false);
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'ACL_DCL');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'PKEY_EXTERNAL');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'FKEYS_EXTERNAL');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'FKEYS_EXTERNAL', 'INCLUDE_TRIGGERS');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', false, 'PKEY_EXTERNAL', 'FKEYS_EXTERNAL', 'COMMENTS', 'INCLUDE_TRIGGERS');
<br/><br/>
psql clone_testing -c "select * from pg_get_tabledef('sample','emp',false,'COMMENTS','INCLUDE_TRIGGERS')"
![image](https://github.com/MichaelDBA/pg_get_tabledef/assets/12436545/45e5bff3-e6a5-4893-80f5-1bdae25ebd28)

## Compare to pg_dump
pg_dump -t 'myschema.mytable' --schema-only mydb | grep -v '\-\-' | grep -v -e '^[[:space:]]*$'
<br/><br/>
![image](https://github.com/MichaelDBA/pg_get_tabledef/assets/12436545/44e6beda-3707-4cf7-b401-96f45f2182e2)
<br/><br/>

## psql formatting
You can avoid column headers and plus signs at the end of each line by specifying the **-At** parameters:

psql mydatabase  **-At**
<br/><br/>
psql mydatabase  **-At** -c "select pg_get_tabledef('myschema','mytable', false, 'FKEYS_EXTERNAL')"
<br/><br/>
or within a psql sesssion: **\pset format unaligned**

