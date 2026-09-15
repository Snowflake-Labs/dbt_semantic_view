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

{% materialization semantic_view, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}
    {% do dbt_semantic_view.snowflake__create_or_replace_semantic_view() %}

    {% set target_relation = this.incorporate(type='view') %}

    {% do unset_query_tag(original_query_tag) %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}