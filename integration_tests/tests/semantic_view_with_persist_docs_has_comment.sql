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

-- Test that persist_docs adds the model description as a COMMENT
select 'persist_docs comment missing' as error_message
where position('comment=' in lower(get_ddl('SEMANTIC_VIEW', '{{ ref('semantic_view_with_persist_docs') }}'))) = 0
   or position('this semantic view tests persist_docs functionality' in lower(get_ddl('SEMANTIC_VIEW', '{{ ref('semantic_view_with_persist_docs') }}'))) = 0