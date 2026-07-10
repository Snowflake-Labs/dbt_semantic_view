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
  Use a set block to build the YAML when you need Jinja expressions inside it
  (e.g. injecting the warehouse from the dbt profile or an env_var).
  For static YAML with no Jinja, you can pass the string directly in config().
#}
{%- set sv_mats_yaml -%}
materializations:
  - name: test_mat_by_value
    warehouse: {{ target.warehouse }}
    dimensions:
      - table: t1
        name: value
    metrics:
      - table: t1
        name: total_rows
  - name: test_mat_filtered_by_value
    warehouse: {{ target.warehouse }}
    dimensions:
      - table: t1
        name: value
    metrics:
      - table: t1
        name: total_rows
    filter_clause: "WHERE (t1.count >= 1)"
  - name: test_mat_immutable_by_value
    warehouse: {{ target.warehouse }}
    dimensions:
      - table: t1
        name: value
    metrics:
      - table: t1
        name: total_rows
    immutable_where: "value < 10"
{%- endset -%}

{{
    config(
        materialized='semantic_view',
        create_or_alter=true,
        sv_materializations=sv_mats_yaml
    )
}}

TABLES(t1 AS {{ ref('base_table') }})
DIMENSIONS(t1.count as value)
METRICS(t1.total_rows AS SUM(t1.count))
MAX_STALENESS = '1 hour'
COMMENT='semantic view with materialization for integration test'
