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

-- Override for get_columns_in_relation to handle Snowflake Semantic Views
-- 
-- Context: Semantic views are a special Snowflake relation type that cannot
-- be described using standard DESCRIBE TABLE commands. This macro detects
-- semantic views and returns an empty column list for them, while preserving
-- standard behavior for all other relation types.

{% macro snowflake__get_columns_in_relation(relation) -%}
  
  {# First check if this is a semantic view #}
  {%- set check_semantic_view_query -%}
    SELECT COUNT(*) as is_semantic_view
    FROM {{ relation.information_schema('tables') }}
    WHERE table_schema = '{{ relation.schema | upper }}'
      AND table_name = '{{ relation.identifier | upper }}'
      AND table_type = 'SEMANTIC VIEW'
  {%- endset -%}
  
  {%- set check_result = run_query(check_semantic_view_query) -%}
  
  {%- if execute and check_result and check_result.rows | length > 0 -%}
    {%- set is_semantic_view = (check_result.rows[0][0] > 0) -%}
  {%- else -%}
    {%- set is_semantic_view = false -%}
  {%- endif -%}

  {%- if is_semantic_view -%}
    {# For semantic views, we cannot use standard DESCRIBE TABLE #}
    {# Return an empty column list since semantic views are defined via YAML #}
    {# and dbt doesn't need column-level metadata for them #}
    {%- set empty_table = [] -%}
    {{ return(empty_table) }}
  {%- else -%}
    {# For regular tables/views, use the default Snowflake adapter behavior #}
    {%- call statement('get_columns_in_relation', fetch_result=True) %}
      select
        column_name,
        data_type,
        character_maximum_length,
        numeric_precision,
        numeric_scale
      from {{ relation.information_schema('columns') }}
      where table_name = '{{ relation.identifier | upper }}'
        and table_schema = '{{ relation.schema | upper }}'
      order by ordinal_position
    {% endcall -%}
    
    {%- set table = load_result('get_columns_in_relation').table -%}
    {{ return(sql_convert_columns_in_relation(table)) }}
  {%- endif -%}

{%- endmacro %}

