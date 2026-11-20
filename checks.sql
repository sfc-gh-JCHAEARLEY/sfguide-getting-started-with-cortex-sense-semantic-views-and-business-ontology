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
-- Checkpoints. Run each CHECK block when the guide tells you to.
-- Every row should say PASS. Each block sets its own role and warehouse,
-- so you can run any block on its own.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CHECK 1 - after setup.sql
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
SELECT check_name, expected, actual, IFF(expected = actual, 'PASS', 'FAIL') AS result
FROM (
  SELECT 'Tables in SENSE_ONTOLOGY_QS.SAP' AS check_name, 17 AS expected,
         (SELECT COUNT(*) FROM SENSE_ONTOLOGY_QS.INFORMATION_SCHEMA.TABLES
          WHERE TABLE_SCHEMA = 'SAP' AND TABLE_TYPE = 'BASE TABLE') AS actual
  UNION ALL SELECT 'Vendor master records (LFA1)', 15, (SELECT COUNT(*) FROM SENSE_ONTOLOGY_QS.SAP.LFA1)
  UNION ALL SELECT 'Shipments (LIKP)', 20, (SELECT COUNT(*) FROM SENSE_ONTOLOGY_QS.SAP.LIKP)
);

-- -----------------------------------------------------------------------------
-- CHECK 2 - after semantic_view.sql
-- The official metrics and their look-alikes disagree on purpose.
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
SELECT check_name, expected, actual, IFF(expected = actual, 'PASS', 'FAIL') AS result
FROM (
  SELECT 'SUPPLIER_COUNT (official)' AS check_name, 14.00::NUMBER(10,2) AS expected,
         (SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LFA1.SUPPLIER_COUNT))::NUMBER(10,2) AS actual
  UNION ALL SELECT 'VENDOR_RECORD_COUNT (look-alike)', 15,
         (SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LFA1.VENDOR_RECORD_COUNT))
  UNION ALL SELECT 'ON_TIME_DELIVERY_RATE (official)', 66.67,
         (SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LIKP.ON_TIME_DELIVERY_RATE))
  UNION ALL SELECT 'CARRIER_REPORTED_ON_TIME_RATE (look-alike)', 90.00,
         (SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LFA2.CARRIER_REPORTED_ON_TIME_RATE))
);

-- -----------------------------------------------------------------------------
-- CHECK 3 - after ontology.sql
-- Counts only what belongs to the Procurement and Logistics domains, so other
-- domains in your account don't change the result.
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
WITH g AS (SELECT PARSE_JSON(SYSTEM$GET_ONTOLOGY_GRAPH()) AS g),
nodes AS (
  SELECT t.value:termId::STRING AS term_id
  FROM g, LATERAL FLATTEN(INPUT => g:terms) t
  WHERE t.value:domain::STRING IN ('Procurement', 'Logistics')
),
rels AS (
  SELECT r.value FROM g, LATERAL FLATTEN(INPUT => g:relationships) r
  WHERE r.value:sourceTermId::STRING IN (SELECT term_id FROM nodes)
),
reps AS (
  SELECT a.value FROM g, LATERAL FLATTEN(INPUT => g:associations) a
  WHERE a.value:termId::STRING IN (SELECT term_id FROM nodes)
)
SELECT check_name, expected, actual, IFF(expected = actual, 'PASS', 'FAIL') AS result
FROM (
  SELECT 'Approved nodes' AS check_name, 12 AS expected, (SELECT COUNT(*) FROM nodes) AS actual
  UNION ALL SELECT 'Relationships', 11, (SELECT COUNT(*) FROM rels)
  UNION ALL SELECT 'Cross-domain relationships (Procurement to Logistics)', 2,
    (SELECT COUNT(*) FROM rels WHERE value:targetTermId::STRING IN
       (SELECT t.value:termId::STRING FROM g, LATERAL FLATTEN(INPUT => g:terms) t WHERE t.value:domain::STRING = 'Logistics')
     AND value:sourceTermId::STRING IN
       (SELECT t.value:termId::STRING FROM g, LATERAL FLATTEN(INPUT => g:terms) t WHERE t.value:domain::STRING = 'Procurement'))
  UNION ALL SELECT 'Representations', 12, (SELECT COUNT(*) FROM reps)
  UNION ALL SELECT 'Metrics linked to a semantic view metric', 5,
    (SELECT COUNT(*) FROM reps WHERE value:subObjectType::STRING = 'METRIC' AND value:validity::STRING = 'VALID')
);

-- -----------------------------------------------------------------------------
-- CHECK 4 - after the Cortex Sense build
-- A context that is still building shows a last-processed date in 1970.
-- Re-run this block every few minutes until it says PASS.
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
SELECT 'PROCUREMENT context processed' AS check_name,
       'processed' AS expected,
       IFF(c.value:last_processed_at::STRING LIKE '1970%', 'building', 'processed') AS actual,
       IFF(actual = expected, 'PASS', 'FAIL (still building, check again in a few minutes)') AS result
FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER('{"action":"list-contexts"}')):response_structured:cortex_contexts)) c
WHERE c.value:database_name::STRING = 'SENSE_ONTOLOGY_QS'
  AND c.value:name::STRING = 'PROCUREMENT';

-- -----------------------------------------------------------------------------
-- CHECK 5 - the answers to the Ask CoCo questions
-- Compare these with what CoCo told you. The first two come from the
-- semantic view metrics the ontology marks as official. The third comes from
-- T320, a table outside the semantic view that Cortex Sense found.
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
SELECT question, expected, actual, IFF(expected = actual, 'PASS', 'FAIL') AS result
FROM (
  SELECT 'How many suppliers do we have?' AS question, '14' AS expected,
         (SELECT SUPPLIER_COUNT::STRING FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LFA1.SUPPLIER_COUNT)) AS actual
  UNION ALL SELECT 'What is our on-time delivery rate?', '66.67%',
         (SELECT TO_VARCHAR(ON_TIME_DELIVERY_RATE, 'FM990.00') || '%' FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LIKP.ON_TIME_DELIVERY_RATE))
  UNION ALL SELECT 'How many storage locations does plant PLT-001 have?', '3',
         (SELECT COUNT(*)::STRING FROM SENSE_ONTOLOGY_QS.SAP.T320 WHERE WERKS = 'PLT-001')
);
