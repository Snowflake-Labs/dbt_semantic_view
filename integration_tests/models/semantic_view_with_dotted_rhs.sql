{{ config(materialized='semantic_view') }}

TABLES (
  t1 AS {{ dbt_semantic_view.sv_ref('base_table') }}
)
DIMENSIONS(
  t1.value AS t1.value
)
