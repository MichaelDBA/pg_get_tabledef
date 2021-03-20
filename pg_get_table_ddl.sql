-- Create enum types used by this function
CREATE TYPE IF NOT EXISTS public.ddl_type AS ENUM ('FKEYS_INTERNAL', 'FKEYS_EXTERNAL', 'FKEYS_COMMENTED', 'FKEYS_NONE');

-- SELECT * FROM public.pg_get_table_ddl('sample', 'address');
CREATE OR REPLACE FUNCTION public.pg_get_table_ddl(
  in_schema varchar,
  in_table varchar,
  in_fktype  public.ddl_type DEFAULT 'FKEYS_INTERNAL'
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


History:
Date	     Description
==========   ======================================================================  
2021-03-20   Original coding
2021-03-21   Change parameters to use ENUMERATED TYPES to add more options for FKEYS.

************************************************************************************ */
  DECLARE
    -- the ddl we're building
    v_table_ddl text;

    -- data about the target table
    v_table_oid int;

    -- records for looping
    v_colrec record;
    v_constraintrec record;
    v_indexrec record;
    v_primary boolean := False;
    v_constraint_name text;
    v_fkey_defs text;
  BEGIN
    SELECT c.oid INTO v_table_oid FROM pg_catalog.pg_class c LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND c.relname = in_table AND n.nspname = in_schema;

    -- throw an error if table was not found
    IF (v_table_oid IS NULL) THEN
      RAISE EXCEPTION 'table does not exist';
    END IF;

    -- start the create definition
    v_table_ddl := 'CREATE TABLE ' || in_schema || '.' || in_table || ' (' || E'\n';

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
      RAISE NOTICE 'table_ddl=%   constraint_def=%',v_table_ddl, v_constraintrec.constraint_definition;
      v_table_ddl := v_table_ddl || '  ' -- note: two char spacer to start, to indent the column
        || 'CONSTRAINT' || ' '
        || v_constraintrec.constraint_name || ' '
        || v_constraintrec.constraint_definition
        || ',' || E'\n';
    END LOOP;

    -- drop the last comma before ending the create statement
    v_table_ddl = substr(v_table_ddl, 0, length(v_table_ddl) - 1) || E'\n';

    -- end the create definition
    v_table_ddl := v_table_ddl || ');' || E'\n';

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
    

    -- return the ddl
    RETURN v_table_ddl;
  END;
$$;
