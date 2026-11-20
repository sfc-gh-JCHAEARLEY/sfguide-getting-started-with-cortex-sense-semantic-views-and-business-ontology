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
-- Step 2: define, approve and connect the business terms in Business Ontology.
--
-- Two teams own the meaning here, so there are two domains:
--   Procurement  owns suppliers, purchase orders, spend and the official
--                on-time delivery rate used in performance reporting
--   Logistics    owns shipments, carriers and the carrier-reported on-time
--                rate it uses for carrier scorecards
--
-- Run this file top to bottom (Run All). To look at the drafts before they are
-- approved, run Parts 1 and 2 first, then the rest.
-- Domains are account-wide. Part 1 stops if either name is already taken.
-- =============================================================================
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;

-- -----------------------------------------------------------------------------
-- Part 1: one domain per team. The [sense-ontology-qs] marker lets
-- teardown.sql recognise the domains this lab created.
-- -----------------------------------------------------------------------------
EXECUTE IMMEDIATE $$
DECLARE
  taken EXCEPTION (-20001, 'A domain named Procurement or Logistics already exists in this account. If it is left over from this lab, run teardown.sql and then setup.sql. If another guide created it, run that guide''s clean up first.');
BEGIN
  IF (EXISTS (
        SELECT 1
        FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$GET_ONTOLOGY_SUMMARY()):domains)) d
        WHERE d.value:name::STRING IN ('Procurement', 'Logistics'))) THEN
    RAISE taken;
  END IF;
  RETURN 'Domain names are free';
END;
$$;

SELECT SYSTEM$CREATE_ONTOLOGY_DOMAIN('Procurement',
  'Suppliers, materials, purchase orders, spend and delivery performance. Steward: Procurement data steward. [sense-ontology-qs]');
SELECT SYSTEM$CREATE_ONTOLOGY_DOMAIN('Logistics',
  'Shipments, carriers and carrier scorecards. Steward: Logistics and carrier management. [sense-ontology-qs]');

-- -----------------------------------------------------------------------------
-- Part 2: draft the 12 nodes. A draft is a proposal: agents don't see it
-- until a steward approves it.
-- -----------------------------------------------------------------------------

-- Procurement: entities, a code term and a policy
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Supplier", "domainName": "Procurement", "itemKind": "ENTITY", "synonyms": ["Vendor", "Supply partner"], "description": "A company we buy materials from, recorded in the vendor master (LFA1). Each supplier has a Vendor Account Group that decides whether it counts as an active supplier.", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Material", "domainName": "Procurement", "itemKind": "ENTITY", "synonyms": ["Part", "Component"], "description": "A purchased item in the material master (MARA), identified by material number and grouped by material group.", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Purchase Order", "domainName": "Procurement", "itemKind": "ENTITY", "synonyms": ["PO", "PO line"], "description": "An order line placed with a Supplier for a Material (EKPO). Its net value is Procurement Spend.", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Vendor Account Group", "domainName": "Procurement", "itemKind": "TERM", "synonyms": ["KTOKK", "Vendor type"], "description": "The code on the vendor master that classifies a Supplier: ZSTR strategic partner, ZSTD standard vendor, ZPRB probationary. The full code list, and which codes count as active, live in the code table T077K. New codes are added there, not here.", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Probationary Vendor Exclusion", "domainName": "Procurement", "itemKind": "POLICY", "synonyms": [], "description": "Procurement policy: vendors in a probationary account group (ZPRB) are not active suppliers. They are excluded from the Supplier Count and from supplier KPIs until they are promoted.", "sourceType": "MANUAL"}');

-- Procurement: the official metrics and one look-alike
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Supplier Count", "domainName": "Procurement", "itemKind": "METRIC", "synonyms": ["Number of suppliers", "Active suppliers", "Active supplier count"], "description": "The official supplier count used in all reporting: the number of active suppliers, meaning vendors whose Vendor Account Group counts as active (ZSTR or ZSTD). Probationary vendors are excluded by policy. Counting vendor master records overstates it: use Vendor Record Count only for data maintenance.", "formula": "COUNT(DISTINCT vendor) WHERE account group counts as active", "formulaSource": "SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV", "exclusions": ["Vendor Account Group ZPRB (probationary)"], "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Vendor Record Count", "domainName": "Procurement", "itemKind": "METRIC", "synonyms": ["Vendor master record count"], "description": "Every vendor record on file, including probationary vendors. The vendor master data team uses it for maintenance. It is never the supplier count.", "formula": "COUNT(DISTINCT vendor)", "formulaSource": "SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Procurement Spend", "domainName": "Procurement", "itemKind": "METRIC", "synonyms": ["Spend", "Purchase spend", "Total spend"], "description": "Total net value of Purchase Order lines in USD, across every supplier, including probationary ones.", "formula": "SUM(net order value)", "formulaSource": "SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "On-Time Delivery Rate", "domainName": "Procurement", "itemKind": "METRIC", "synonyms": ["OTD", "On-time delivery", "Delivery performance"], "description": "The official on-time delivery rate used in performance reporting: the percent of delivered Shipments (status D) that arrived on or before the planned delivery date. It is measured from our own receipts. The rate carriers report about themselves is the Logistics team''s Carrier Reported On-Time Rate, which is not delivery performance.", "formula": "100 * delivered on or before planned date / delivered", "formulaSource": "SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV", "sourceType": "MANUAL"}');

-- Logistics: entities and the carrier scorecard metric
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Shipment", "domainName": "Logistics", "itemKind": "ENTITY", "synonyms": ["Delivery", "Inbound shipment"], "description": "An inbound delivery (LIKP) with a planned delivery date, an actual delivery date and a status: D delivered, T in transit, X delayed.", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Carrier", "domainName": "Logistics", "itemKind": "ENTITY", "synonyms": ["Forwarding agent", "Logistics provider"], "description": "A logistics provider that moves Shipments (LFA2). Each carrier reports its own on-time ratio.", "sourceType": "MANUAL"}');
SELECT SYSTEM$DRAFT_ONTOLOGY_TERM('{"name": "Carrier Reported On-Time Rate", "domainName": "Logistics", "itemKind": "METRIC", "synonyms": ["Carrier OTD", "Carrier self-reported on-time rate"], "description": "The average on-time ratio that carriers report about themselves, as a percent. The Logistics team uses it for carrier scorecards and contract negotiations. For delivery performance, use the Procurement team''s On-Time Delivery Rate.", "formula": "100 * AVG(carrier on-time ratio)", "formulaSource": "SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV", "sourceType": "MANUAL"}');

-- -----------------------------------------------------------------------------
-- Part 3: approve the drafts. Each team approves its own domain; in a real
-- account each domain's steward runs its line. The history read-back in Part 6
-- records who approved and with which role.
-- Expected: "approved": 9 for Procurement and "approved": 3 for Logistics.
-- -----------------------------------------------------------------------------
SELECT SYSTEM$APPROVE_ALL_ONTOLOGY_TERMS('[]', 'ACTIVE', '{"domain":"Procurement"}');
SELECT SYSTEM$APPROVE_ALL_ONTOLOGY_TERMS('[]', 'ACTIVE', '{"domain":"Logistics"}');

-- -----------------------------------------------------------------------------
-- Part 4: connect the nodes. Two relationships cross from Procurement to
-- Logistics: that is where the two teams' definitions meet.
-- -----------------------------------------------------------------------------
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Purchase Order', 'Procurement.Supplier', 'RELATED_TO', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Purchase Order', 'Procurement.Material', 'RELATED_TO', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Vendor Account Group', 'Procurement.Supplier', 'CLASSIFIES', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Supplier Count', 'Procurement.Supplier', 'MEASURES', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Supplier Count', 'Procurement.Vendor Record Count', 'HAS_VARIANT', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Probationary Vendor Exclusion', 'Procurement.Supplier Count', 'APPLIES_TO', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.Procurement Spend', 'Procurement.Purchase Order', 'MEASURES', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.On-Time Delivery Rate', 'Logistics.Shipment', 'MEASURES', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Procurement.On-Time Delivery Rate', 'Logistics.Carrier Reported On-Time Rate', 'HAS_VARIANT', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Logistics.Carrier', 'Logistics.Shipment', 'RELATED_TO', '', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_RELATIONSHIP('Logistics.Carrier Reported On-Time Rate', 'Logistics.Carrier', 'MEASURES', '', 'MANUAL');

-- -----------------------------------------------------------------------------
-- Part 5: link each node to the data that represents it. Each metric points at
-- the semantic view metric that computes it, so an agent that finds the
-- definition also finds the one place the number is calculated.
-- -----------------------------------------------------------------------------
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Supplier Count',
  '{"refType":"SEMANTIC_VIEW","fqn":"SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV","subObjectType":"METRIC","entityQualifier":"LFA1","subObjectName":"SUPPLIER_COUNT"}',
  'RELATED_SEMANTIC_VIEW', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Vendor Record Count',
  '{"refType":"SEMANTIC_VIEW","fqn":"SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV","subObjectType":"METRIC","entityQualifier":"LFA1","subObjectName":"VENDOR_RECORD_COUNT"}',
  'RELATED_SEMANTIC_VIEW', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Procurement Spend',
  '{"refType":"SEMANTIC_VIEW","fqn":"SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV","subObjectType":"METRIC","entityQualifier":"EKPO","subObjectName":"PROCUREMENT_SPEND"}',
  'RELATED_SEMANTIC_VIEW', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.On-Time Delivery Rate',
  '{"refType":"SEMANTIC_VIEW","fqn":"SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV","subObjectType":"METRIC","entityQualifier":"LIKP","subObjectName":"ON_TIME_DELIVERY_RATE"}',
  'RELATED_SEMANTIC_VIEW', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Logistics.Carrier Reported On-Time Rate',
  '{"refType":"SEMANTIC_VIEW","fqn":"SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV","subObjectType":"METRIC","entityQualifier":"LFA2","subObjectName":"CARRIER_REPORTED_ON_TIME_RATE"}',
  'RELATED_SEMANTIC_VIEW', 'MANUAL');

SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Supplier',
  '{"refType":"TABLE","fqn":"SENSE_ONTOLOGY_QS.SAP.LFA1","objectName":"LFA1"}', 'DESCRIBES', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Material',
  '{"refType":"TABLE","fqn":"SENSE_ONTOLOGY_QS.SAP.MARA","objectName":"MARA"}', 'DESCRIBES', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Purchase Order',
  '{"refType":"TABLE","fqn":"SENSE_ONTOLOGY_QS.SAP.EKPO","objectName":"EKPO"}', 'DESCRIBES', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Vendor Account Group',
  '{"refType":"TABLE","fqn":"SENSE_ONTOLOGY_QS.SAP.T077K","objectName":"T077K"}', 'DESCRIBES', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Procurement.Probationary Vendor Exclusion',
  '{"refType":"COLUMN","fqn":"SENSE_ONTOLOGY_QS.SAP.T077K","dimensionName":"EXCLUDE_FROM_ACTIVE_COUNT"}', 'DESCRIBES', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Logistics.Shipment',
  '{"refType":"TABLE","fqn":"SENSE_ONTOLOGY_QS.SAP.LIKP","objectName":"LIKP"}', 'DESCRIBES', 'MANUAL');
SELECT SYSTEM$CREATE_ONTOLOGY_ASSOCIATION('Logistics.Carrier',
  '{"refType":"TABLE","fqn":"SENSE_ONTOLOGY_QS.SAP.LFA2","objectName":"LFA2"}', 'DESCRIBES', 'MANUAL');

-- -----------------------------------------------------------------------------
-- Part 6: read it back. A call that returns "error": false has not necessarily
-- been saved, so count what the ontology actually holds (checks.sql CHECK 3
-- does the same with PASS/FAIL), then see who approved the official metric.
-- -----------------------------------------------------------------------------
SELECT d.value:name::STRING AS domain,
       d.value:termCount::INT AS nodes,
       d.value:draftCount::INT AS drafts
FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$GET_ONTOLOGY_SUMMARY()):domains)) d
WHERE d.value:name::STRING IN ('Procurement', 'Logistics')
ORDER BY 1;

-- The approval record: who changed the node, with which role, and when.
SELECT TO_TIMESTAMP_LTZ(e.value:createdOn::NUMBER, 3) AS changed_at,
       e.value:changeType::STRING AS change,
       e.value:beforeValue::STRING AS before_value,
       e.value:afterValue::STRING AS after_value,
       e.value:changedBy::STRING AS changed_by,
       e.value:changedByRole::STRING AS changed_by_role
FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$GET_ONTOLOGY_TERM_HISTORY('Procurement.Supplier Count', '{"kinds":["ITEM"]}')):events)) e
ORDER BY 1;
