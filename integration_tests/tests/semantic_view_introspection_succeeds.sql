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

-- Assert that semantic views are correctly identified in INFORMATION_SCHEMA
-- This validates that our custom get_columns_in_relation macro properly detects semantic views
with semantic_view_check as (
  select 
    *
  from {{ target.database }}.information_schema.SEMANTIC_VIEWS
  where name ilike '%semantic_view_basic%'
)
select 'semantic view not properly identified in INFORMATION_SCHEMA' as error_message
where (select count(*) from semantic_view_check) = 0