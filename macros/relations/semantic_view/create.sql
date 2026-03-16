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

{% macro snowflake__get_create_semantic_view_sql(relation, sql) -%}
{#-
--  Produce DDL that creates a semantic view
--
--  Args:
--  - relation: Union[SnowflakeRelation, str]
--      - SnowflakeRelation - required for relation.render()
--      - str - is already the rendered relation name
--  - sql: str - the code defining the model
--  Returns:
--      A valid DDL statement which will result in a new semantic view.
-#}

  create or replace semantic view {{ relation }}
  {{ sql }}

{%- endmacro %}


{% macro append_ca_extension_if_missing(sql, ca_json) -%}
  {%- set s = (sql | trim) -%}
  {%- if not s -%}
    {{- s -}}
  {%- else -%}
    {%- set had_semicolon = (s[-1:] == ';') -%}
    {%- if had_semicolon -%}
      {%- set s = (s[:-1] | trim) -%}
    {%- endif -%}

    {# If the model SQL already includes a WITH EXTENSION clause, do not try to merge. #}
    {%- if 'with extension' in (s | lower) -%}
      {{- s -}}
    {%- else -%}
      {%- set out = s ~ "\nWITH EXTENSION (CA = '" ~ ca_json ~ "')" -%}
      {{- out -}}
    {%- endif -%}
  {%- endif -%}
{%- endmacro %}

{% macro append_copy_grants_if_missing(sql) -%}
  {%- set s = (sql | trim) -%}
  {%- set had_semicolon = (s[-1:] == ';') -%}
  {%- if had_semicolon -%}
    {%- set s = (s[:-1] | trim) -%}
  {%- endif -%}

  {# detect existing COPY GRANTS at the end, case/whitespace-insensitive #}
  {%- set tokens = s.split() -%}
  {%- set ends_with_copy = (tokens | length >= 2) 
      and ((tokens[-2] | lower) == 'copy')
      and ((tokens[-1] | lower) == 'grants') -%}

  {%- if ends_with_copy -%}
    {%- set out = s -%}
  {%- else -%}
    {%- set out = s ~ '\nCOPY GRANTS' -%}
  {%- endif -%}

  {{- out -}}
{%- endmacro %}


{% macro snowflake__create_or_replace_semantic_view() %}
  {%- set identifier = model['alias'] -%}

  {%- set copy_grants = config.get('copy_grants', default=false) -%}
  {%- set verified_queries = config.get('verified_queries', default=none) -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {%- if copy_grants -%}
    {%- set sql = dbt_semantic_view.append_copy_grants_if_missing(sql) -%}
  {%- endif -%}

  {%- if verified_queries is not none -%}
    {%- set ca_json = {'verified_queries': verified_queries} | tojson -%}
    {%- set sql = dbt_semantic_view.append_ca_extension_if_missing(sql, ca_json) -%}
  {%- endif -%}

  {{ run_hooks(pre_hooks) }}

  -- build model
  {% call statement('main') -%}
    {{ dbt_semantic_view.snowflake__get_create_semantic_view_sql(target_relation, sql) }}
  {%- endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}