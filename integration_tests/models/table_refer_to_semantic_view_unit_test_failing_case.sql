{{ config(materialized='table') }}

with base as (
  select 1 as x
)
select b.x, s.*
from base b
cross join (
  select *
  from semantic_view(
    {{ ref('semantic_view_basic_for_unit_test') }}
    metrics total_rows, max_volume
  )
) s
