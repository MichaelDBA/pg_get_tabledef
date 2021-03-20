# pg_get_table_ddl
PostgreSQL PL/PGSQL function that generates table DDL for the given schema/table.

(c) 2021 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported @ michaeldba@sqlexec.com


## History
There are various forms of generating table DDL out there, and this is one more to add to the list.  I think this is more complete than the ones I have found on the internet.

## Overview
There are 2 ways to call this function:
1.  Providing just the first 2 parameters: schema and table.  This will include any Foreign Keys within the create table statement.
2.  Providing a boolean=False as the optional 3rd parameter, which will generate the create table statement without foreign key definitions.

## Examples
select * from public.pg_get_table_ddl('myschema','mytable');
<br/><br/>
select * from public.pg_get_table_ddl('myschema','mytable', False);
<br/><br/>
