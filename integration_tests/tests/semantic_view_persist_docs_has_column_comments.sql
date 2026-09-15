{{ config(materialized='test') }}

-- Assert the resolved-from-graph column description appears twice in the
-- DIMENSIONS clause (once per alias, both resolve to `value` description)
-- and the explicit description override appears on the METRIC.
-- Expected description strings are defined in integration_tests/models/schema.yml
-- (base_table.value) and integration_tests/models/source.yml (base_table2.value);
-- if those YAMLs change, update the literals below.
with ddl as (
  select lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_with_persist_docs') }}')) as body
),
checks as (
  select
    (length(body) - length(replace(body, 'generic numeric value column', ''))) / length('generic numeric value column') as dim_desc_count,
    position('total row count aggregate' in body) as metric_desc_pos
  from ddl
)
select error_message from (
  select 'dimension value-column description not present twice' as error_message, 1 as ord
  from checks where dim_desc_count < 2
  union all
  select 'metric description override missing' as error_message, 2 as ord
  from checks where metric_desc_pos = 0
)
