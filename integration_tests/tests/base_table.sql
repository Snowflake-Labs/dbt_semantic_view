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

{{ config(materialized='test', enabled=not flags.EMPTY) }}

-- Passes when the seed has rows; fails if empty
-- Skipped with --empty because the flag rewrites ref() to return 0 rows by design
select 'my_seed is empty' as error_message
where not exists (
  select 1 from {{ ref('my_seed') }}
)