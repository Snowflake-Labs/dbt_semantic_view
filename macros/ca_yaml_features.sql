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

{% macro ca_yaml_features(time_dimensions=[], filters=[], dimensions=[]) -%}
{#-
--  Build a `WITH EXTENSION (CA=$$...$$)` clause carrying the semantic-view
--  features that are expressible in the Cortex Analyst YAML spec but not in
--  plain CREATE SEMANTIC VIEW DDL:
--    - time_dimensions : a distinct category for date/timestamp columns
--    - filters         : standalone, named table-level filter expressions
--    - data_type       : explicit column data-type declarations
--  (see https://docs.snowflake.com/en/user-guide/views-semantic/yaml-vs-ddl)
--
--  Each entry is a dict routed by its `table` key. Entries are grouped by table
--  into the CA extension's per-table structure, and only keys that carry a value
--  are emitted, so the macro is safe to always call.
--
--  Args:
--  - time_dimensions: list[dict] - {table, name, expr, data_type?, synonyms?,
--        sample_values?, description?}
--  - filters: list[dict] - {table, name, expr, description?, synonyms?}
--  - dimensions: list[dict] - regular dimensions used to declare an explicit
--        data_type: {table, name, expr?, data_type, synonyms?, description?}
--  Returns:
--      A `WITH EXTENSION (CA=$$ {json} $$)` string, or '' when no inputs given.
-#}
  {%- if not (time_dimensions or filters or dimensions) -%}
    {{- return('') -}}
  {%- endif -%}

  {%- set groups = [
      ('time_dimensions', time_dimensions, ['name', 'expr', 'data_type', 'synonyms', 'sample_values', 'description']),
      ('dimensions', dimensions, ['name', 'expr', 'data_type', 'synonyms', 'sample_values', 'description']),
      ('filters', filters, ['name', 'expr', 'description', 'synonyms'])
  ] -%}

  {#- Ordered set of table names referenced by any entry. -#}
  {%- set table_names = [] -%}
  {%- for section, entries, allowed in groups -%}
    {%- for entry in entries -%}
      {%- set tname = entry.get('table') -%}
      {%- if not tname -%}
        {{ exceptions.raise_compiler_error("ca_yaml_features: every entry must set a 'table' key. Offending entry: " ~ entry) }}
      {%- endif -%}
      {%- if tname not in table_names -%}
        {%- do table_names.append(tname) -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endfor -%}

  {%- set tables = [] -%}
  {%- for tname in table_names -%}
    {%- set table = {'name': tname} -%}
    {%- for section, entries, allowed in groups -%}
      {%- set cleaned = [] -%}
      {%- for entry in entries if entry.get('table') == tname -%}
        {%- set clean = {} -%}
        {%- for key in allowed -%}
          {%- set value = entry.get(key) -%}
          {%- if value is not none and value != '' and value != [] -%}
            {%- do clean.update({key: value}) -%}
          {%- endif -%}
        {%- endfor -%}
        {%- do cleaned.append(clean) -%}
      {%- endfor -%}
      {%- if cleaned | length > 0 -%}
        {%- do table.update({section: cleaned}) -%}
      {%- endif -%}
    {%- endfor -%}
    {%- do tables.append(table) -%}
  {%- endfor -%}

  {{- return('WITH EXTENSION (CA=$$' ~ ({'tables': tables} | tojson) ~ '$$)') -}}
{%- endmacro %}
