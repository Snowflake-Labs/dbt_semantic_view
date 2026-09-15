{{ config(materialized='test') }}

-- Regression test for trailing per-entry clauses in TABLES: PRIMARY KEY (...)
-- must not break auto-injection of column comments on dimensions.
-- Description comes from integration_tests/models/schema.yml (base_table.value).
with ddl as (
  select lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_with_primary_key') }}')) as body
)
select 'auto-injected column comment missing from semantic_view_with_primary_key DDL' as error_message
from ddl
where position('generic numeric value column' in body) = 0
