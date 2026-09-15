{{ config(materialized='semantic_view') }}

TABLES (
  t1 AS {{ dbt_semantic_view.sv_ref('base_table') }} UNIQUE (id),
  t2 AS {{ dbt_semantic_view.sv_source('seed_sources', 'base_table2') }} WITH SYNONYMS ('bt2', 'alias2')
)
DIMENSIONS(
  t1.value_from_schema AS value,
  t2.value_from_source AS value
)
