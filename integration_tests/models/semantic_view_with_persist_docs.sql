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

{{ config(
    materialized='semantic_view',
    persist_docs={'relation': true}
) }}

TABLES(t1 AS {{ ref('base_table') }}, t2 as {{ source('seed_sources', 'base_table2') }})
DIMENSIONS(t1.count as value, t2.volume as value)
METRICS(t1.total_rows AS SUM(t1.count), t2.max_volume as max(t2.volume))