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

-- Exercises the YAML-only features (time_dimensions, filters, data_type)
-- through the inline ca_yaml_features() macro form.
{{ config(materialized='semantic_view') }}

TABLES(t1 AS {{ ref('base_table') }})
DIMENSIONS(t1.status AS value)
METRICS(t1.total_rows AS SUM(t1.value))
{{ dbt_semantic_view.ca_yaml_features(
    time_dimensions=[{'table': 't1', 'name': 'created_at', 'expr': 'value', 'data_type': 'NUMBER'}],
    filters=[{'table': 't1', 'name': 'recent', 'expr': 'value > 100'}],
    dimensions=[{'table': 't1', 'name': 'amount', 'expr': 'value', 'data_type': 'NUMBER(38,2)'}]
) }}
