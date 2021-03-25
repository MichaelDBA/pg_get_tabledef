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

************************************************************************************ */

-- History:
-- Date	     Description
-- ==========   ======================================================================  
-- 2021-03-20   Original coding using some snippets from 
--              https://stackoverflow.com/questions/2593803/how-to-generate-the-create-table-sql-statement-for-an-existing-table-in-postgr
-- 2021-03-21   Added partitioned table support, i.e., PARTITION BY clause.
-- 2021-03-21   Added WITH clause logic where storage parameters for tables are set.
-- 2021-03-22   Added tablespace logic for tables and indexes.
-- 2021-03-24   Added inheritance-based partitioning support for PG 9.6 and lower.

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
    v_temp  text := ''; 
    v_relopts text;
    v_tablespace text;
    v_pgversion int;
    bPartition boolean;
    bInheritance boolean;
    bRelispartition boolean;
    
  BEGIN
    SELECT c.oid, (select setting from pg_settings where name = 'server_version_num') INTO v_table_oid, v_pgversion FROM pg_catalog.pg_class c LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind in ('r','p') AND c.relname = in_table AND n.nspname = in_schema;
    -- RAISE NOTICE 'version=%', v_pgversion;
    -- throw an error if table was not found
    IF (v_table_oid IS NULL) THEN
      RAISE EXCEPTION 'table does not exist';
    END IF;

    -- get user-defined tablespaces if applicable
    SELECT tablespace INTO v_temp FROM pg_tables WHERE schemaname = in_schema and tablename = in_table and tablespace IS NOT NULL;
    IF v_tablespace IS NULL THEN
      v_tablespace := 'TABLESPACE pg_default';
    ELSE
      v_tablespace := 'TABLESPACE ' || v_temp;
    END IF;

    -- also see if there are any SET commands for this table, ie, autovacuum_enabled=off, fillfactor=70
    WITH relopts AS (SELECT unnest(c.reloptions) relopts FROM pg_class c, pg_namespace n WHERE n.nspname = in_schema and n.oid = c.relnamespace and c.relname = in_table) 
    SELECT string_agg(r.relopts, ', ') as relopts INTO v_temp from relopts r;
    IF v_temp IS NULL THEN
      v_relopts := '';
    ELSE
      v_relopts := ' WITH (' || v_temp || ')';
    END IF;
    
    -- -----------------------------------------------------------------------------------
    -- Create table defs for partitions/children using inheritance or declarative methods.
    -- inheritance: pg_class.relkind = 'r'   pg_class.relispartition=false   pg_class.relpartbound is NULL
    -- declarative: pg_class.relkind = 'r'   pg_class.relispartition=true    pg_class.relpartbound is NOT NULL
    -- -----------------------------------------------------------------------------------
    v_partbound := '';
    bPartition := False;
    bInheritance := False;
    IF v_pgversion < 100000 THEN
      SELECT c2.relname parent INTO v_parent from pg_class c1, pg_namespace n, pg_inherits i, pg_class c2
      WHERE n.nspname = in_schema and n.oid = c1.relnamespace and c1.relname = in_table and c1.oid = i.inhrelid and i.inhparent = c2.oid and c1.relkind = 'r';      
      IF (v_parent IS NOT NULL) THEN
        bPartition   := True;
        bInheritance := True;
      END IF;
    ELSE
      SELECT c2.relname parent, c1.relispartition, pg_get_expr(c1.relpartbound, c1.oid, true) INTO v_parent, bRelispartition, v_partbound from pg_class c1, pg_namespace n, pg_inherits i, pg_class c2
      WHERE n.nspname = in_schema and n.oid = c1.relnamespace and c1.relname = in_table and c1.oid = i.inhrelid and i.inhparent = c2.oid and c1.relkind = 'r';
      IF (v_parent IS NOT NULL) THEN
        bPartition   := True;
        IF bRelispartition THEN
          bInheritance := False;
        ELSE
          bInheritance := True;
        END IF;
      END IF;
    END IF;
   
    IF bPartition THEN
      IF bInheritance THEN
        -- inheritance-based
        v_table_ddl := 'CREATE TABLE ' || in_schema || '.' || in_table || '( '|| E'\n';
        -- Jump to constraints section to add the check constraints
      ELSE
        -- declarative-based
        IF v_relopts <> '' THEN
          v_table_ddl := 'CREATE TABLE ' || in_schema || '.' || in_table || ' PARTITION OF ' || in_schema || '.' || v_parent || ' ' || v_partbound || v_relopts || ' ' || v_tablespace || '; ' || E'\n';
        ELSE
          v_table_ddl := 'CREATE TABLE ' || in_schema || '.' || in_table || ' PARTITION OF ' || in_schema || '.' || v_parent || ' ' || v_partbound || ' ' || v_tablespace || '; ' || E'\n';
        END IF;
        -- Jump to constraints and index section to add the check constraints and indexes and perhaps FKeys
      END IF;
    END IF;
    -- RAISE NOTICE 'DDL so far3=%', v_table_ddl;

    IF NOT bPartition THEN
      -- see if this is unlogged or temporary table
      select c.relpersistence into v_persist from pg_class c, pg_namespace n where n.nspname = in_schema and n.oid = c.relnamespace and c.relname = in_table and c.relkind = 'r';
      IF v_persist = 'u' THEN
        v_temp := 'UNLOGGED';
      ELSIF v_persist = 't' THEN
        v_temp := 'TEMPORARY';
      ELSE
        v_temp := '';
      END IF;
    END IF;
    
    -- start the create definition for regular tables unless we are in progress creating an inheritance-based child table
    IF NOT bPartition THEN
      v_table_ddl := 'CREATE ' || v_temp || ' TABLE ' || in_schema || '.' || in_table || ' (' || E'\n';
    END IF;
    
    -- define all of the columns in the table unless we are in progress creating an inheritance-based child table
    IF NOT bPartition THEN
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
    END IF;
    -- RAISE NOTICE 'DDL so far4=%', v_table_ddl;
    
    -- define all the constraints
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
          IF bPartition THEN
            continue;
          END IF;
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

    -- ---------------------------------------------------------------------------
    -- at this point we have everything up to the last table-enclosing parenthesis
    -- ---------------------------------------------------------------------------
    -- RAISE NOTICE 'ddlsofar1: %', v_table_ddl;

    -- See if this is an inheritance-based child table and finish up the table create.
    IF bPartition and bInheritance THEN
      v_table_ddl := v_table_ddl || ') INHERITS (' || in_schema || '.' || v_parent || ') ' || E'\n' || v_relopts || ' ' || v_tablespace || ';' || E'\n';
    END IF;

    IF v_pgversion >= 100000 AND NOT bPartition and NOT bInheritance THEN
      -- See if this is a partitioned table (pg_class.relkind = 'p') and add the partitioned key 
      SELECT pg_get_partkeydef(c1.oid) as partition_key INTO v_partition_key FROM pg_class c1 JOIN pg_namespace n ON (n.oid = c1.relnamespace) LEFT JOIN pg_partitioned_table p ON (c1.oid = p.partrelid) 
      WHERE n.nspname = in_schema and n.oid = c1.relnamespace and c1.relname = in_table and c1.relkind = 'p';

      IF v_partition_key IS NOT NULL AND v_partition_key <> '' THEN
        -- add partition clause
        -- NOTE:  cannot specify default tablespace for partitioned relations
        -- v_table_ddl := v_table_ddl || ') PARTITION BY ' || v_partition_key || ' ' || v_tablespace || ';' || E'\n';  
        v_table_ddl := v_table_ddl || ') PARTITION BY ' || v_partition_key || ';' || E'\n';  
      ELSEIF v_relopts <> '' THEN
        v_table_ddl := v_table_ddl || ') ' || v_relopts || ' ' || v_tablespace || ';' || E'\n';  
      ELSE
        -- end the create definition
        v_table_ddl := v_table_ddl || ') ' || v_tablespace || ';' || E'\n';    
      END IF;  
    END IF;

    -- RAISE NOTICE 'ddlsofar2: %', v_table_ddl;
    
    -- Add closing paren for regular tables
    -- IF NOT bPartition THEN
    -- v_table_ddl := v_table_ddl || ') ' || v_relopts || ' ' || v_tablespace || E';\n';  
    -- END IF;
    -- RAISE NOTICE 'ddlsofar3: %', v_table_ddl;
   
    -- create indexes
    FOR v_indexrec IN
      SELECT indexdef, COALESCE(tablespace, 'pg_default') as tablespace, indexname FROM pg_indexes WHERE (schemaname, tablename) = (in_schema, in_table)
    LOOP
      -- RAISE NOTICE 'indexdef=%', v_indexrec.indexdef;
      IF v_indexrec.indexname = v_constraint_name THEN
          continue;
      END IF;
      
      -- Add IF NOT EXISTS clause so partition index additions will not be created if declarative partition in effect and index already created on parent
      v_indexrec.indexdef := REPLACE(v_indexrec.indexdef, 'CREATE INDEX', 'CREATE INDEX IF NOT EXISTS');
      
      -- NOTE:  cannot specify default tablespace for partitioned relations
      IF v_partition_key IS NOT NULL AND v_partition_key <> '' THEN
        v_table_ddl := v_table_ddl || v_indexrec.indexdef || ';' || E'\n';
      ELSE
        v_table_ddl := v_table_ddl || v_indexrec.indexdef || ' TABLESPACE ' || v_indexrec.tablespace || ';' || E'\n';
      END IF;
      
    END LOOP;
    -- RAISE NOTICE 'ddlsofar4: %', v_table_ddl;
    
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
    -- RAISE NOTICE 'ddlsofar5: %', v_table_ddl;
    IF in_trigger = 'INCLUDE_TRIGGERS' THEN
      select pg_get_triggerdef(t.oid, True) || ';' INTO v_trigger FROM pg_trigger t, pg_class c, pg_namespace n 
      WHERE n.nspname = in_schema and n.oid = c.relnamespace and c.relname = in_table and c.relkind = 'r' and t.tgrelid = c.oid and NOT t.tgisinternal;
      IF v_trigger <> '' THEN
        v_table_ddl := v_table_ddl || v_trigger;
      END IF;  
    END IF;
  
    -- add empty line
    v_table_ddl := v_table_ddl || E'\n';

    RETURN v_table_ddl;
  END;
$$;
