{#-
  append_column_comments_if_missing(sql)

  Post-processor that auto-injects COMMENT = $$…$$ into semantic view bodies
  when config.persist_docs.columns is true. Users write plain Snowflake
  semantic-view SQL; this macro scans each DIMENSIONS/METRICS/FACTS entry and,
  when the RHS of AS is a single column reference (either a bare identifier
  like `value` or a qualified form like `t1.value`) and the LHS is
  alias-qualified, looks up the column description from schema.yml/source.yml
  and appends the COMMENT clause. The column name used for the lookup is the
  trailing identifier on the RHS; any qualifying prefix is ignored. Entries
  that already have an inline COMMENT = … are left untouched (inline wins).
  Computed expressions (aggregates, arithmetic, function calls, etc.) stay
  passthrough — there is no single column to look up.

  Limitations:
  - SQL comments inside the semantic view body (-- or /* */) are not handled as
    opaque regions. A single quote inside a SQL comment (e.g., -- it's a note)
    will be treated as the start of a string literal, potentially causing
    _sv_find_clause to skip over the actual clause. Column comments for the
    affected clause will be silently skipped. Workaround: avoid -- and /* */
    comments inside semantic view model SQL bodies.
  - RELATIONSHIPS entries are not processed.
  - Model-local columns: in the semantic view's own schema.yml are not used as
    an override source.
  - Cross-table qualified RHS (e.g. `t1.my_dim AS t2.col`) resolves the source
    table from the LHS alias, not the RHS prefix. If `col` only lives in t2's
    table, the lookup silently misses. Acceptable because this form is unusual
    and the regular `t1.my_dim AS t1.col` / `t1.my_dim AS col` cases work.
-#}
{% macro append_column_comments_if_missing(sql) -%}
  {%- if not config.persist_column_docs() -%}
    {{- sql -}}
  {%- else -%}
    {%- set tables_clause = dbt_semantic_view._sv_find_clause(sql, 'TABLES') -%}
    {%- if not tables_clause.found -%}
      {{- sql -}}
    {%- else -%}
      {%- set tables_body = sql[tables_clause.open_idx + 1 : tables_clause.close_idx] -%}
      {%- set tables_map = dbt_semantic_view._sv_parse_tables(tables_body) -%}
      {%- if not tables_map -%}
        {{- sql -}}
      {%- else -%}
        {%- set ns = namespace(out=sql) -%}
        {%- for keyword in ['DIMENSIONS', 'METRICS', 'FACTS'] -%}
          {%- set clause = dbt_semantic_view._sv_find_clause(ns.out, keyword) -%}
          {%- if clause.found -%}
            {%- set body = ns.out[clause.open_idx + 1 : clause.close_idx] -%}
            {%- set entries = dbt_semantic_view._sv_split_depth0(body) -%}
            {%- set new_entries = [] -%}
            {%- for entry in entries -%}
              {%- set trimmed = entry | trim -%}
              {%- if dbt_semantic_view._sv_entry_has_comment(trimmed) -%}
                {%- do new_entries.append(trimmed) -%}
              {%- else -%}
                {%- set split = dbt_semantic_view._sv_split_as(trimmed) -%}
                {%- if split is none -%}
                  {%- do new_entries.append(trimmed) -%}
                {%- else -%}
                  {#-
                    Accept either a bare identifier (`value`) or a two-segment
                    qualified column reference (`t1.value`). The optional prefix
                    is non-capturing so group(1) is always the trailing column
                    name — the key used for the description lookup.
                  -#}
                  {%- set rhs_match = modules.re.match('^(?:[A-Za-z_][A-Za-z0-9_]*\\.)?([A-Za-z_][A-Za-z0-9_]*)$', split.rhs | trim) -%}
                  {%- if not rhs_match -%}
                    {%- do new_entries.append(trimmed) -%}
                  {%- else -%}
                    {%- set alias_match = modules.re.match('^\\s*([A-Za-z_][A-Za-z0-9_]*)\\.', split.lhs) -%}
                    {%- if not alias_match -%}
                      {%- do new_entries.append(trimmed) -%}
                    {%- else -%}
                      {%- set tuple3 = tables_map.get(alias_match.group(1) | lower) -%}
                      {%- if tuple3 is none -%}
                        {%- do new_entries.append(trimmed) -%}
                      {%- else -%}
                        {%- set desc = dbt_semantic_view._sv_find_column_description(tuple3, rhs_match.group(1)) -%}
                        {%- if not desc or desc | trim | length == 0 -%}
                          {%- do new_entries.append(trimmed) -%}
                        {%- else -%}
                          {%- set escaped = desc | replace('$', '[$]') -%}
                          {%- do new_entries.append(trimmed ~ ' COMMENT = $$' ~ escaped ~ '$$') -%}
                        {%- endif -%}
                      {%- endif -%}
                    {%- endif -%}
                  {%- endif -%}
                {%- endif -%}
              {%- endif -%}
            {%- endfor -%}
            {%- set new_body = new_entries | join(',\n  ') -%}
            {%- set ns.out = ns.out[:clause.open_idx + 1] ~ new_body ~ ns.out[clause.close_idx:] -%}
          {%- endif -%}
        {%- endfor -%}
        {{- ns.out -}}
      {%- endif -%}
    {%- endif -%}
  {%- endif -%}
{%- endmacro %}


{#-
  _sv_find_clause(sql, keyword)

  Character-by-character walk with opaque regions for '...' and $$...$$
  and paren depth tracking. At paren depth 0, looks for `keyword` with
  word-boundary checks on both sides. After the keyword match, skips
  whitespace and expects an opening `(`, then walks to the matching `)`.

  Uses direct string iteration (for ch in sql) instead of range(n) to
  avoid Jinja's MAX_RANGE sandbox limit on large compiled SQL bodies.
  String literal boundaries are found via regex rather than nested loops.

  Returns a dict: {found, open_idx, close_idx}
    - found: bool
    - open_idx: index of the `(` after keyword (or -1)
    - close_idx: index of the matching `)` (or -1)
-#}
{% macro _sv_find_clause(sql, keyword) -%}
  {%- set kw_lower = keyword | lower -%}
  {%- set kw_len = keyword | length -%}
  {%- set lower_sql = sql | lower -%}
  {%- set ns = namespace(depth=0, found=false, open_idx=-1, close_idx=-1, skip_until=0) -%}

  {%- for ch in sql -%}
    {%- set i = loop.index0 -%}
    {%- if i >= ns.skip_until and not ns.found -%}

      {%- if ch == "'" -%}
        {%- set end_q = modules.re.search("(?:[^']|'')*'", sql[i + 1:]) -%}
        {%- set ns.skip_until = (i + 1 + end_q.end()) if end_q else (sql | length) -%}

      {%- elif ch == '$' and sql[i + 1:i + 2] == '$' -%}
        {%- set end_dq = sql.find('$$', i + 2) -%}
        {%- set ns.skip_until = (end_dq + 2) if end_dq != -1 else (sql | length) -%}

      {%- elif ch == '(' -%}
        {%- set ns.depth = ns.depth + 1 -%}

      {%- elif ch == ')' -%}
        {%- set ns.depth = ns.depth - 1 -%}

      {%- elif ns.depth == 0 and lower_sql[i:i + kw_len] == kw_lower -%}
        {%- set prev_char = sql[i - 1:i] -%}
        {%- set prev_ok = prev_char == '' or not (prev_char.isalnum() or prev_char == '_') -%}
        {%- set after_pos = i + kw_len -%}
        {%- set next_char = sql[after_pos:after_pos + 1] -%}
        {%- set next_ok = next_char == '' or not (next_char.isalnum() or next_char == '_') -%}
        {%- if prev_ok and next_ok -%}
          {%- set ws_match = modules.re.match('[\\s]*\\(', sql[after_pos:]) -%}
          {%- if ws_match -%}
            {%- set open_idx = after_pos + (ws_match.group(0) | length) - 1 -%}
            {%- set ns.open_idx = open_idx -%}
            {%- set inner = namespace(depth=1, skip_until=0) -%}
            {%- for ic in sql[open_idx + 1:] -%}
              {%- set j = open_idx + 1 + loop.index0 -%}
              {%- if j >= inner.skip_until and inner.depth > 0 -%}
                {%- if ic == "'" -%}
                  {%- set end_q = modules.re.search("(?:[^']|'')*'", sql[j + 1:]) -%}
                  {%- set inner.skip_until = (j + 1 + end_q.end()) if end_q else (sql | length) -%}
                {%- elif ic == '$' and sql[j + 1:j + 2] == '$' -%}
                  {%- set end_dq = sql.find('$$', j + 2) -%}
                  {%- set inner.skip_until = (end_dq + 2) if end_dq != -1 else (sql | length) -%}
                {%- elif ic == '(' -%}
                  {%- set inner.depth = inner.depth + 1 -%}
                {%- elif ic == ')' -%}
                  {%- set inner.depth = inner.depth - 1 -%}
                  {%- if inner.depth == 0 -%}
                    {%- set ns.close_idx = j -%}
                    {%- set ns.found = true -%}
                  {%- endif -%}
                {%- endif -%}
              {%- endif -%}
            {%- endfor -%}
            {%- if ns.found -%}
              {%- set ns.skip_until = sql | length -%}
            {%- endif -%}
          {%- endif -%}
        {%- endif -%}

      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}

  {%- do return({'found': ns.found, 'open_idx': ns.open_idx, 'close_idx': ns.close_idx}) -%}
{%- endmacro %}


{#-
  _sv_split_depth0(body)

  Splits `body` on commas at paren depth 0, outside '...' and $$...$$
  regions. Returns a list of entry strings.

  Uses direct string iteration (for ch in body) instead of range(n) to
  avoid Jinja's MAX_RANGE sandbox limit on large clause bodies.
  Tracks entry start position and slices body[start:i] at each depth-0 comma.
-#}
{% macro _sv_split_depth0(body) -%}
  {%- set ns = namespace(depth=0, start=0, skip_until=0) -%}
  {%- set entries = [] -%}

  {%- for ch in body -%}
    {%- set i = loop.index0 -%}
    {%- if i >= ns.skip_until -%}
      {%- if ch == "'" -%}
        {%- set end_q = modules.re.search("(?:[^']|'')*'", body[i + 1:]) -%}
        {%- set ns.skip_until = (i + 1 + end_q.end()) if end_q else (body | length) -%}
      {%- elif ch == '$' and body[i + 1:i + 2] == '$' -%}
        {%- set end_dq = body.find('$$', i + 2) -%}
        {%- set ns.skip_until = (end_dq + 2) if end_dq != -1 else (body | length) -%}
      {%- elif ch == '(' -%}
        {%- set ns.depth = ns.depth + 1 -%}
      {%- elif ch == ')' -%}
        {%- set ns.depth = ns.depth - 1 -%}
      {%- elif ch == ',' and ns.depth == 0 -%}
        {%- do entries.append(body[ns.start:i]) -%}
        {%- set ns.start = i + 1 -%}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}

  {%- if body[ns.start:] | trim | length > 0 -%}
    {%- do entries.append(body[ns.start:]) -%}
  {%- endif -%}

  {%- do return(entries) -%}
{%- endmacro %}


{#-
  _sv_entry_has_comment(entry)

  Returns true if `entry` contains a top-level COMMENT = token (at paren
  depth 0, outside all opaque regions), with word-boundary guards on both
  sides of COMMENT.
-#}
{% macro _sv_entry_has_comment(entry) -%}
  {%- set n = entry | length -%}
  {%- set lower_entry = entry | lower -%}
  {%- set ns = namespace(i=0, depth=0, has_comment=false) -%}

  {%- if 'comment' in lower_entry -%}
    {%- for _ in range(n) -%}
      {%- if ns.i < n and not ns.has_comment -%}
        {%- set ch = entry[ns.i] -%}

        {%- if ch == "'" -%}
          {%- set ns.i = ns.i + 1 -%}
          {%- set inner = namespace(done=false) -%}
          {%- for _ in range(n - ns.i) -%}
            {%- if not inner.done and ns.i < n -%}
              {%- if entry[ns.i] == "'" -%}
                {%- if entry[ns.i + 1:ns.i + 2] == "'" -%}
                  {%- set ns.i = ns.i + 2 -%}
                {%- else -%}
                  {%- set ns.i = ns.i + 1 -%}
                  {%- set inner.done = true -%}
                {%- endif -%}
              {%- else -%}
                {%- set ns.i = ns.i + 1 -%}
              {%- endif -%}
            {%- endif -%}
          {%- endfor -%}

        {%- elif ch == '$' and entry[ns.i + 1:ns.i + 2] == '$' -%}
          {%- set ns.i = ns.i + 2 -%}
          {%- set inner = namespace(done=false) -%}
          {%- for _ in range(n - ns.i) -%}
            {%- if not inner.done and ns.i < n -%}
              {%- if entry[ns.i] == '$' and entry[ns.i + 1:ns.i + 2] == '$' -%}
                {%- set ns.i = ns.i + 2 -%}
                {%- set inner.done = true -%}
              {%- else -%}
                {%- set ns.i = ns.i + 1 -%}
              {%- endif -%}
            {%- endif -%}
          {%- endfor -%}

        {%- elif ch == '(' -%}
          {%- set ns.depth = ns.depth + 1 -%}
          {%- set ns.i = ns.i + 1 -%}

        {%- elif ch == ')' -%}
          {%- set ns.depth = ns.depth - 1 -%}
          {%- set ns.i = ns.i + 1 -%}

        {%- elif ns.depth == 0 and lower_entry[ns.i:ns.i + 7] == 'comment' -%}
          {%- set prev_char = entry[ns.i - 1:ns.i] -%}
          {%- set prev_ok = prev_char == '' or not (prev_char.isalnum() or prev_char == '_') -%}
          {%- set after_pos = ns.i + 7 -%}
          {%- set next_char = entry[after_pos:after_pos + 1] -%}
          {%- set next_ok = next_char == '' or not (next_char.isalnum() or next_char == '_') -%}
          {%- if prev_ok and next_ok -%}
            {%- set rest = entry[after_pos:] | trim -%}
            {%- if rest and rest[0] == '=' -%}
              {%- set ns.has_comment = true -%}
            {%- endif -%}
          {%- endif -%}
          {%- set ns.i = after_pos -%}

        {%- else -%}
          {%- set ns.i = ns.i + 1 -%}
        {%- endif -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}

  {%- do return(ns.has_comment) -%}
{%- endmacro %}


{#-
  _sv_split_as(entry)

  Splits on the first case-insensitive ` AS ` token at top-level (depth 0,
  outside opaque regions). Returns a dict {lhs, rhs} or none if no split found.
-#}
{% macro _sv_split_as(entry) -%}
  {%- set n = entry | length -%}
  {%- set lower_entry = entry | lower -%}
  {%- set ns = namespace(i=0, depth=0, split_pos=-1) -%}

  {%- for _ in range(n) -%}
    {%- if ns.i < n and ns.split_pos == -1 -%}
      {%- set ch = entry[ns.i] -%}

      {%- if ch == "'" -%}
        {%- set ns.i = ns.i + 1 -%}
        {%- set inner = namespace(done=false) -%}
        {%- for _ in range(n - ns.i) -%}
          {%- if not inner.done and ns.i < n -%}
            {%- if entry[ns.i] == "'" -%}
              {%- if entry[ns.i + 1:ns.i + 2] == "'" -%}
                {%- set ns.i = ns.i + 2 -%}
              {%- else -%}
                {%- set ns.i = ns.i + 1 -%}
                {%- set inner.done = true -%}
              {%- endif -%}
            {%- else -%}
              {%- set ns.i = ns.i + 1 -%}
            {%- endif -%}
          {%- endif -%}
        {%- endfor -%}

      {%- elif ch == '$' and entry[ns.i + 1:ns.i + 2] == '$' -%}
        {%- set ns.i = ns.i + 2 -%}
        {%- set inner = namespace(done=false) -%}
        {%- for _ in range(n - ns.i) -%}
          {%- if not inner.done and ns.i < n -%}
            {%- if entry[ns.i] == '$' and entry[ns.i + 1:ns.i + 2] == '$' -%}
              {%- set ns.i = ns.i + 2 -%}
              {%- set inner.done = true -%}
            {%- else -%}
              {%- set ns.i = ns.i + 1 -%}
            {%- endif -%}
          {%- endif -%}
        {%- endfor -%}

      {%- elif ch == '(' -%}
        {%- set ns.depth = ns.depth + 1 -%}
        {%- set ns.i = ns.i + 1 -%}

      {%- elif ch == ')' -%}
        {%- set ns.depth = ns.depth - 1 -%}
        {%- set ns.i = ns.i + 1 -%}

      {#-
        At depth 0 look for whitespace + AS + whitespace (case-insensitive).
        We need the character before the current position to be whitespace/boundary
        and the sequence [whitespace]AS[whitespace] starting here.
        More practically: look for ' as ' as a 4+ char sequence where:
          entry[i] is whitespace, entry[i+1:i+3] is 'as', entry[i+3] is whitespace.
      -#}
      {%- elif ns.depth == 0 and ch in [' ', '\t', '\n', '\r'] -%}
        {%- set remaining = lower_entry[ns.i:] -%}
        {%- set as_match = modules.re.match('^(\\s+)[Aa][Ss](\\s+)', remaining) -%}
        {%- if as_match -%}
          {%- set token_start = ns.i -%}
          {%- set skip = as_match.group(0) | length -%}
          {%- set ns.split_pos = token_start -%}
          {%- set ns.i = ns.i + skip -%}
        {%- else -%}
          {%- set ns.i = ns.i + 1 -%}
        {%- endif -%}

      {%- else -%}
        {%- set ns.i = ns.i + 1 -%}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}

  {%- if ns.split_pos == -1 -%}
    {%- do return(none) -%}
  {%- else -%}
    {%- set lhs = entry[:ns.split_pos] -%}
    {%- set rhs = entry[ns.i:] -%}
    {%- do return({'lhs': lhs, 'rhs': rhs}) -%}
  {%- endif -%}
{%- endmacro %}


{#-
  _sv_parse_tables(body)

  Parses the TABLES clause body into a dict of {alias_lower: (db, schema, identifier)}.
  For each entry:
    1. Splits on ' AS ' via _sv_split_as -> alias, relation_str.
    2. Parses relation_str as a dotted identifier (splits on . outside quotes).
    3. Requires exactly 3 parts -> (db, schema, identifier), all lowercased.
    4. Strips surrounding "..." from each part.
  Returns the mapping dict (may be empty if no valid entries found).
-#}
{% macro _sv_parse_tables(body) -%}
  {%- set entries = dbt_semantic_view._sv_split_depth0(body) -%}
  {%- set result = {} -%}

  {%- for entry in entries -%}
    {%- set trimmed = entry | trim -%}
    {%- set split = dbt_semantic_view._sv_split_as(trimmed) -%}
    {%- if split is not none -%}
      {%- set alias_lower = split.lhs | trim | lower -%}
      {%- set relation_str = split.rhs | trim -%}

      {#-
        Truncate at the first whitespace.
        Snowflake allows trailing per-TABLES-entry clauses after the dotted name:
        PRIMARY KEY (...), UNIQUE (...), WITH SYNONYMS (...), COMMENT = '...'.
        None of those are part of the identifier; strip them before dot-splitting.
      -#}
      {%- set tn = relation_str | length -%}
      {%- set tns = namespace(i=0, stop=-1) -%}
      {%- for _ in range(tn) -%}
        {%- if tns.i < tn and tns.stop == -1 -%}
          {%- set tc = relation_str[tns.i] -%}
          {%- if tc in [' ', '\t', '\n', '\r'] -%}
            {%- set tns.stop = tns.i -%}
          {%- else -%}
            {%- set tns.i = tns.i + 1 -%}
          {%- endif -%}
        {%- endif -%}
      {%- endfor -%}
      {%- if tns.stop != -1 -%}
        {%- set relation_str = relation_str[:tns.stop] -%}
      {%- endif -%}

      {#- Split relation_str on dots -#}
      {%- set rn = relation_str | length -%}
      {%- set rns = namespace(i=0, current='') -%}
      {%- set parts = [] -%}

      {%- for _ in range(rn) -%}
        {%- if rns.i < rn -%}
          {%- set rc = relation_str[rns.i] -%}

          {%- if rc == '.' -%}
            {%- do parts.append(rns.current) -%}
            {%- set rns.current = '' -%}
            {%- set rns.i = rns.i + 1 -%}

          {%- else -%}
            {%- set rns.current = rns.current ~ rc -%}
            {%- set rns.i = rns.i + 1 -%}
          {%- endif -%}
        {%- endif -%}
      {%- endfor -%}
      {%- if rns.current | length > 0 -%}
        {%- do parts.append(rns.current) -%}
      {%- endif -%}

      {%- if parts | length == 3 -%}
        {%- set db_raw = parts[0] | trim -%}
        {%- set schema_raw = parts[1] | trim -%}
        {%- set ident_raw = parts[2] | trim -%}

        {#- Strip surrounding double-quotes -#}
        {%- if db_raw[:1] == '"' and db_raw[-1:] == '"' -%}
          {%- set db_raw = db_raw[1:-1] | replace('""', '"') -%}
        {%- endif -%}
        {%- if schema_raw[:1] == '"' and schema_raw[-1:] == '"' -%}
          {%- set schema_raw = schema_raw[1:-1] | replace('""', '"') -%}
        {%- endif -%}
        {%- if ident_raw[:1] == '"' and ident_raw[-1:] == '"' -%}
          {%- set ident_raw = ident_raw[1:-1] | replace('""', '"') -%}
        {%- endif -%}

        {%- do result.update({alias_lower: (db_raw | lower, schema_raw | lower, ident_raw | lower)}) -%}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}

  {%- do return(result) -%}
{%- endmacro %}


{#-
  _sv_find_column_description(tuple3, column_name)

  Walks the dbt manifest to resolve a column's description. Takes a (db, schema,
  identifier) tuple (all already lowercased) instead of a Relation object.
  Matches (database, schema, physical_name) case-insensitively against
  graph.nodes and graph.sources.

  Rationale for `alias or identifier or name`: model nodes often leave
  `identifier` null when `alias` is set, so alias must be tried first.
  `name` is a final fallback for edge cases. Sources have no `.alias`
  and populate `.identifier`.

  Tiered lookup:
    Tier 1: strict (database, schema, identifier) match against graph.nodes.
    Tier 2: strict (database, schema, identifier) match against graph.sources (if Tier 1 found nothing).
    Tier 3: identifier-only match against graph.nodes (if Tier 2 found nothing). This handles cross-env
            sv_ref references where the resolved table lives in a different database than the one recorded in graph.nodes.
            Sources are excluded from this tier because source identifiers are not unique within a project (the same table name can appear
            across multiple schemas), whereas model names are unique by convention.

  Returns the raw description string (may be empty). Caller decides
  whether to emit a COMMENT clause.
-#}
{% macro _sv_find_column_description(tuple3, column_name) -%}
  {%- set target_db = tuple3[0] -%}
  {%- set target_schema = tuple3[1] -%}
  {%- set target_identifier = tuple3[2] -%}
  {%- set found = namespace(node=none) -%}

  {%- for node in graph.nodes.values() -%}
    {%- if found.node is none -%}
      {%- set physical = node.alias or node.identifier or node.name -%}
      {%- if physical
          and (node.database or '') | lower == target_db
          and (node.schema or '') | lower == target_schema
          and (physical | lower) == target_identifier -%}
        {%- set found.node = node -%}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}

  {%- if found.node is none -%}
    {%- for src in graph.sources.values() -%}
      {%- if found.node is none -%}
        {%- set physical = src.identifier or src.name -%}
        {%- if physical
            and (src.database or '') | lower == target_db
            and (src.schema or '') | lower == target_schema
            and (physical | lower) == target_identifier -%}
          {%- set found.node = src -%}
        {%- endif -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}

  {#- Tier 3: identifier-only fallback on graph.nodes for cross-env sv_ref scenarios where the
      resolved table lives in a
      different database than the one recorded in graph.nodes.
      Sources are intentionally excluded: source identifiers are not unique within a project and
      an identifier-only match against graph.sources risks returning the wrong node. -#}
  {%- if found.node is none -%}
    {%- for node in graph.nodes.values() -%}
      {%- if found.node is none -%}
        {%- set physical = node.alias or node.identifier or node.name -%}
        {%- if physical and (physical | lower) == target_identifier -%}
          {%- set found.node = node -%}
        {%- endif -%}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}

  {%- if found.node is not none -%}
    {%- set columns = found.node.columns or {} -%}
    {%- set col_def = columns.get(column_name) -%}
    {%- if col_def is none -%}
      {# Case-insensitive fallback: yaml column keys may differ in case. #}
      {%- set lookup_key = column_name | lower -%}
      {%- for col_key, col_val in columns.items() -%}
        {%- if col_def is none and (col_key | lower) == lookup_key -%}
          {%- set col_def = col_val -%}
        {%- endif -%}
      {%- endfor -%}
    {%- endif -%}
    {%- if col_def is not none and col_def.description is not none -%}
      {{- col_def.description -}}
    {%- endif -%}
  {%- endif -%}
{%- endmacro %}
