-- Create enum types used by this function
DROP TYPE IF EXISTS public.tabledef_fkeys;
DROP TYPE IF EXISTS public.tabledef_trigs;
CREATE TYPE public.tabledef_fkeys AS ENUM ('FKEYS_INTERNAL', 'FKEYS_EXTERNAL', 'FKEYS_COMMENTED', 'FKEYS_NONE');
CREATE TYPE public.tabledef_trigs AS ENUM ('INCLUDE_TRIGGERS', 'NO_TRIGGERS');

-- SELECT * FROM public.pg_get_tabledef('sample', 'address');
CREATE OR REPLACE FUNCTION public.pg_get_tabledef(
  in_schema varchar,
  in_table varchar,
  in_fktype  public.tabledef_fkeys DEFAULT 'FKEYS_INTERNAL',
  in_trigger public.tabledef_trigs DEFAULT 'NO_TRIGGERS'
)
RETURNS text
LANGUAGE plpgsql VOLATILE
AS
$$
 /* ********************************************************************************
COPYRIGHT NOTICE FOLLOWS.  DO NOT REMOVE
Copyright (c) 2021 SQLEXEC LLC

Permission to use, copy, modify, and distribute this software and its documentation 
for any purpose, without fee, and without a written agreement is hereby granted, 
provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL SQLEXEC LLC BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT,INDIRECT SPECIAL, 
INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE 
OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF SQLEXEC LLC HAS BEEN ADVISED OF THE 
POSSIBILITY OF SUCH DAMAGE.

SQLEXEC LLC SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. 
THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND SQLEXEC LLC HAS 
NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

Suggestions: Use "-At" parameters to avoid column header and plus signs on output

SELECT * FROM public.pg_get_tabledef('sample', 'address');
SELECT * FROM public.pg_get_tabledef('sample', 'address', 'FKEYS_INTERNAL');
SELECT * FROM public.pg_get_tabledef('sample', 'address', 'FKEYS_INTERNAL', 'INCLUDE_TRIGGERS');

Assumptions:
1.  Only works with PG v10+ since DDL only works with declarative partitioning, not inheritance-based (V9.6 and earlier).

History:
Date	     Description
==========   ======================================================================  
2021-03-20   Original coding using some snippets from https://stackoverflow.com/questions/2593803/how-to-generate-the-create-table-sql-statement-for-an-existing-table-in-postgr
2021-03-21   Added partitioned table support, i.e., PARTITION BY clause.
2021-03-21   Added WITH clause logic where storage parameters for tables are set.

************************************************************************************ */
  DECLARE
    v_table_ddl text;
    v_table_oid int;
    v_colrec record;
    v_constraintrec record;
    v_indexrec record;
    v_primary boolean := False;
    v_constraint_name text;
    v_fkey_defs text;
    v_trigger text := '';
    v_partition_key text := '';
    v_partbound text;
    v_parent text;
    v_persist text;
    v_temp  text; 
    v_relopts text;
    
  BEGIN
    SELECT c.oid INTO v_table_oid FROM pg_catalog.pg_class c LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind in ('r','p') AND c.relname = in_table AND n.nspname = in_schema;

    -- throw an error if table was not found
    IF (v_table_oid IS NULL) THEN
      RAISE EXCEPTION 'table does not exist';
    END IF;

    -- also see if there are any SET commands for this table, ie, autovacuum_enabled=off, fillfactor=70
    WITH relopts AS (SELECT unnest(c.reloptions) relopts FROM pg_class c, pg_namespace n WHERE n.nspname = in_schema and n.oid = c.relnamespace and c.relname = in_table) 
    SELECT string_agg(r.relopts, ', ') as relopts INTO v_temp from relopts r;
    IF v_temp IS NULL THEN
      v_relopts := '';
    ELSE
      v_relopts := ' WITH (' || v_temp || ')';
      -- RAISE NOTICE 'relopts="%"', v_relopts;
    END IF;

    -- see if this is a declarative child table and if so a one-liner does the trick.
    -- CREATE TABLE sample.foo_bar_baz_6 PARTITION OF sample.foo_bar_baz FOR VALUES FROM (6) TO (7); 
    SELECT pg_get_expr(c1.relpartbound, c1.oid, true) partbound, c2.relname parent INTO v_partbound, v_parent from pg_class c1, pg_namespace n, pg_inherits i, pg_class c2
    WHERE n.nspname = in_schema and n.oid = c1.relnamespace and c1.relname = in_table and c1.oid = i.inhrelid and i.inhparent = c2.oid and c1.relkind = 'r' and  c1.relispartition;
    IF (v_parent IS NOT NULL) THEN
      IF v_relopts <> '' THEN
        v_table_ddl := 'CREATE TABLE ' || in_schema || '.' || in_table || ' PARTITION OF ' || in_schema || '.' || v_parent || ' ' || v_partbound || v_relopts || ';' || E'\n';
      ELSE
        v_table_ddl := 'CREATE TABLE ' || in_schema || '.' || in_table || ' PARTITION OF ' || in_schema || '.' || v_parent || ' ' || v_partbound || ';' || E'\n';
      END IF;
      RETURN v_table_ddl;  
    END IF;

    -- see if this is unlogged or temporary table
    select c.relpersistence into v_persist from pg_class c, pg_namespace n where n.nspname = in_schema and n.oid = c.relnamespace and c.relname = in_table and c.relkind = 'r';
    IF v_persist = 'u' THEN
      v_temp := 'UNLOGGED';
    ELSIF v_persist = 't' THEN
      v_temp := 'TEMPORARY';
    ELSE
      v_temp := '';
    END IF;
    
    -- start the create definition for regular tables
    v_table_ddl := 'CREATE ' || v_temp || ' TABLE ' || in_schema || '.' || in_table || ' (' || E'\n';

    -- define all of the columns in the table; https://stackoverflow.com/a/8153081/3068233
    FOR v_colrec IN
      SELECT c.column_name, c.data_type, c.udt_name, c.character_maximum_length, c.is_nullable, c.column_default, c.numeric_precision, c.numeric_scale, c.is_identity, c.identity_generation        
      FROM information_schema.columns c WHERE (table_schema, table_name) = (in_schema, in_table) ORDER BY ordinal_position
    LOOP
      v_table_ddl := v_table_ddl || '  ' -- note: two char spacer to start, to indent the column
        || v_colrec.column_name || ' '
        || CASE WHEN v_colrec.data_type = 'USER-DEFINED' THEN in_schema || '.' || v_colrec.udt_name ELSE v_colrec.data_type END 
        || CASE WHEN v_colrec.is_identity = 'YES' THEN CASE WHEN v_colrec.identity_generation = 'ALWAYS' THEN ' GENERATED ALWAYS AS IDENTITY' ELSE ' GENERATED BY DEFAULT AS IDENTITY' END ELSE '' END
        || CASE WHEN v_colrec.character_maximum_length IS NOT NULL THEN ('(' || v_colrec.character_maximum_length || ')') 
                WHEN v_colrec.numeric_precision > 0 AND v_colrec.numeric_scale > 0 THEN '(' || v_colrec.numeric_precision || ',' || v_colrec.numeric_scale || ')' 
           ELSE '' END || ' '
        || CASE WHEN v_colrec.is_nullable = 'NO' THEN 'NOT NULL' ELSE 'NULL' END
        || CASE WHEN v_colrec.column_default IS NOT null THEN (' DEFAULT ' || v_colrec.column_default) ELSE '' END
        || ',' || E'\n';
    END LOOP;

    -- define all the constraints in the; https://www.postgresql.org/docs/9.1/catalog-pg-constraint.html && https://dba.stackexchange.com/a/214877/75296
    FOR v_constraintrec IN
      SELECT con.conname as constraint_name, con.contype as constraint_type,
        CASE
          WHEN con.contype = 'p' THEN 1 -- primary key constraint
          WHEN con.contype = 'u' THEN 2 -- unique constraint
          WHEN con.contype = 'f' THEN 3 -- foreign key constraint
          WHEN con.contype = 'c' THEN 4
          ELSE 5
        END as type_rank,
        pg_get_constraintdef(con.oid) as constraint_definition
      FROM pg_catalog.pg_constraint con JOIN pg_catalog.pg_class rel ON rel.oid = con.conrelid JOIN pg_catalog.pg_namespace nsp ON nsp.oid = connamespace
      WHERE nsp.nspname = in_schema AND rel.relname = in_table ORDER BY type_rank
    LOOP
      IF v_constraintrec.type_rank = 1 THEN
          v_primary := True;
          v_constraint_name := v_constraintrec.constraint_name;
      END IF;

      IF in_fktype <> 'FKEYS_INTERNAL' AND v_constraintrec.constraint_type = 'f' THEN
          continue;
      END IF;

      v_table_ddl := v_table_ddl || '  ' -- note: two char spacer to start, to indent the column
        || 'CONSTRAINT' || ' '
        || v_constraintrec.constraint_name || ' '
        || v_constraintrec.constraint_definition
        || ',' || E'\n';
    END LOOP;

    -- drop the last comma before ending the create statement
    v_table_ddl = substr(v_table_ddl, 0, length(v_table_ddl) - 1) || E'\n';

    -- See if this is a partitioned table (pg_class.relkind = 'p') and add the partitioned key 
    SELECT pg_get_partkeydef(c1.oid) as partition_key INTO v_partition_key FROM pg_class c1 JOIN pg_namespace n ON (n.oid = c1.relnamespace) LEFT JOIN pg_partitioned_table p ON (c1.oid = p.partrelid) 
    WHERE n.nspname = in_schema and n.oid = c1.relnamespace and c1.relname = in_table and c1.relkind = 'p';
    
    IF v_partition_key IS NOT NULL AND v_partition_key <> '' THEN
      -- add partition clause
      v_table_ddl := v_table_ddl || ') PARTITION BY ' || v_partition_key || ';' || E'\n';  
    ELSEIF v_relopts <> '' THEN
      v_table_ddl := v_table_ddl || ') ' || v_relopts || ';' || E'\n';  
    ELSE
      -- end the create definition
      v_table_ddl := v_table_ddl || ');' || E'\n';    
    END IF;  

    -- suffix create statement with all of the indexes on the table
    FOR v_indexrec IN
      SELECT indexdef, indexname FROM pg_indexes WHERE (schemaname, tablename) = (in_schema, in_table)
    LOOP
      IF v_indexrec.indexname = v_constraint_name THEN
          continue;
      END IF;
      v_table_ddl := v_table_ddl
        || v_indexrec.indexdef
        || ';' || E'\n';
    END LOOP;

    -- Handle external foreign key defs here if applicable. 
    IF in_fktype = 'FKEYS_EXTERNAL' THEN
      SELECT 'ALTER TABLE ONLY ' || n.nspname || '.' || c2.relname || ' ADD CONSTRAINT ' || r.conname || ' ' || pg_catalog.pg_get_constraintdef(r.oid, true) || ';' into v_fkey_defs 
      FROM pg_constraint r, pg_class c1, pg_namespace n, pg_class c2 where r.conrelid = c1.oid and  r.contype = 'f' and n.nspname = in_schema and n.oid = r.connamespace and r.conrelid = c2.oid and c2.relname = in_table;
      v_table_ddl := v_table_ddl || v_fkey_defs;
    ELSIF  in_fktype = 'FKEYS_COMMENTED' THEN 
      SELECT '-- ALTER TABLE ONLY ' || n.nspname || '.' || c2.relname || ' ADD CONSTRAINT ' || r.conname || ' ' || pg_catalog.pg_get_constraintdef(r.oid, true) || ';' into v_fkey_defs 
      FROM pg_constraint r, pg_class c1, pg_namespace n, pg_class c2 where r.conrelid = c1.oid and  r.contype = 'f' and n.nspname = in_schema and n.oid = r.connamespace and r.conrelid = c2.oid and c2.relname = in_table;
      v_table_ddl := v_table_ddl || v_fkey_defs;
    END IF;
  
    IF in_trigger = 'INCLUDE_TRIGGERS' THEN
      select pg_get_triggerdef(t.oid, True) || ';' INTO v_trigger FROM pg_trigger t, pg_class c, pg_namespace n 
      WHERE n.nspname = in_schema and n.oid = c.relnamespace and c.relname = in_table and c.relkind = 'r' and t.tgrelid = c.oid and NOT t.tgisinternal;
      IF v_trigger <> '' THEN
        v_table_ddl := v_table_ddl || v_trigger;
      END IF;  
    END IF;
  
    -- return the ddl
    RETURN v_table_ddl;
  END;
$$;
