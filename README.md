# pg_get_tabledef
PostgreSQL PL/PGSQL function that generates table DDL for the given schema/table.

(c) 2021 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported @ michaeldba@sqlexec.com


## History
There are various forms of generating table DDL out there, and this is one more to add to the list.  I think this is more complete than the ones I have found on the internet.

## Overview
There are multiple ways to call this function where the differences are only related to whether Foreign Keys and/or Triggers are included.  Here is a description of each parameter:

`in_schema`         Required: schema name
<br/>
`in_table`          Required: table name
<br/>
`FKEY ENUM`         Optional: FOREIGN KEY Enumeration: 'FKEYS_INTERNAL', 'FKEYS_EXTERNAL', 'FKEYS_COMMENTED', 'FKEYS_NONE'
<br/>
`TRIG ENUM`         Optional: TRIGGER Enumeration: 'INCLUDE_TRIGGERS', 'NO_TRIGGERS'
<br/>


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

