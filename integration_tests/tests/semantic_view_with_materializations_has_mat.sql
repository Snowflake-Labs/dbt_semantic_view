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

-- Verifies that the materialization declared in sv_materializations was actually
-- created on the semantic view. Returns a row (test failure) if it is missing.

{% call statement('show_mats', fetch_result=True) %}
  show materializations in semantic view {{ ref('semantic_view_with_materializations') }}
{% endcall %}

{%- set result = load_result('show_mats') -%}
{%- set base_found = [] -%}
{%- set filtered_found = [] -%}
{%- set immutable_found = [] -%}
{%- for row in result['data'] -%}
  {%- if row[0] | upper == 'TEST_MAT_BY_VALUE' -%}
    {%- do base_found.append(1) -%}
  {%- endif -%}
  {%- if row[0] | upper == 'TEST_MAT_FILTERED_BY_VALUE' -%}
    {%- do filtered_found.append(1) -%}
  {%- endif -%}
  {%- if row[0] | upper == 'TEST_MAT_IMMUTABLE_BY_VALUE' and 'value < 10' in (row[7] | lower) -%}
    {%- do immutable_found.append(1) -%}
  {%- endif -%}
{%- endfor -%}

select 'materialization test_mat_by_value was not created on semantic_view_with_materializations' as error_message
where {{ base_found | length }} = 0

union all

select 'materialization test_mat_filtered_by_value was not created on semantic_view_with_materializations' as error_message
where {{ filtered_found | length }} = 0

union all

select 'materialization test_mat_immutable_by_value was not created with immutable_where on semantic_view_with_materializations' as error_message
where {{ immutable_found | length }} = 0
