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

{% macro get_column_comment(model_name, column_name) %}
  {#-
  -- Get the description from schema.yml for a specific column
  -- This is useful for adding comments to semantic view dimensions/facts/metrics
  --
  -- Args:
  --   model_name: The name of the model in schema.yml
  --   column_name: The name of the column to get the description for
  --
  -- Returns:
  --   A COMMENT clause if description exists, empty string otherwise
  --
  -- Example usage in semantic view:
  --   DIMENSIONS (
  --     JOIN.ORDER_ID AS order_id {{ get_column_comment('sample_join', 'order_id') }}
  --   )
  -#}
  
  {%- set model = none -%}
  
  {#- Search for the model in graph.nodes -#}
  {%- for node in graph.nodes.values() -%}
    {%- if node.name == model_name -%}
      {%- set model = node -%}
      {%- break -%}
    {%- endif -%}
  {%- endfor -%}
  
  {#- Check if model and column exist, then return the comment -#}
  {%- if model and model.columns and column_name in model.columns -%}
    {%- set column = model.columns[column_name] -%}
    {%- if column.description -%}
      {{- " COMMENT='" ~ column.description.replace("'", "''") ~ "'" -}}
    {%- endif -%}
  {%- endif -%}
{%- endmacro %}

{% macro get_model_comment(model_name) %}
  {#-
  -- Get the description from schema.yml for a specific model
  -- This is useful for adding comments to semantic views
  --
  -- Args:
  --   model_name: The name of the model in schema.yml
  --
  -- Returns:
  --   The description if it exists, empty string otherwise
  --
  -- Example usage in semantic view:
  --   COMMENT = '{{ get_model_comment("sample_join") }}'
  -#}
  
  {%- set model = none -%}
  
  {#- Search for the model in graph.nodes -#}
  {%- for node in graph.nodes.values() -%}
    {%- if node.name == model_name -%}
      {%- set model = node -%}
      {%- break -%}
    {%- endif -%}
  {%- endfor -%}
  
  {#- Return the model description if it exists -#}
  {%- if model and model.description -%}
    {{- model.description.replace("'", "''") -}}
  {%- endif -%}
{%- endmacro %}