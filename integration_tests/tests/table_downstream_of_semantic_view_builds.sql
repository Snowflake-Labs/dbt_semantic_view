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

{{ config(materialized='test') }}

-- Assert that downstream models can successfully reference semantic views
-- This validates that dbt lineage tracking works despite empty column introspection
select 'downstream table referencing semantic view is empty or failed to build' as error_message
where (select count(*) from {{ ref('table_downstream_of_semantic_view') }}) = 0

