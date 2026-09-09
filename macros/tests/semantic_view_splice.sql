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

{# Inline semantic views that opt in with an sv_def__<model_name> macro. #}
{% macro sv_aware_ref(ref_args, ref_kwargs) %}
  {% set target_name = ref_args[-1] if ref_args | length > 0 else none %}
  {% set definition_name = 'sv_def__' ~ target_name if target_name is not none else none %}
  {% set definition_macro = context.get(definition_name) if definition_name is not none else none %}

  {% if model.resource_type == 'unit_test' and definition_macro is not none %}
    {% set dependency_ids = model.depends_on.nodes if model.depends_on is defined else [] %}
    {% for dependency_id in dependency_ids %}
      {% if dependency_id.split('.')[-1] == target_name %}
        {{ exceptions.raise_compiler_error(
          "Unit test '" ~ model.name ~ "' cannot use given: ref('" ~ target_name ~ "') "
          ~ "because '" ~ target_name ~ "' is a semantic view. Fixture the ref()/source() "
          ~ "relations used in its TABLES clause instead."
        ) }}
      {% endif %}
    {% endfor %}

    {# Render once so dbt registers the definition's fixture dependencies. #}
    {% do definition_macro() %}
    {{ return(
      adapter.quote(target_name)
      ~ '/*__DBT_SEMANTIC_VIEW_DEF__:' ~ target_name ~ '*/'
    ) }}
  {% endif %}

  {{ return(builtins.ref(*ref_args, **ref_kwargs)) }}
{% endmacro %}


{# Preserve dependency tracking and remap sources when the definition is rendered during a unit test. #}
{% macro sv_aware_source(source_name, table_name) %}
  {% set resolved = builtins.source(source_name, table_name) %}
  {% if model.resource_type == 'unit_test' %}
    {{ return(api.Relation.add_ephemeral_prefix(source_name ~ '__' ~ table_name)) }}
  {% endif %}
  {{ return(resolved) }}
{% endmacro %}


{# Rebuilds the WITH clause ourselves, since dbt core has no native concept of an ad-hoc
   semantic view CTE. Errors out if the model already opens with its own WITH clause. #}
{% macro _semantic_view_structured_splice_sql(compiled_sql, extra_ctes) %}
  {% set marker_prefix = '/*__DBT_SEMANTIC_VIEW_DEF__:' %}
  {% set marker_suffix = '*/' %}

  {% set leaf_cte_texts = extra_ctes | map(attribute='sql') | list %}

  {% if leaf_cte_texts | length == 0 %}
    {% set original_select = compiled_sql %}
  {% else %}
    {% set expected_prefix = 'with' ~ (leaf_cte_texts | join(', ')) ~ ' ' %}
    {% if not compiled_sql.startswith(expected_prefix) %}
      {{ exceptions.raise_compiler_error(
        "Semantic view unit tests (structured splice) only support models "
        ~ "that don't already open with their own WITH clause; dbt merges "
        ~ "fixture CTEs into an existing WITH instead of prepending one, "
        ~ "and this macro doesn't parse that merged form."
      ) }}
    {% endif %}
    {% set original_select = compiled_sql[(expected_prefix | length):] %}
  {% endif %}

  {% if marker_prefix not in original_select %}
    {{ return(compiled_sql) }}
  {% endif %}

  {# The marker is a fixed delimiter, never user input, so a plain split is enough. #}
  {% set ns = namespace(ctes=[], seen=[]) %}
  {% for chunk in original_select.split(marker_prefix)[1:] %}
    {% set semantic_view_name = chunk.split(marker_suffix, 1)[0] %}
    {% if semantic_view_name not in ns.seen %}
      {% set definition_name = 'sv_def__' ~ semantic_view_name %}
      {% set definition_macro = context.get(definition_name) %}
      {% if definition_macro is none %}
        {{ exceptions.raise_compiler_error(
          "Could not find semantic view definition macro '" ~ definition_name ~ "'."
        ) }}
      {% endif %}
      {% do ns.ctes.append(
        adapter.quote(semantic_view_name)
        ~ ' AS SEMANTIC VIEW\n'
        ~ (definition_macro() | trim)
      ) %}
      {% do ns.seen.append(semantic_view_name) %}
    {% endif %}
  {% endfor %}

  {% set all_ctes = leaf_cte_texts + ns.ctes %}

  {{ return(
    'with ' ~ (all_ctes | join(',\n')) ~ '\n' ~ original_select
  ) }}
{% endmacro %}


{# Splices in the semantic view CTE before dbt's schema-introspection CTAS, which otherwise
   runs before the CTE exists. #}
{% macro snowflake__get_empty_subquery_sql(select_sql, select_sql_header=none) %}
  {% set spliced_sql = dbt_semantic_view._semantic_view_structured_splice_sql(select_sql, model.extra_ctes) %}
  {{ return(dbt.default__get_empty_subquery_sql(spliced_sql, select_sql_header)) }}
{% endmacro %}


{# Splices in the semantic view CTE before building the actual/expected comparison SQL. #}
{% macro snowflake__get_unit_test_sql(main_sql, expected_fixture_sql, expected_column_names) %}
  {% set spliced_sql = dbt_semantic_view._semantic_view_structured_splice_sql(main_sql, model.extra_ctes) %}
  {{ return(dbt.default__get_unit_test_sql(
    spliced_sql,
    expected_fixture_sql,
    expected_column_names
  )) }}
{% endmacro %}
