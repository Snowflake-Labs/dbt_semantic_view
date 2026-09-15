{{ config(materialized='test') }}

-- semantic_view_basic's schema.yml has a description AND persist_docs.relation
-- is true at the project level, but the model's SQL already writes an inline
-- COMMENT='test semantic view'. Inline SQL wins: the schema.yml description
-- must NOT override the inline comment.
select 'inline COMMENT was overridden by schema.yml description' as error_message
where position(
  'comment=''test semantic view'''
  in lower(get_ddl('SEMANTIC_VIEW', '{{ dbt_semantic_view.sv_ref('semantic_view_basic') }}'))
) = 0
