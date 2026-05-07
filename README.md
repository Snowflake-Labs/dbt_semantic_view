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
[ COMMENT = '<comment>' ]
[ COPY GRANTS ]
```

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

### Documentation persistence (persist_docs)
This package supports dbt-driven documentation persistence for Semantic Views through the `persist_docs` configuration. When enabled, model descriptions from `schema.yml` will be automatically added as `COMMENT` clauses to the Semantic View DDL.

To enable persist_docs for relation-level comments:
```yaml
# In your model config
{{ config(
    materialized='semantic_view',
    persist_docs={'relation': true}
) }}
```

Or in `dbt_project.yml`:
```yaml
models:
  your_project:
    +persist_docs:
      relation: true
```

When persist_docs is enabled, the model description from `schema.yml` will be applied:
```yaml
# schema.yml
models:
  - name: my_semantic_view
    description: "This description will become a COMMENT"
```

**Note**: Column-level persist_docs is not supported as Semantic Views use DIMENSIONS, METRICS, and FACTS rather than traditional columns.

Inline COMMENT syntax within the Semantic View DDL is also supported:
```
CREATE OR REPLACE SEMANTIC VIEW <name>
  TABLES ( ... COMMENT = '...' )
  [ FACTS ( ... COMMENT = '...' ) ]
  [ DIMENSIONS ( ... COMMENT = '...' ) ]
  [ METRICS ( ... COMMENT = '...' ) ]
  [ COMMENT = '...' ]
```

#### Column-level comments from schema.yml
This package provides utility macros to automatically add column-level comments from `schema.yml` descriptions to Semantic View elements:

```sql
{{ config(materialized='semantic_view') }}
TABLES ( t1 AS {{ ref('my_model') }} )
DIMENSIONS (
  t1.customer_id AS customer_id {{ dbt_semantic_view.get_column_comment('my_model', 'customer_id') }},
  t1.order_date AS order_date {{ dbt_semantic_view.get_column_comment('my_model', 'order_date') }}
)
FACTS (
  t1.amount AS amount {{ dbt_semantic_view.get_column_comment('my_model', 'amount') }}
)
COMMENT = '{{ dbt_semantic_view.get_model_comment("my_model") }}'
```

These macros will automatically extract descriptions from your `schema.yml` and apply them as `COMMENT` clauses.

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
