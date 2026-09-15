{{ config(
    materialized='semantic_view'
) }}

TABLES(
    BASE_TABLE as {{ ref('union_table_refer_to_semantic_views') }}
)
METRICS(
    BASE_TABLE.total_rows as SUM(BASE_TABLE.total_rows)
)