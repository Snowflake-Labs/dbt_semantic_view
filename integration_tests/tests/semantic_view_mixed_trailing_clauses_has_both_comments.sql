{{ config(materialized='test') }}

-- Regression test for multi-entry TABLES combined with trailing per-entry
-- clauses. Covers UNIQUE + WITH SYNONYMS end-to-end — both dims rely on
-- auto-injection, so the walker must strip both trailing clauses for the
-- dot-splitter to identify the correct source tables.
-- Both base_table.value (models/schema.yml) and base_table2.value (source.yml)
-- share the description "Generic numeric value column", so we assert the
-- string appears at least twice: once per successfully-auto-injected dim.
with ddl as (
  select lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_with_mixed_trailing_clauses') }}')) as body
)
select 'auto-injected description should appear twice (once per dim) but appears fewer than 2 times — walker may have failed to strip UNIQUE or WITH SYNONYMS' as error_message
from ddl
where regexp_count(body, 'generic numeric value column') < 2
