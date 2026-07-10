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

{% macro snowflake__get_create_semantic_view_sql(relation, sql) -%}
{#-
--  Produce DDL that creates a semantic view
--
--  Args:
--  - relation: Union[SnowflakeRelation, str]
--      - SnowflakeRelation - required for relation.render()
--      - str - is already the rendered relation name
--  - sql: str - the code defining the model
--  Returns:
--      A valid DDL statement which will result in a new semantic view.
-#}

  create or replace semantic view {{ relation }}
  {{ sql }}

{%- endmacro %}


{% macro snowflake__get_create_or_alter_semantic_view_sql(relation, sql) -%}
{#-
--  Produce DDL that creates or alters a semantic view (non-destructive).
--  Unlike CREATE OR REPLACE, CREATE OR ALTER preserves existing materializations
--  and grants when only the SV body changes.
--
--  Args:
--  - relation: Union[SnowflakeRelation, str]
--  - sql: str - the code defining the model
--  Returns:
--      A valid DDL statement using CREATE OR ALTER semantics.
-#}

  create or alter semantic view {{ relation }}
  {{ sql }}

{%- endmacro %}


{% macro append_copy_grants_if_missing(sql) -%}
  {%- set s = (sql | trim) -%}
  {%- set had_semicolon = (s[-1:] == ';') -%}
  {%- if had_semicolon -%}
    {%- set s = (s[:-1] | trim) -%}
  {%- endif -%}

  {# detect existing COPY GRANTS at the end, case/whitespace-insensitive #}
  {%- set tokens = s.split() -%}
  {%- set ends_with_copy = (tokens | length >= 2)
      and ((tokens[-2] | lower) == 'copy')
      and ((tokens[-1] | lower) == 'grants') -%}

  {%- if ends_with_copy -%}
    {%- set out = s -%}
  {%- else -%}
    {%- set out = s ~ '\nCOPY GRANTS' -%}
  {%- endif -%}

  {{- out -}}
{%- endmacro %}


{#-
  append_comment_if_missing: idempotently appends
    COMMENT = $$<comment_text>$$
  to a CREATE OR REPLACE SEMANTIC VIEW statement.

  - If the statement already has a top-level COMMENT = ... clause, returns
    the input unchanged — inline SQL wins.
  - If the statement ends with COPY GRANTS, inserts the COMMENT clause
    BEFORE it so COPY GRANTS remains the final clause (Snowflake grammar).
  - Detects an existing COMMENT clause by scanning all occurrences of 'comment'
    at top-level (paren depth 0). Works correctly even when AI_VERIFIED_QUERIES(...)
    or other parenthesized clauses appear after COMMENT.
  - Known limitation: if a string literal inside a clause body ($$...$$) contains
    unbalanced parentheses (e.g., $$func(arg$$), the paren-balance depth check may
    misclassify a COMMENT inside the body as top-level. This edge case is extremely
    unlikely in Snowflake semantic view DDL.
  - Known limitation: if a relation-level COMMENT is inserted BEFORE AI_VERIFIED_QUERIES,
    the new COMMENT clause will still be appended at the end of body (after
    AI_VERIFIED_QUERIES), violating clause order. This only matters when the model
    already has no COMMENT and also uses AI_VERIFIED_QUERIES — a rare combination.
    Acceptable for current use. Fix: detect AI clause positions and insert before them.
  - $ in comment_text is escaped to [$] (Snowflake convention) so the
    description can never close the enclosing $$...$$ block.
-#}
{% macro append_comment_if_missing(sql, comment_text) -%}
  {%- set s = (sql | trim) -%}
  {%- if s[-1:] == ';' -%}{%- set s = (s[:-1] | trim) -%}{%- endif -%}

  {%- set tokens = s.split() -%}
  {%- set ends_with_copy = (tokens | length >= 2)
      and ((tokens[-2] | lower) == 'copy')
      and ((tokens[-1] | lower) == 'grants') -%}

  {%- if ends_with_copy -%}
    {%- set lower_s = s | lower -%}
    {%- set cg_idx = lower_s.rfind('copy grants') -%}
    {%- set body = (s[:cg_idx] | trim) -%}
    {%- set tail = s[cg_idx:] -%}
  {%- else -%}
    {%- set body = s -%}
    {%- set tail = '' -%}
  {%- endif -%}

  {#- Detect existing top-level COMMENT using split + paren-balance.
      Splits body on 'comment', then for each occurrence checks:
        (a) the occurrence is followed by \s*= (it's a COMMENT = clause, not just the word)
        (b) paren count before that position is balanced (it's at depth 0, not inside a body)
      Uses str.split() + str.count() — O(n) Python ops, NOT subject to Jinja's MAX_RANGE
      sandbox limit. Correctly handles:
        - AI_VERIFIED_QUERIES(...) and other post-COMMENT parenthesized clauses (C1)
        - bodies with no parentheses at all (C2)
        - per-column COMMENTs inside clause bodies (they are at depth > 0 so ignored)
  -#}
  {%- set lower_body = body | lower -%}
  {%- set ns = namespace(has_comment=false) -%}
  {%- if 'comment' in lower_body -%}
    {%- set comment_parts = lower_body.split('comment') -%}
    {%- set pos = namespace(val=0) -%}
    {%- for part in comment_parts[:-1] -%}
      {%- if not ns.has_comment -%}
        {%- set at_comment = pos.val + (part | length) -%}
        {%- if modules.re.match('comment\\s*=', lower_body[at_comment:]) -%}
          {%- if body[:at_comment].count('(') == body[:at_comment].count(')') -%}
            {%- set ns.has_comment = true -%}
          {%- endif -%}
        {%- endif -%}
        {%- set pos.val = at_comment + 7 -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}

  {%- set escaped = comment_text | replace('$', '[$]') -%}
  {%- if ns.has_comment -%}
    {{- sql -}}
  {%- elif ends_with_copy -%}
    {{- body ~ '\nCOMMENT = $$' ~ escaped ~ '$$\n' ~ tail -}}
  {%- else -%}
    {{- body ~ '\nCOMMENT = $$' ~ escaped ~ '$$' -}}
  {%- endif -%}
{%- endmacro %}


{% macro snowflake__create_or_replace_semantic_view() %}
  {%- set identifier = model['alias'] -%}

  {%- set copy_grants         = config.get('copy_grants',         default=false) -%}
  {%- set create_or_alter     = config.get('create_or_alter',     default=false) -%}
  {%- set sv_materializations = config.get('sv_materializations', default=none)  -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {%- if config.persist_column_docs() -%}
    {%- set sql = dbt_semantic_view.append_column_comments_if_missing(sql) -%}
  {%- endif -%}

  {%- if copy_grants and not create_or_alter -%}
    {%- set sql = dbt_semantic_view.append_copy_grants_if_missing(sql) -%}
  {%- endif -%}

  {%- if config.persist_relation_docs() and model.description -%}
    {%- set sql = dbt_semantic_view.append_comment_if_missing(sql, model.description) -%}
  {%- endif -%}

  {{ run_hooks(pre_hooks) }}

  -- build model
  {% call statement('main') -%}
    {%- if create_or_alter -%}
      {{ dbt_semantic_view.snowflake__get_create_or_alter_semantic_view_sql(target_relation, sql) }}
    {%- else -%}
      {{ dbt_semantic_view.snowflake__get_create_semantic_view_sql(target_relation, sql) }}
    {%- endif -%}
  {%- endcall %}

  {%- if sv_materializations is not none -%}
    {%- set sv_fqn = target_relation.render() | replace("'", "''") -%}
    {{ dbt_semantic_view.snowflake__sync_sv_materializations(sv_fqn, sv_materializations) }}
  {%- endif -%}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}