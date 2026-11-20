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
-- Step 3: build a Cortex Sense context named PROCUREMENT.
--
-- The scope says what Cortex Sense reads:
--   catalog_objects    every table in SENSE_ONTOLOGY_QS.SAP: names, columns,
--                      comments and keys
--   semantic_views     PROCUREMENT_SV: its metrics, joins and synonyms
--   query_history      the queries people already run on those tables
--   business_ontology  the approved terms in the Procurement and Logistics
--                      domains
--
-- Part 1 saves the scope and starts the build, which runs in the background
-- for a few minutes. Run checks.sql CHECK 4 until it says PASS, then run
-- Part 2 to see what Cortex Sense found. Re-running Part 1 saves the scope
-- again and rebuilds.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Part 1: save the scope and start the build
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;

EXECUTE IMMEDIATE $$
DECLARE
  context_name STRING DEFAULT 'PROCUREMENT';
  scope STRING DEFAULT 'business_domain: PROCUREMENT
warehouse: SENSE_ONTOLOGY_WH
sources:
- name: catalog_objects
  type: snowflake_metadata
  enabled: true
  rules:
  - type: pattern
    pattern: SENSE_ONTOLOGY_QS.SAP.*
- name: semantic_views
  type: snowflake_content
  enabled: true
  rules:
  - type: pattern
    pattern: SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV
- name: query_history
  type: snowflake_metadata
  enabled: true
- name: business_ontology
  type: snowflake_metadata
  enabled: true
  rules:
  - type: ontology_domain
    domain: Procurement
    promotion: draft
  - type: ontology_domain
    domain: Logistics
additional_instructions: []
in_account_instructions: []
status: active
version_id: v-quickstart-1
';
  location OBJECT;
  payload STRING;
  result STRING;
BEGIN
  location := OBJECT_CONSTRUCT('name', context_name, 'database_name', 'SENSE_ONTOLOGY_QS', 'schema_name', 'SAP');

  -- 1. Create the context.
  payload := OBJECT_CONSTRUCT('action', 'create-context', 'parameters', location)::STRING;
  -- On a re-run the context already exists; keep it and save the scope again.
  result := (SELECT SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER(:payload));
  IF (PARSE_JSON(result):error::BOOLEAN AND NOT CONTAINS(result, 'AlreadyExists')) THEN
    RETURN 'create-context failed: ' || result;
  END IF;

  -- 2. Save the scope.
  payload := OBJECT_CONSTRUCT('action', 'put-stage-file', 'parameters',
               OBJECT_INSERT(OBJECT_INSERT(OBJECT_INSERT(location, 'path', 'scope.yaml'), 'content', scope), 'overwrite', TRUE))::STRING;
  result := (SELECT SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER(:payload));
  IF (PARSE_JSON(result):error::BOOLEAN) THEN
    RETURN 'saving the scope failed: ' || result;
  END IF;

  -- 3. Start the build.
  payload := OBJECT_CONSTRUCT('action', 'force-reprocess', 'parameters', location)::STRING;
  result := (SELECT SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER(:payload));
  IF (PARSE_JSON(result):error::BOOLEAN) THEN
    RETURN 'starting the build failed: ' || result;
  END IF;

  RETURN 'Context ' || context_name || ' saved. The build is running: run CHECK 4 in checks.sql until it says PASS.';
END;
$$;

ALTER CORTEX SENSE SENSE_ONTOLOGY_QS.SAP.PROCUREMENT SET COMMENT =
  'Procurement context for SAP purchasing data: suppliers, materials, purchase orders and spend, plus the shipments and carriers behind on-time delivery. Built from the SAP tables, the PROCUREMENT_SV semantic view, query history and the approved Procurement and Logistics ontology terms.';

-- -----------------------------------------------------------------------------
-- Part 2: what did Cortex Sense find? Run this after CHECK 4 passes.
-- Each lookup returns the documents an agent gets for the question: tables
-- (table_entity), approved ontology terms (ontology_node), and the semantic
-- view or domain (datamart). The order can differ from run to run.
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;

SELECT d.index + 1 AS rank,
       d.value:doc_type::STRING AS doc_type,
       d.value:entity_key::STRING AS entity_key,
       LEFT(REGEXP_REPLACE(d.value:cam_content::STRING, '\\s+', ' '), 300) AS preview
FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT(
  '{"request_structured": {"query": "How many suppliers do we have?", "max_results": 6}}')):response_structured:documents)) d;

-- The storage location table T320 is not in the semantic view or the ontology,
-- and has no table comment. Cortex Sense still found it and described it.
SELECT d.index + 1 AS rank,
       d.value:doc_type::STRING AS doc_type,
       d.value:entity_key::STRING AS entity_key,
       LEFT(REGEXP_REPLACE(d.value:cam_content::STRING, '\\s+', ' '), 300) AS preview
FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT(
  '{"request_structured": {"query": "storage location", "max_results": 4}}')):response_structured:documents)) d;

-- The full document Cortex Sense wrote for the vendor master table. It
-- combines the column metadata, the semantic view's descriptions and joins,
-- and the questions people are likely to ask of it.
SELECT d.value:cam_content::STRING AS lfa1_document
FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT(
  '{"request_structured": {"query": "vendor master", "fully_qualified_names": ["SENSE_ONTOLOGY_QS.SAP.LFA1"], "max_results": 1}}')):response_structured:documents)) d;
