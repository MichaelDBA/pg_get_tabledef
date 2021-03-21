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
There are multiple ways to call this function where the differences are only related to how Foreign Keys are used.  The third parameter is optional, which defaults to the ENUMERATED value, 'FKEYS_INTERNAL'.  Here is a description of each enumerated type:
1.  FKEYS_INTERNAL: Foreign Key definition is included within the table definition.
2.  FKEYS_EXTERNAL: Foreign Key definition is defined outside the table definition.
2.  FKEYS_COMMENTED: Foreign Key definition is defined outside the table definition, but is commented out.
2.  FKEYS_NONE: No Foreign Key definitions are generated.


## Examples
select * from public.pg_get_tabledef('myschema','mytable');
<br/><br/>
select * from public.pg_get_tabledef('myschema','mytable', 'FKEYS_EXTERNAL');
<br/><br/>


## psql formatting
You can avoid column headers and plus signs at the end of each line by specifying the **-At** parameters:

psql mydatabase  -At
<br/><br/>
psql mydatabase  -At -c "select pg_get_tabledef('myschema','mytable', 'FKEYS_EXTERNAL')"

