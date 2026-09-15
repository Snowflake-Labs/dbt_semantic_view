{% macro snowflake__get_columns_in_relation(relation) -%}

  {# Robust detection for Snowflake Semantic Views: prefer SHOW SEMANTIC VIEWS; fallback to graph #}
  {%- set is_semantic_view = false -%}
  {%- if execute -%}
    {%- set show_sql -%}
      show semantic views like '{{ relation.identifier }}' in schema {{ relation.database }}.{{ relation.schema }}
    {%- endset -%}
    {%- set show_res = run_query(show_sql) -%}
    {%- if show_res is not none and (show_res | length) > 0 -%}
      {%- set is_semantic_view = true -%}
    {%- elif graph is defined -%}
      {%- for node_id, node in graph.nodes.items() -%}
        {%- if node.resource_type == 'model' -%}
          {%- set node_relation_name = (node.alias if node.alias else node.name) | upper -%}
          {%- set target_relation_name = relation.identifier | upper -%}
          {%- if node_relation_name == target_relation_name and node.schema | upper == relation.schema | upper -%}
            {%- if node.config.materialized == 'semantic_view' -%}
              {%- set is_semantic_view = true -%}
            {%- endif -%}
          {%- endif -%}
        {%- endif -%}
      {%- endfor -%}
    {%- endif -%}
  {%- endif -%}

  {%- if is_semantic_view -%}
    {# For semantic views, return empty column list to signal special handling #}
    {%- set empty_table = [] -%}
    {{ return(empty_table) }}
  {%- endif -%}
  
  {# Not a semantic view - use standard DESCRIBE TABLE (default dbt behavior) #}
  {%- set sql -%}
    describe table {{ relation.render() }}
  {%- endset -%}
  {%- set result = run_query(sql) -%}
  
  {# Safety check: dbt can't handle more than 10,000 columns #}
  {% set maximum = 10000 %}
  {% if (result | length) >= maximum %}
    {% set msg %}
      Too many columns in relation {{ relation.render() }}! dbt can only get
      information about relations with fewer than {{ maximum }} columns.
    {% endset %}
    {% do exceptions.raise_compiler_error(msg) %}
  {% endif %}
  
  {# Convert DESCRIBE TABLE results to dbt Column objects #}
  {% set columns = [] %}
  {% for row in result %}
    {% do columns.append(api.Column.from_description(row['name'], row['type'])) %}
  {% endfor %}
  {% do return(columns) %}

{%- endmacro %}