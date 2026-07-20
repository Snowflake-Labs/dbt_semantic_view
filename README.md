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

### YAML-only features in DDL (time_dimensions, filters, data_type)
Snowflake's [YAML vs. DDL comparison](https://docs.snowflake.com/en/user-guide/views-semantic/yaml-vs-ddl) notes a few semantic-view features that can be expressed in the YAML semantic-model spec but **not** in plain `CREATE SEMANTIC VIEW` DDL:

- **`time_dimensions`** — a distinct category for date/timestamp columns (DDL only has generic dimensions).
- **Standalone `filters`** — named, table-level filter expressions consumed by Cortex Analyst.
- **`data_type`** — explicit column data-type declarations.

In Snowflake these fields live in the Cortex Analyst ("CA") extension, which a DDL-created view can carry through the `WITH EXTENSION (CA=$$ ...json... $$)` clause. Rather than hand-writing that escaped JSON, the `ca_yaml_features` macro lets you declare these fields as structured dicts and generates the clause for you.

**Parameters** (each entry is a dict routed by its `table` key; only keys with a value are emitted):

| Argument | Entry shape |
|----------|-------------|
| `time_dimensions` | `{table, name, expr, data_type?, synonyms?, sample_values?, description?}` |
| `filters` | `{table, name, expr, description?, synonyms?}` |
| `dimensions` | `{table, name, expr?, data_type, synonyms?, description?}` (use to declare an explicit `data_type` on a regular dimension) |

**Inline usage** — append the macro to your model body:
```sql
{{ config(materialized='semantic_view') }}
TABLES(orders AS {{ ref('orders') }})
DIMENSIONS(orders.status AS status)
METRICS(orders.total AS SUM(orders.amount))
{{ dbt_semantic_view.ca_yaml_features(
    time_dimensions=[{'table': 'orders', 'name': 'order_ts', 'expr': 'ORDER_TS', 'data_type': 'TIMESTAMP_NTZ'}],
    filters=[{'table': 'orders', 'name': 'recent', 'expr': 'order_ts > dateadd(day, -30, current_date)'}],
    dimensions=[{'table': 'orders', 'name': 'amount', 'expr': 'AMOUNT', 'data_type': 'NUMBER(38,2)'}]
) }}
```

**Config-driven usage** — pass the same lists via config keys (`time_dimensions`, `ca_filters`, `ca_dimensions`) and the materialization appends the clause automatically:
```sql
{{ config(
    materialized='semantic_view',
    time_dimensions=[{'table': 'orders', 'name': 'order_ts', 'expr': 'ORDER_TS', 'data_type': 'TIMESTAMP_NTZ'}],
    ca_filters=[{'table': 'orders', 'name': 'recent', 'expr': 'order_ts > dateadd(day, -30, current_date)'}],
    ca_dimensions=[{'table': 'orders', 'name': 'amount', 'expr': 'AMOUNT', 'data_type': 'NUMBER(38,2)'}]
) }}
TABLES(orders AS {{ ref('orders') }})
DIMENSIONS(orders.status AS status)
METRICS(orders.total AS SUM(orders.amount))
```

> **Notes**
> - The config-driven form cannot be combined with a hand-written `WITH EXTENSION` clause in the same model (a single CA extension is allowed); doing so raises a compiler error. Use the inline macro if you need to compose with other CA content.
> - These fields are metadata consumed by Cortex Analyst. Per Snowflake's docs, on the semantic SQL read path the compiler infers types regardless of a declared `data_type`.

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
