{{ config(materialized='semantic_view') }}

TABLES(t1 AS {{ dbt_semantic_view.sv_ref('base_table') }}, t2 AS {{ dbt_semantic_view.sv_source('seed_sources', 'base_table2') }})
DIMENSIONS(
  t1.count AS value,
  t2.volume AS value
)
METRICS(
  t1.total_rows AS SUM(t1.count) COMMENT = $$Total row count aggregate$$
)
