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

-- Compare result of a table that refers to the semantic view to calling the semantic view directly
with table_ref as (
  select * from {{ ref('table_refer_to_semantic_view') }}
), sv as (
  select * from semantic_view({{ dbt_semantic_view.sv_ref('semantic_view_basic') }} metrics total_rows)
)
select 'table refer result does not match semantic view result' as error_message
from table_ref, sv
where table_ref.total_rows != sv.total_rows


