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

The value is a YAML string matching the format accepted by the stored procedure:

```sql
{{ config(
    materialized='semantic_view',
    create_or_alter=true,
    sv_materializations="""
materializations:
  - name: by_region_date
    warehouse: MY_WAREHOUSE
    dimensions:
      - table: fact
        name: region
      - table: fact
        name: date
    metrics:
      - table: fact
        name: revenue
    filter_clause: "WHERE (fact.date >= '2020-01-01')"  # optional: mutable filter — planner rewrites
                                                         #   queries whose filter matches or is stricter
    immutable_where: "date < '2024-01-01'"               # optional: freeze historical rows permanently
                                                         #   out of refresh; predicate columns must be
                                                         #   included in this materialization's dimensions
    refresh_mode: AUTO                       # optional: AUTO (default) | INCREMENTAL | FULL
"""
) }}

TABLES(fact AS {{ ref('fact_sales') }})
DIMENSIONS(fact.region as region, fact.date as date)
METRICS(fact.revenue AS SUM(fact.revenue_amount))
MAX_STALENESS = '1 hour'
```

Use `filter_clause` for a mutable materialization filter. The value is passed through to Snowflake's
`ADD MATERIALIZATION` statement, so include the `WHERE (...)` keyword and predicate text. Do not use a
top-level YAML key named `where`.

Use `immutable_where` for a frozen historical region. It is mutually exclusive with `filter_clause` for a
single materialization. The predicate should reference the materialization output column name, not a
qualified source expression, and that column must be part of the materialization's dimensions.

When you need Jinja expressions inside the YAML (e.g. to inject a warehouse from the dbt profile or an environment variable), use a `{% set %}` block to build the string first:

```sql
{%- set sv_mats_yaml -%}
materializations:
  - name: by_region_date
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
    sv_materializations=sv_mats_yaml
) }}

TABLES(fact AS {{ ref('fact_sales') }})
DIMENSIONS(fact.region as region)
METRICS(fact.revenue AS SUM(fact.revenue_amount))
```

To set `LOG_EVENT_LEVEL` on materializations (e.g. for event table alerting), use a `post_hook`:

```sql
post_hook=["ALTER SEMANTIC VIEW {{ this }} ALTER MATERIALIZATION my_mat SET LOG_EVENT_LEVEL = 'INFO'"]
```

### Note on documentation persistence (persist_docs)
At this time, dbt-driven documentation persistence for Semantic Views (`persist_docs`) is not supported by this package. Enabling `persist_docs` and adding model or column descriptions will not affect Semantic Views.

Inline `COMMENT` syntax within the Semantic View DDL is supported and will be applied by Snowflake. For example:
```
CREATE OR REPLACE SEMANTIC VIEW <name>
  TABLES ( ... COMMENT = '...' )
  [ FACTS ( ... COMMENT = '...' ) ]
  [ DIMENSIONS ( ... COMMENT = '...' ) ]
  [ METRICS ( ... COMMENT = '...' ) ]
  [ COMMENT = '...' ]
```

We plan to revisit `persist_docs` support as upstream capabilities evolve.

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
