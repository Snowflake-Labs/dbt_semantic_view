{{ config(materialized='test') }}

-- Regression test: per-entry COMMENT = '...' on a TABLES entry must not
-- break auto-injection of the column-level description on the dimension.
with ddl as (
  select lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_with_table_comment_clause') }}')) as body
)
select 'auto-injected column comment missing when TABLES entry carries a COMMENT clause' as error_message
from ddl
where position('generic numeric value column' in body) = 0
