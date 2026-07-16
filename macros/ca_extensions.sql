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
  ca_extensions — generate the WITH EXTENSION (CA=$$...$$) block for Cortex Analyst.

  Parameters
  ----------
  verified_queries : list of dicts
      Each dict must have:
        - name            (str)  short label shown in the UI
        - question        (str)  natural-language question this SQL answers
        - sql             (str)  verified SQL (use table aliases, not fully-qualified names)
      Optional keys:
        - verified_at     (int)  Unix timestamp of verification
        - verified_by     (str)  name of the person who verified
        - use_as_onboarding_question (bool)  surface in the onboarding flow

  relationships : list of dicts
      Cortex Analyst relationship definitions (see Snowflake docs).

  custom_instructions : str
      Free-text instructions appended to every Cortex Analyst prompt for this view.

  tables : list of dicts
      Per-table Cortex Analyst metadata (filters, synonyms, etc.).

  Usage
  -----
  {{ config(materialized='semantic_view') }}
  TABLES(t1 AS {{ ref('orders') }})
  DIMENSIONS(t1.status AS status)
  METRICS(t1.order_count AS COUNT(*))
  {{ dbt_semantic_view.ca_extensions(
      verified_queries=[
          {
              "name": "total orders last 30 days",
              "question": "How many orders were placed in the last 30 days?",
              "sql": "SELECT COUNT(*) AS order_count FROM t1 WHERE order_date >= CURRENT_DATE - 30",
              "verified_at": 1733356800,
              "verified_by": "Jane Smith",
              "use_as_onboarding_question": true
          }
      ],
      custom_instructions="Always filter to completed orders unless the user specifies otherwise."
  ) }}
#}

{% macro ca_extensions(relationships=[], verified_queries=[], custom_instructions='', tables=[]) %}

{%- set ca_items = [] -%}
  {%- if tables -%}
      {%- do ca_items.append('"tables": ' ~ (tables | tojson)) -%}
  {%- endif -%}
  {%- if relationships -%}
      {%- do ca_items.append('"relationships": ' ~ (relationships | tojson)) -%}
  {%- endif -%}
  {%- if verified_queries -%}
      {%- do ca_items.append('"verified_queries": ' ~ (verified_queries | tojson)) -%}
  {%- endif -%}
  {%- if custom_instructions -%}
      {%- do ca_items.append('"custom_instructions": ' ~ (custom_instructions | tojson)) -%}
  {%- endif -%}

    {% if ca_items -%}
    with extension (CA=$$
{
  {{ ca_items | join(',\n  ') | indent(2, true) }}
}
$$)
    {%- endif %}
{% endmacro %}
