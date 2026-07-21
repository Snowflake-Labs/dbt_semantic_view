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

{#
  Generic dbt test: assert a named materialization exists on a semantic view.

  Usage in schema.yml:
    models:
      - name: my_semantic_view
        tests:
          - dbt_semantic_view.materialization_exists:
              materialization_name: my_mat
#}
{% test materialization_exists(model, materialization_name) %}
  {%- call statement('show_mats', fetch_result=True) -%}
    show materializations in semantic view {{ model }}
  {%- endcall -%}
  {%- set result = load_result('show_mats') -%}
  {%- set found = [] -%}
  {%- for row in result['data'] -%}
    {%- if row[0] | upper == materialization_name | upper -%}
      {%- do found.append(1) -%}
    {%- endif -%}
  {%- endfor -%}
  select 'materialization {{ materialization_name }} does not exist on {{ model }}' as error_message
  where {{ found | length }} = 0
{% endtest %}


{#
  Generic dbt test: assert a named materialization exists and is not suspended.

  Usage in schema.yml:
    models:
      - name: my_semantic_view
        tests:
          - dbt_semantic_view.materialization_is_active:
              materialization_name: my_mat
#}
{% test materialization_is_active(model, materialization_name) %}
  {%- call statement('show_mats_active', fetch_result=True) -%}
    show materializations in semantic view {{ model }}
  {%- endcall -%}
  {%- set result = load_result('show_mats_active') -%}

  {# SCHEDULING_STATUS is column 1 in SHOW MATERIALIZATIONS output #}
  {%- set ns = namespace(status_idx=1) -%}
  {%- for col in result['columns'] -%}
    {%- if col.name | upper == 'SCHEDULING_STATUS' -%}
      {%- set ns.status_idx = loop.index0 -%}
    {%- endif -%}
  {%- endfor -%}

  {%- set found = [] -%}
  {%- set active = [] -%}
  {%- for row in result['data'] -%}
    {%- if row[0] | upper == materialization_name | upper -%}
      {%- do found.append(1) -%}
      {%- if (row[ns.status_idx] | upper) != 'SUSPENDED' -%}
        {%- do active.append(1) -%}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}

  select 'materialization {{ materialization_name }} does not exist on {{ model }}' as error_message
  where {{ found | length }} = 0
  union all
  select 'materialization {{ materialization_name }} is suspended on {{ model }}' as error_message
  where {{ found | length }} > 0 and {{ active | length }} = 0
{% endtest %}
