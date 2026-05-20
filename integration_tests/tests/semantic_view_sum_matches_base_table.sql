-- Copyright 2025 Snowflake Inc. 
-- SPDX-License-Identifier: Apache-2.0
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{{ config(materialized='test') }}

-- Compare sum(value) from BASE_TABLE to metric from semantic view
with base_sum as (
  select sum(value) as v from {{ ref('base_table') }}
), sv as (
  select * from semantic_view({{ dbt_semantic_view.sv_ref('semantic_view_basic') }} metrics total_rows)
)
select 'semantic view metric does not match base_table sum' as error_message
from base_sum, sv
where base_sum.v != sv.total_rows