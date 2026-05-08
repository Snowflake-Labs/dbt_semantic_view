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


{% macro append_comment_if_missing(sql, comment) -%}
  {%- if not comment -%}
    {{ sql }}
  {%- else -%}
    {%- set s = (sql | trim) -%}
    {%- set had_semicolon = (s[-1:] == ';') -%}
    {%- if had_semicolon -%}
      {%- set s = (s[:-1] | trim) -%}
    {%- endif -%}

    {# detect existing COMMENT at the end, case-insensitive #}
    {%- set has_comment = 'comment=' in (s | lower) -%}

    {%- if has_comment -%}
      {%- set out = s -%}
    {%- else -%}
      {%- set out = s ~ "\nCOMMENT='" ~ comment ~ "'" -%}
    {%- endif -%}

    {{- out -}}
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
  {%- set persist_docs = config.get('persist_docs', {}) -%}
  {%- set relation_comment = none -%}
  
  {%- if persist_docs.get('relation', false) and model.description -%}
    {%- set relation_comment = model.description -%}
  {%- endif -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {%- if relation_comment -%}
    {%- set sql = dbt_semantic_view.append_comment_if_missing(sql, relation_comment) -%}
  {%- endif -%}
  
  {%- if copy_grants -%}
    {%- set sql = dbt_semantic_view.append_copy_grants_if_missing(sql) -%}
  {%- endif -%}

  {{ run_hooks(pre_hooks) }}

  -- build model
  {% call statement('main') -%}
    {{ dbt_semantic_view.snowflake__get_create_semantic_view_sql(target_relation, sql) }}
  {%- endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}