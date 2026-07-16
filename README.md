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

### Cortex Analyst enrichments (`ca_extensions`)

The `ca_extensions` macro generates the `WITH EXTENSION (CA=$$...$$)` block that enriches a semantic view for [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst). Use it to attach **verified queries**, **custom instructions**, **relationships**, and per-table metadata without hand-writing JSON.

**Parameters**

| Parameter | Type | Description |
|---|---|---|
| `verified_queries` | list of dicts | Pre-verified SQL + natural-language question pairs shown in the Cortex Analyst UI |
| `custom_instructions` | str | Free-text instructions appended to every Cortex Analyst prompt for this view |
| `relationships` | list of dicts | Cross-table relationship definitions |
| `tables` | list of dicts | Per-table Cortex Analyst metadata (synonyms, filters, etc.) |

**Verified query fields**

| Field | Required | Description |
|---|---|---|
| `name` | yes | Short label shown in the UI |
| `question` | yes | Natural-language question this SQL answers |
| `sql` | yes | Verified SQL (use table aliases from `TABLES(...)`, not fully-qualified names) |
| `verified_at` | no | Unix timestamp of verification |
| `verified_by` | no | Name of the person who verified |
| `use_as_onboarding_question` | no | Surface this question in the onboarding flow |

**Example**

```sql
{{ config(materialized='semantic_view') }}

TABLES(orders AS {{ ref('orders') }})
DIMENSIONS(orders.status AS status)
METRICS(orders.order_count AS COUNT(*))

{{ dbt_semantic_view.ca_extensions(
    verified_queries=[
        {
            "name": "total orders last 30 days",
            "question": "How many orders were placed in the last 30 days?",
            "sql": "SELECT COUNT(*) AS order_count FROM orders WHERE order_date >= CURRENT_DATE - 30",
            "verified_at": 1733356800,
            "verified_by": "Jane Smith",
            "use_as_onboarding_question": true
        }
    ],
    custom_instructions="Always filter to completed orders unless the user specifies otherwise."
) }}
```

This renders as:

```sql
CREATE OR REPLACE SEMANTIC VIEW <name>
TABLES(orders AS ...)
DIMENSIONS(orders.status AS status)
METRICS(orders.order_count AS COUNT(*))
with extension (CA=$$
{
  "verified_queries": [{"name": "total orders last 30 days", ...}],
  "custom_instructions": "Always filter to completed orders unless the user specifies otherwise."
}
$$)
```

All parameters are optional — `ca_extensions` only includes keys that have values, so you can start with just `verified_queries` and add the rest later.

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
