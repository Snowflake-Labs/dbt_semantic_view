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
  snowflake__sync_sv_materializations

  Declaratively synchronises the materializations on a semantic view by
  calling SYSTEM$MANAGE_SEMANTIC_VIEW_MATERIALIZATIONS_FROM_YAML.  The
  stored procedure performs the full diff (add / update / drop) so no
  diff logic is needed here.

  Args:
    sv_fqn        - fully-qualified semantic view name, e.g.
                    'MY_DB.MY_SCHEMA.MY_SEMANTIC_VIEW'
    yaml_spec     - YAML string accepted by the SP (see format below)

  YAML format:
    materializations:
      - name: my_mat
        warehouse: MY_WAREHOUSE
        dimensions:
          - table: entity
            name: dim_col
        metrics:
          - table: entity
            name: metric_col
        filter_clause: "WHERE (entity.date_col >= '2024-01-01')"  # optional: mutable filter;
                                                                  #   planner rewrites queries whose
                                                                  #   filter matches or is stricter
        immutable_where: "date_col < '2024-01-01'"                # optional: freeze historical rows;
                                                                  #   mutually exclusive with filter_clause
                                                                  #   and date_col must be a materialized
                                                                  #   dimension
        refresh_mode: AUTO                            # optional: AUTO (default) | INCREMENTAL | FULL
                                                      # NOTE: silently ignored by the SP — refresh_mode
                                                      # is a DDL-only parameter; Snowflake always uses AUTO
#}
{% macro snowflake__sync_sv_materializations(sv_fqn, yaml_spec) %}
  {% call statement('sync_sv_materializations', fetch_result=False) -%}
    call system$manage_semantic_view_materializations_from_yaml(
      '{{ sv_fqn }}',
      $$
{{ yaml_spec }}
      $$
    )
  {%- endcall %}
{% endmacro %}
