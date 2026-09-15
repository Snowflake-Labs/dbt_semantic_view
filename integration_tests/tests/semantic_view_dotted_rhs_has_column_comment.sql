{{ config(materialized='test') }}

-- Regression test: a DIMENSIONS entry with a qualified (dotted) RHS column
-- reference must trigger auto-injection just like a bare RHS. Today's line-47
-- regex rejects dotted RHS; this test locks in the relaxed form.
with ddl as (
  select lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_with_dotted_rhs') }}')) as body
)
select 'auto-injected description missing for dimension with qualified (dotted) RHS column reference' as error_message
from ddl
where position('generic numeric value column' in body) = 0
