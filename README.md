## Snowflake Semantic View dbt Package

Professional dbt macros and integration tests for building, dropping, and renaming Snowflake Semantic Views. This package lets you materialize Semantic Views via dbt and reference them from downstream models.

### Compatibility

> **Full SQL API coverage** — This package automatically supports the complete Snowflake `CREATE SEMANTIC VIEW` SQL syntax. When Snowflake introduces new semantic view capabilities, the package picks them up without requiring any code change or package upgrade. Simply update your model definition to use the new syntax and run `dbt build`.
>
> For the full syntax reference, see [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view#syntax).

### At a glance
- **Materialization**: `semantic_view`
- **Warehouse**: Snowflake
- **dbt Compatibility**: dbt 1.x
- **Supports**: `CREATE OR ALTER`, `MAX_STALENESS`, and declarative materialization management

### Quickstart
Follow these steps on macOS/Linux with Python 3 installed. No prior dbt installation is required.

1) Clone and enter the repo
```
git clone https://github.com/Snowflake-Labs/dbt_semantic_view.git
cd dbt_semantic_view/
```

2) Create an isolated Python environment and install dependencies
```
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install dbt-snowflake
```

3) Configure Snowflake credentials (env vars)

Set the following environment variables for the integration profile. For username/password auth use `SNOWFLAKE_TEST_AUTHENTICATOR=snowflake`.
```
export SNOWFLAKE_TEST_ACCOUNT=<account>
export SNOWFLAKE_TEST_USER=<user>
export SNOWFLAKE_TEST_PASSWORD=<password>
export SNOWFLAKE_TEST_AUTHENTICATOR=<authenticator>   # e.g. snowflake | externalbrowser
export SNOWFLAKE_TEST_ROLE=<role>
export SNOWFLAKE_TEST_DATABASE=<database>
export SNOWFLAKE_TEST_WAREHOUSE=<warehouse>
export SNOWFLAKE_TEST_SCHEMA=<schema>
```

4) Run integration tests
```
cd integration_tests/
dbt deps --target snowflake
dbt build --target snowflake
```

### Usage in your dbt project
Add to `packages.yml`:
```
packages:
  - package: Snowflake-Labs/dbt_semantic_view
    verion: <latest version/your selected version>
```

To find the current version, see the [dbt_semantic_view package page](https://hub.getdbt.com/Snowflake-Labs/dbt_semantic_view/latest/).

> **Note:** This package is a direct passthrough to Snowflake's SQL layer. You don't need to update the package version to access new Snowflake semantic view features. When Snowflake adds new SQL capabilities (for example, AI_VERIFIED_QUERIES), they will be available immediately via the package without any package update.

Create a model using the Semantic View materialization:
```
{{ config(materialized='semantic_view') }}
TABLES(
  {{ source('<source_name>', '<table_name>') }},
  {{ ref('<another_model>') }}
)
[ RELATIONSHIPS ( relationshipDef [ , ... ] ) ]
[ FACTS ( semanticExpression [ , ... ] ) ]
[ DIMENSIONS ( semanticExpression [ , ... ] ) ]
[ METRICS ( semanticExpression [ , ... ] ) ]
...
```
for the complete list of support semantic view elements please refer to: https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view#syntax

Reference a Semantic View from another model:
```
{{ config(materialized='table') }}
select *
from semantic_view(
  {{ ref('<semantic_view_model>') }}
  [ { METRICS <metric> | FACTS <fact_expr> } ]
  [ DIMENSIONS <dimension_expr> ]
  [ WHERE <predicate> ]
)
```

### Config options

All config options are set via `{{ config(...) }}` at the top of your model file.

| Option | Type | Default | Description |
|---|---|---|---|
| `copy_grants` | bool | `false` | Preserve grants when the view is replaced |
| `create_or_alter` | bool | `false` | Use `CREATE OR ALTER` instead of `CREATE OR REPLACE` — non-destructive, preserves materializations and grants across runs |
| `max_staleness` | string | none | Inject a `MAX_STALENESS = '<value>'` clause — required when `sv_materializations` is set; mutually exclusive with a `MAX_STALENESS` clause in the model SQL body |
| `sv_materializations` | string (YAML) | none | Declarative materialization spec; see below |

`copy_grants` only applies to `CREATE OR REPLACE`. Snowflake does not support `COPY GRANTS` with `CREATE OR ALTER`.

#### `create_or_alter`

Use `CREATE OR ALTER` when your semantic view has materializations. `CREATE OR REPLACE` drops and recreates the view on every run, which silently removes all attached materializations.

```sql
{{ config(materialized='semantic_view', create_or_alter=true) }}

TABLES(fact AS {{ ref('fact_sales') }})
DIMENSIONS(fact.region as region)
METRICS(fact.revenue AS SUM(fact.revenue_amount))
```

#### `sv_materializations`

Declares one or more materializations on the semantic view. On every `dbt run` the package calls `SYSTEM$MANAGE_SEMANTIC_VIEW_MATERIALIZATIONS_FROM_YAML`, which diffs the desired state against the current state and only adds, updates, or drops what changed.

We highly recommend setting `create_or_alter=true` whenever you use `sv_materializations`. Without it, the model uses `CREATE OR REPLACE`, which drops and recreates the semantic view — and every materialization on it — on each run.

`MAX_STALENESS` is required when using `sv_materializations`. You can set it via the `max_staleness` config key (recommended) or by including the clause directly in the model SQL body.

The simplest example:

```sql
{{ config(
    materialized='semantic_view',
    create_or_alter=true,
    max_staleness='1 hour',
    sv_materializations="""
materializations:
  - name: by_region
    warehouse: MY_WAREHOUSE
    dimensions:
      - table: fact
        name: region
    metrics:
      - table: fact
        name: revenue
"""
) }}

TABLES(fact AS {{ ref('fact_sales') }})
DIMENSIONS(fact.region as region)
METRICS(fact.revenue AS SUM(fact.revenue_amount))
```

When you need Jinja expressions inside the YAML (e.g. to inject the warehouse from the dbt profile or an environment variable), use a `{% set %}` block to build the string first:

```sql
{%- set sv_mats_yaml -%}
materializations:
  - name: by_region
    warehouse: {{ target.warehouse }}
    dimensions:
      - table: fact
        name: region
    metrics:
      - table: fact
        name: revenue
{%- endset -%}

{{ config(
    materialized='semantic_view',
    create_or_alter=true,
    max_staleness='1 hour',
    sv_materializations=sv_mats_yaml
) }}

TABLES(fact AS {{ ref('fact_sales') }})
DIMENSIONS(fact.region as region)
METRICS(fact.revenue AS SUM(fact.revenue_amount))
```

**Optional: `filter_clause`** — restrict which rows the materialization pre-computes. The query planner uses the materialization when a query's filter matches or is stricter. Include the `WHERE (...)` keyword:

```yaml
    filter_clause: "WHERE (fact.date >= '2020-01-01')"
```

Do not use a top-level YAML key named `where` — it is not supported.

**Optional: `immutable_where`** — permanently exclude rows from refresh (e.g. rows that will never change). Mutually exclusive with `filter_clause` for a single materialization. The predicate must reference the materialization output column name (not a qualified source expression), and that column must be included in the materialization's dimensions:

```yaml
    immutable_where: "date < '2024-01-01'"
```

**Optional: `refresh_mode`** — `AUTO` (default) | `INCREMENTAL` | `FULL`. Note: this field is silently ignored by `SYSTEM$MANAGE_SEMANTIC_VIEW_MATERIALIZATIONS_FROM_YAML` — `REFRESH_MODE` is a DDL-only parameter and is not part of the SP's YAML schema. Snowflake defaults to `AUTO` (incremental where possible). To set a specific refresh mode, use `ALTER SEMANTIC VIEW ... ADD MATERIALIZATION ... REFRESH_MODE = FULL AS DIMENSIONS ... METRICS ...` directly.

To set `LOG_EVENT_LEVEL` on materializations (e.g. for event table alerting), use a `post_hook`:

```sql
post_hook=["ALTER SEMANTIC VIEW {{ this }} ALTER MATERIALIZATION my_mat SET LOG_EVENT_LEVEL = 'INFO'"]
```

#### Built-in materialization tests

The package ships two generic dbt tests you can attach to any semantic view model to verify that materializations are in place and healthy:

```yaml
models:
  - name: my_semantic_view
    tests:
      - dbt_semantic_view.materialization_exists:
          materialization_name: my_mat
      - dbt_semantic_view.materialization_is_active:
          materialization_name: my_mat
```

- **`materialization_exists`** — fails if the named materialization is absent from the semantic view.
- **`materialization_is_active`** — fails if the materialization is absent or suspended.

### Unit testing Semantic Views

dbt's [`unit_tests`](https://docs.getdbt.com/docs/build/unit-tests) can fixture and verify a model that references a Semantic View. This requires a small amount of one-time project setup.

1) Route `ref()`/`source()` through the package's unit-test-aware wrappers. Add a project-level dispatch override in `dbt_project.yml`:
```yaml
dispatch:
  - macro_namespace: dbt
    search_order: ['dbt_semantic_view', 'dbt']
```
and a macro that overrides the builtins for your project:
```sql
{% macro ref() %}
  {{ return(dbt_semantic_view.sv_aware_ref(varargs, kwargs)) }}
{% endmacro %}

{% macro source(source_name, table_name) %}
  {{ return(dbt_semantic_view.sv_aware_source(source_name, table_name)) }}
{% endmacro %}
```

2) Move the Semantic View's body into an `sv_def__<model_name>` macro, and have the model call it. This lets the unit test render the same definition inline instead of querying the real Semantic View:
```sql
{% macro sv_def__my_semantic_view() %}
TABLES(t1 AS {{ ref('base_table') }}, t2 AS {{ source('my_source', 'base_table2') }})
DIMENSIONS(t1.region AS region)
METRICS(t1.revenue AS SUM(t1.revenue_amount))
{% endmacro %}
```
```sql
{{ config(materialized='semantic_view') }}
{{ sv_def__my_semantic_view() }}
```

3) Write the unit test against a model that references the Semantic View — not against the Semantic View model itself. Fixture the Semantic View's underlying tables/sources, and dbt will splice `sv_def__my_semantic_view()` in as a CTE:
```yaml
unit_tests:
  - name: test_revenue_by_region
    model: model_that_selects_from_my_semantic_view
    given:
      - input: ref('base_table')
        rows:
          - {region: 'west', revenue_amount: 100}
      - input: source('my_source', 'base_table2')
        rows:
          - {region: 'west', volume: 5}
    expect:
      rows:
        - {REVENUE: 100}
```

4) Run it
```
dbt test --select test_revenue_by_region
```

**Limitation:** this only supports models whose compiled SQL doesn't already open with its own `WITH` clause — dbt merges fixture CTEs into an existing `WITH` rather than prepending a new one, and the splice macro doesn't parse that merged form. A model like this raises a clear compiler error instead of producing incorrect SQL.

### Note on documentation persistence (persist_docs)
At this time, dbt-driven documentation persistence for Semantic Views (`persist_docs`) is not supported by this package. Enabling `persist_docs` and adding model or column descriptions will not affect Semantic Views.

Snowflake Semantic View DDL requires bare `DATABASE.SCHEMA.IDENTIFIER` table references in `TABLES()` clauses and `semantic_view()` function calls. dbt's `--empty` flag rewrites `ref()` and `source()` into `(SELECT ... LIMIT 0)` subqueries, which breaks this syntax.

`sv_ref()` and `sv_source()` render the fully-qualified identifier directly while still registering the dependency in the dbt DAG, so lineage and catalog integration work as expected.

**When to use them:** only inside `TABLES()` clauses in semantic view model definitions, and inside `semantic_view()` function calls in downstream query models. Use standard `ref()` and `source()` everywhere else (normal `SELECT` statements, `WHERE` clauses, CTEs, etc.).

Defining a semantic view:
```sql
{{ config(materialized='semantic_view') }}

TABLES(t1 AS {{ dbt_semantic_view.sv_ref('base_table') }})
DIMENSIONS(t1.count as value)
METRICS(t1.total_rows AS SUM(t1.count))
```

Querying a semantic view from a downstream model:
```sql
select * from semantic_view({{ dbt_semantic_view.sv_ref('my_semantic_view') }} metrics total_rows)
```

Using a source table:
```sql
TABLES(t1 AS {{ dbt_semantic_view.sv_source('my_source', 'my_table') }})
```

### Documentation persistence (persist_docs)
This package supports both relation-level and column-level `persist_docs` for Semantic Views.

**Relation-level** — enable `persist_docs: {relation: true}` and add a model `description:` in `schema.yml`. The description is emitted as a top-level `COMMENT = $$...$$` on the `CREATE OR REPLACE SEMANTIC VIEW` statement. If your model already writes an inline top-level `COMMENT = ...`, it is preserved unchanged (**inline SQL wins**).

**Column-level (dimensions / metrics / facts)** — Snowflake requires dim/metric/fact `COMMENT` clauses to be emitted inline at create time (they cannot be added via `ALTER SEMANTIC VIEW`). Enable `persist_docs: {columns: true}`. Write your semantic view using the standard Snowflake syntax. At materialize time the package scans each `DIMENSIONS`/`METRICS`/`FACTS` entry and, when the RHS of `AS` is a simple column reference (optionally alias-qualified, e.g., `value` or `t1.value`) and the LHS is alias-qualified, looks up the underlying `schema.yml` / `source.yml` column description and appends `COMMENT = $$…$$` to that entry. Entries that already contain an inline `COMMENT = …` are left untouched (inline wins). Column lookups always resolve against the table behind the **LHS alias**, so cross-alias RHS references like `t1.my_dim AS t2.col` will pull the description for `col` from `t1`'s underlying table, not `t2`'s — if the two tables don't share that column, no comment is emitted.

Example — mirrors `integration_tests/models/semantic_view_with_persist_docs.sql`:

```sql
{{ config(materialized='semantic_view') }}

TABLES(t1 AS {{ dbt_semantic_view.sv_ref('base_table') }}, t2 AS {{ dbt_semantic_view.sv_source('seed_sources', 'base_table2') }})
DIMENSIONS(
  t1.count AS value,
  t2.volume AS value
)
METRICS(
  t1.total_rows AS SUM(t1.count) COMMENT = $$Total row count aggregate$$
)
```

With a model `description:` in `schema.yml` and project-wide `persist_docs: {relation: true, columns: true}`, this renders a single `CREATE OR REPLACE SEMANTIC VIEW` with a top-level `COMMENT`, plus per-dim `COMMENT = $$Generic numeric value column$$` resolved from the underlying `base_table.value` / `base_table2.value` descriptions. The metric's inline `COMMENT = $$Total row count aggregate$$` is preserved as-is — inline always wins.

### Development
- Python 3.9+ recommended
- Use a venv: `python3 -m venv .venv && source .venv/bin/activate`
- Install tooling as needed: `pip install dbt-snowflake`

### Contributing
We welcome issues and PRs! Please:
- Open an issue to discuss significant changes
- Keep edits focused and include tests where possible
- Follow dbt and Python best practices

### License
Apache License 2.0. See `LICENSE` for details.
