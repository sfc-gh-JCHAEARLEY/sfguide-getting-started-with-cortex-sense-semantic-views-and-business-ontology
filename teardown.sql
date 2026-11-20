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
-- Clean up: remove everything this quickstart created.
--
-- Run this file top to bottom (Run All). Part 1 runs as the lab role and
-- removes the Cortex Sense context and the two ontology domains. Part 2 runs
-- as ACCOUNTADMIN and drops the database, warehouse, role and API integration.
--
-- Ontology domains are account-level, so dropping the database does not
-- remove them.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Part 1: Cortex Sense context and ontology domains (lab role)
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;

-- The context lives in SENSE_ONTOLOGY_QS.SAP and would also go with the
-- database; deleting it first stops its background refresh straight away.
SELECT SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER('{"action":"delete-context","parameters":{"name":"PROCUREMENT","database_name":"SENSE_ONTOLOGY_QS","schema_name":"SAP"}}');

-- Other guides also create a domain named Procurement. A domain is deleted
-- only if its description carries the [sense-ontology-qs] marker that
-- ontology.sql wrote; any other domain is left alone and reported.
EXECUTE IMMEDIATE $$
DECLARE
  domains ARRAY DEFAULT ['Procurement', 'Logistics'];
  report STRING DEFAULT '';
BEGIN
  FOR i IN 0 TO ARRAY_SIZE(domains) - 1 DO
    LET d STRING := domains[i];
    LET filter STRING := OBJECT_CONSTRUCT('domainFilter', d)::STRING;
    LET info VARIANT := (SELECT PARSE_JSON(SYSTEM$GET_ONTOLOGY_DOMAIN(:d)));
    IF (info:error::BOOLEAN) THEN
      report := report || d || ': not found. ';
    ELSEIF (NOT CONTAINS(info:description::STRING, '[sense-ontology-qs]')) THEN
      report := report || d || ': not created by this lab, left in place. ';
    ELSE
      -- Representations, then relationships, then nodes: a domain with
      -- anything left in it cannot be deleted.
      LET r STRING;
      r := (SELECT SYSTEM$DELETE_ALL_ONTOLOGY_ASSOCIATIONS(:filter));
      r := (SELECT SYSTEM$DELETE_ALL_ONTOLOGY_ASSOCIATION_DRAFTS(:filter));
      r := (SELECT SYSTEM$DELETE_ALL_ONTOLOGY_RELATIONSHIPS(:filter));
      r := (SELECT SYSTEM$DELETE_ALL_ONTOLOGY_RELATIONSHIP_DRAFTS(:filter));
      r := (SELECT SYSTEM$DELETE_ALL_ONTOLOGY_TERM_DRAFTS(:filter));
      r := (SELECT SYSTEM$DELETE_ALL_ONTOLOGY_TERMS(:filter));
      r := (SELECT SYSTEM$DELETE_ONTOLOGY_DOMAIN(:d));
      report := report || d || ': ' || IFF(PARSE_JSON(r):error::BOOLEAN, 'delete failed: ' || r, 'deleted') || '. ';
    END IF;
  END FOR;
  RETURN report;
END;
$$;

-- -----------------------------------------------------------------------------
-- Part 2: database, warehouse and role (ACCOUNTADMIN)
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

DROP DATABASE IF EXISTS SENSE_ONTOLOGY_QS;
DROP WAREHOUSE IF EXISTS SENSE_ONTOLOGY_WH;
DROP ROLE IF EXISTS SENSE_ONTOLOGY_ROLE;

-- The Git API integration the workspace uses, if you created it.
DROP API INTEGRATION IF EXISTS GITHUB_SENSE_ONTOLOGY_LAB;
