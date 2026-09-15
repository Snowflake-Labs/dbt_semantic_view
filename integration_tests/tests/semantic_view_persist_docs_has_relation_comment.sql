{{ config(materialized='test') }}

-- Assert the persist_docs-enabled semantic view's DDL contains the model
-- description from schema.yml as a top-level COMMENT clause.
select 'model description missing from semantic_view_with_persist_docs DDL' as error_message
where position(
  'semantic view exercising both relation and column persist_docs'
  in lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_with_persist_docs') }}'))
) = 0
