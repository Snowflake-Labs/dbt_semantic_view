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

-- Assert the generated CA extension (time_dimensions / filters / data_type) is
-- present on both the inline-macro and config-driven semantic views, via GET_DDL.
with checks as (
  select 'inline' as source, lower(get_ddl('SEMANTIC_VIEW', '{{ ref('semantic_view_with_yaml_features') }}')) as ddl
  union all
  select 'config' as source, lower(get_ddl('SEMANTIC_VIEW', '{{ ref('semantic_view_with_yaml_features_config') }}')) as ddl
)
select 'CA yaml-only features missing for ' || source as error_message
from checks
where not (
  position('ca' in ddl) > 0
  and position('"time_dimensions"' in ddl) > 0
  and position('"created_at"' in ddl) > 0
  and position('"filters"' in ddl) > 0
  and position('"recent"' in ddl) > 0
  and position('number(38,2)' in ddl) > 0
)
