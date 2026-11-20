-- Copyright 2026 Snowflake Inc.
-- SPDX-License-Identifier: Apache-2.0
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- =============================================================================
-- Optional: compare two Cortex Agents on the same questions.
--
--   SV_ONLY_AGENT     the semantic view, nothing else
--   GOVERNED_AGENT    the semantic view, plus Business Ontology search for the
--                     approved definitions, plus the Cortex Sense context
--
-- Part 2 asks each agent the two questions that have a look-alike answer.
-- Both agents usually reach 14 and 66.67%, because the semantic view's metric
-- definitions already carry the logic. Compare how they explain it:
-- GOVERNED_AGENT names the approved term, the policy behind it and the variant
-- it did not use. SV_ONLY_AGENT can only infer why from the data.
--
-- Business Ontology search can take a few hours to pick up newly approved
-- terms. If GOVERNED_AGENT does not name an approved term, run Part 2 again
-- later.
-- =============================================================================

USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
USE SCHEMA SENSE_ONTOLOGY_QS.SAP;

-- -----------------------------------------------------------------------------
-- Part 1: create the agents
-- -----------------------------------------------------------------------------
CREATE OR REPLACE AGENT SENSE_ONTOLOGY_QS.SAP.SV_ONLY_AGENT
  COMMENT = 'Semantic view only'
  FROM SPECIFICATION $$
models:
  orchestration: auto
orchestration:
  budget:
    seconds: 150
    tokens: 40000
instructions:
  response: |
    You are an analytics assistant for SAP procurement data.
    State the final answer as a clear number first, then briefly explain how it
    was computed and which data was used.
  orchestration: |
    Use query_procurement for every data question.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: query_procurement
      description: Procurement data - suppliers, materials, purchase orders, shipments, carriers.
tool_resources:
  query_procurement:
    semantic_view: SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV
    execution_environment: {type: warehouse, warehouse: SENSE_ONTOLOGY_WH, query_timeout: 120}
$$;

CREATE OR REPLACE AGENT SENSE_ONTOLOGY_QS.SAP.GOVERNED_AGENT
  COMMENT = 'Semantic view plus Business Ontology and Cortex Sense'
  FROM SPECIFICATION $$
models:
  orchestration: auto
experimental:
  EnableSnowscopeBusinessOntologySearch: true
orchestration:
  budget:
    seconds: 150
    tokens: 40000
instructions:
  response: |
    You are an analytics assistant for SAP procurement data.
    State the final answer as a clear number first, then briefly explain how it
    was computed and which data was used. When you used an approved Business
    Ontology definition, name the term.
  orchestration: |
    Before querying data, call business_ontology to look up the approved
    definition of each business term in the question, and call
    procurement_context for how the tables join and what the codes mean. When
    the ontology names an official metric, use it rather than a similarly named
    variant, and follow any policy that applies to it. Then use
    query_procurement to compute it.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: query_procurement
      description: Procurement data - suppliers, materials, purchase orders, shipments, carriers.
  - tool_spec:
      type: snowscope_search
      name: business_ontology
      description: Approved business definitions - official metrics and their variants, policies and code meanings.
  - tool_spec:
      type: cortex_sense
      name: procurement_context
      description: Context Cortex Sense built for the SAP procurement tables - joins, key columns, code meanings and the approved definitions.
tool_resources:
  query_procurement:
    semantic_view: SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV
    execution_environment: {type: warehouse, warehouse: SENSE_ONTOLOGY_WH, query_timeout: 120}
  business_ontology:
    corpus: businessOntology
  procurement_context:
    context_name: SENSE_ONTOLOGY_QS.SAP.PROCUREMENT
    execution_environment: {type: warehouse, warehouse: SENSE_ONTOLOGY_WH, query_timeout: 120}
$$;

-- -----------------------------------------------------------------------------
-- Part 2: ask both agents the same questions (takes a minute or two)
-- -----------------------------------------------------------------------------
-- DATA_AGENT_RUN needs literal arguments, so each question and agent pair is
-- its own call.
WITH runs AS (
  SELECT 'How many suppliers do we have?' AS question, '14' AS expected, 'SV_ONLY_AGENT' AS agent,
         PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SENSE_ONTOLOGY_QS.SAP.SV_ONLY_AGENT',
           '{"messages":[{"role":"user","content":[{"type":"text","text":"How many suppliers do we have?"}]}]}')) AS response
  UNION ALL
  SELECT 'How many suppliers do we have?' AS question, '14' AS expected, 'GOVERNED_AGENT' AS agent,
         PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SENSE_ONTOLOGY_QS.SAP.GOVERNED_AGENT',
           '{"messages":[{"role":"user","content":[{"type":"text","text":"How many suppliers do we have?"}]}]}')) AS response
  UNION ALL
  SELECT 'What is our on-time delivery rate?' AS question, '66.67%' AS expected, 'SV_ONLY_AGENT' AS agent,
         PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SENSE_ONTOLOGY_QS.SAP.SV_ONLY_AGENT',
           '{"messages":[{"role":"user","content":[{"type":"text","text":"What is our on-time delivery rate?"}]}]}')) AS response
  UNION ALL
  SELECT 'What is our on-time delivery rate?' AS question, '66.67%' AS expected, 'GOVERNED_AGENT' AS agent,
         PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SENSE_ONTOLOGY_QS.SAP.GOVERNED_AGENT',
           '{"messages":[{"role":"user","content":[{"type":"text","text":"What is our on-time delivery rate?"}]}]}')) AS response
)
SELECT r.question, r.expected, r.agent,
       LISTAGG(IFF(c.value:type = 'tool_use', c.value:tool_use:name::STRING, NULL), ', ') AS tools_used,
       LISTAGG(IFF(c.value:type = 'text', c.value:text::STRING, NULL), '\n') AS answer
FROM runs r, LATERAL FLATTEN(INPUT => r.response:content) c
GROUP BY 1, 2, 3
ORDER BY 1, 3 DESC;

-- teardown.sql drops these agents with the database.
