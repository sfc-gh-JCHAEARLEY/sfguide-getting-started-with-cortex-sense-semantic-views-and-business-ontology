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
-- Step 1: calculate the metrics in a semantic view.
--
-- PROCUREMENT_SV covers 11 of the 17 tables. It computes each metric once, so
-- every tool and agent that queries it gets the same number. It holds both the
-- official metrics and their look-alikes, because some teams rely on the
-- look-alikes. Saying which one is official is the ontology's job (Step 2).
--
-- Six tables are deliberately left out of the view: QUAL_MATRIX, BSEG, COEP,
-- VBAP, KONV and T320 (storage locations). Cortex Sense finds them in Step 3.
-- =============================================================================
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;
USE SCHEMA SENSE_ONTOLOGY_QS.SAP;

CREATE OR REPLACE SEMANTIC VIEW PROCUREMENT_SV
TABLES (
  LFA1 AS SENSE_ONTOLOGY_QS.SAP.LFA1 PRIMARY KEY (LIFNR)
    WITH SYNONYMS = ('vendors', 'suppliers', 'vendor master') COMMENT = 'Vendor master data: one row per vendor record',
  T077K AS SENSE_ONTOLOGY_QS.SAP.T077K PRIMARY KEY (KTOKK) COMMENT = 'Vendor account groups (code table)',
  LFB1 AS SENSE_ONTOLOGY_QS.SAP.LFB1 PRIMARY KEY (LIFNR, VKONT) COMMENT = 'Vendor contract data',
  MARA AS SENSE_ONTOLOGY_QS.SAP.MARA PRIMARY KEY (MATNR)
    WITH SYNONYMS = ('materials', 'parts') COMMENT = 'Material master data',
  T023T AS SENSE_ONTOLOGY_QS.SAP.T023T PRIMARY KEY (MATKL) COMMENT = 'Material group texts (code table)',
  EKPO AS SENSE_ONTOLOGY_QS.SAP.EKPO PRIMARY KEY (EBELN, EBELP)
    WITH SYNONYMS = ('purchase orders', 'PO lines') COMMENT = 'Purchase order lines',
  T001W AS SENSE_ONTOLOGY_QS.SAP.T001W PRIMARY KEY (WERKS) COMMENT = 'Plants',
  LIKP AS SENSE_ONTOLOGY_QS.SAP.LIKP PRIMARY KEY (TKNUM)
    WITH SYNONYMS = ('shipments', 'deliveries') COMMENT = 'Inbound shipments',
  LFA2 AS SENSE_ONTOLOGY_QS.SAP.LFA2 PRIMARY KEY (TDLNR)
    WITH SYNONYMS = ('carriers', 'forwarding agents') COMMENT = 'Carriers (forwarding agents)',
  QALS AS SENSE_ONTOLOGY_QS.SAP.QALS PRIMARY KEY (PRUEFLOS) COMMENT = 'Quality inspection lots',
  STPO AS SENSE_ONTOLOGY_QS.SAP.STPO PRIMARY KEY (STLNR, IDNRK) COMMENT = 'Bill of materials items'
)
RELATIONSHIPS (
  LFA1 (KTOKK) REFERENCES T077K,
  MARA (MATKL) REFERENCES T023T,
  LFB1 (LIFNR) REFERENCES LFA1,
  EKPO (LIFNR) REFERENCES LFA1,
  EKPO (MATNR) REFERENCES MARA,
  EKPO (WERKS) REFERENCES T001W,
  LIKP (TDLNR) REFERENCES LFA2,
  LIKP (WERKS_DST) REFERENCES T001W,
  QALS (MATNR) REFERENCES MARA,
  STPO (IDNRK) REFERENCES MARA
)
FACTS (
  MARA.STPRS AS STPRS COMMENT = 'Standard price',
  EKPO.NETWR AS NETWR COMMENT = 'Net order value (USD)',
  EKPO.MENGE AS MENGE COMMENT = 'Purchase order quantity',
  LIKP.MENGE AS MENGE COMMENT = 'Delivery quantity',
  LIKP.FRTCO AS FRTCO COMMENT = 'Freight cost',
  LFA2.OTRAT AS OTRAT COMMENT = 'On-time ratio self-reported by the carrier (0 to 1)',
  LFA2.LZEIT AS LZEIT COMMENT = 'Transit time (days)',
  QALS.QAESSION AS QAESSION COMMENT = 'Defect rate',
  LFB1.JWERT AS JWERT COMMENT = 'Annual contract value',
  STPO.MENGE AS MENGE COMMENT = 'Component quantity',
  STPO.STUFE AS STUFE COMMENT = 'BOM level'
)
DIMENSIONS (
  LFA1.LIFNR AS LIFNR COMMENT = 'Vendor number',
  LFA1.NAME1 AS NAME1 WITH SYNONYMS = ('vendor name', 'supplier name') COMMENT = 'Vendor name',
  LFA1.ORT01 AS ORT01 COMMENT = 'City',
  LFA1.LAND1 AS LAND1 WITH SYNONYMS = ('country') COMMENT = 'Country code',
  LFA1.KTOKK AS KTOKK WITH SYNONYMS = ('account group', 'vendor type') COMMENT = 'Vendor account group: ZSTR strategic, ZSTD standard, ZPRB probationary',
  LFA1.ZTERM AS ZTERM COMMENT = 'Payment terms key',
  LFA1.IS_ACTIVE_SUPPLIER AS NOT T077K.EXCLUDE_FROM_ACTIVE_COUNT
    COMMENT = 'TRUE when the vendor account group counts toward the active supplier count',
  T077K.KTOKK AS KTOKK COMMENT = 'Account group',
  T077K.TXT30 AS TXT30 COMMENT = 'Account group description',
  T077K.EXCLUDE_FROM_ACTIVE_COUNT AS EXCLUDE_FROM_ACTIVE_COUNT COMMENT = 'TRUE if vendors in this group are excluded from the active supplier count',
  LFB1.VKONT AS VKONT COMMENT = 'Contract account',
  LFB1.VTART AS VTART COMMENT = 'Contract type',
  LFB1.DTEND AS DTEND COMMENT = 'Validity end date',
  MARA.MATNR AS MATNR COMMENT = 'Material number',
  MARA.MAKTX AS MAKTX WITH SYNONYMS = ('material name') COMMENT = 'Material description',
  MARA.MATKL AS MATKL COMMENT = 'Material group',
  T023T.WGBEZ AS WGBEZ WITH SYNONYMS = ('material group name') COMMENT = 'Material group description',
  EKPO.EBELN AS EBELN COMMENT = 'Purchase order number',
  EKPO.EBELP AS EBELP COMMENT = 'Purchase order item number',
  EKPO.LIFNR AS LIFNR COMMENT = 'Vendor number',
  EKPO.MATNR AS MATNR COMMENT = 'Material number',
  EKPO.WERKS AS WERKS COMMENT = 'Plant',
  EKPO.STATU AS STATU COMMENT = 'Purchase order status',
  EKPO.BEDAT AS BEDAT WITH SYNONYMS = ('order date') COMMENT = 'Purchase order date',
  T001W.WERKS AS WERKS COMMENT = 'Plant',
  T001W.NAME1 AS NAME1 WITH SYNONYMS = ('plant name') COMMENT = 'Plant name',
  T001W.REGIO AS REGIO COMMENT = 'Region',
  LIKP.TKNUM AS TKNUM COMMENT = 'Shipment number',
  LIKP.TDLNR AS TDLNR COMMENT = 'Carrier (forwarding agent)',
  LIKP.MATNR AS MATNR COMMENT = 'Material number',
  LIKP.STATU AS STATU COMMENT = 'Shipment status: D delivered, T in transit, X delayed',
  LIKP.LFDAT AS LFDAT WITH SYNONYMS = ('planned delivery date') COMMENT = 'Planned delivery date',
  LIKP.WADAT AS WADAT WITH SYNONYMS = ('actual delivery date') COMMENT = 'Actual delivery date',
  LIKP.WERKS_DST AS WERKS_DST COMMENT = 'Destination plant',
  LFA2.TDLNR AS TDLNR COMMENT = 'Carrier number',
  LFA2.NAME1 AS NAME1 WITH SYNONYMS = ('carrier name') COMMENT = 'Carrier name',
  LFA2.VSART AS VSART COMMENT = 'Transport type: 01 ocean, 02 FTL, 03 air, 04 intermodal, 05 LTL',
  QALS.PRUEFLOS AS PRUEFLOS COMMENT = 'Inspection lot',
  QALS.MATNR AS MATNR COMMENT = 'Material number',
  QALS.VCODE AS VCODE COMMENT = 'Usage decision code',
  STPO.STLNR AS STLNR COMMENT = 'Bill of materials',
  STPO.IDNRK AS IDNRK COMMENT = 'BOM component'
)
METRICS (
  LFA1.SUPPLIER_COUNT AS COUNT(DISTINCT IFF(LFA1.IS_ACTIVE_SUPPLIER, LFA1.LIFNR, NULL))
    WITH SYNONYMS = ('number of suppliers', 'active suppliers', 'active supplier count')
    COMMENT = 'Official supplier count: vendors whose account group counts as active. Probationary vendors are excluded.',
  LFA1.VENDOR_RECORD_COUNT AS COUNT(DISTINCT LFA1.LIFNR)
    WITH SYNONYMS = ('vendor master record count')
    COMMENT = 'Every vendor record on file, including probationary vendors. Used for vendor master data maintenance.',
  LIKP.ON_TIME_DELIVERY_RATE AS ROUND(100 * COUNT_IF(LIKP.STATU = 'D' AND LIKP.WADAT <= LIKP.LFDAT) / NULLIF(COUNT_IF(LIKP.STATU = 'D'), 0), 2)
    WITH SYNONYMS = ('on-time delivery', 'OTD', 'delivery performance')
    COMMENT = 'Percent of delivered shipments (status D) that arrived on or before the planned delivery date.',
  LFA2.CARRIER_REPORTED_ON_TIME_RATE AS ROUND(100 * AVG(LFA2.OTRAT), 2)
    WITH SYNONYMS = ('carrier OTD', 'carrier self-reported on-time rate')
    COMMENT = 'Average on-time ratio that carriers report about themselves, as a percent. Used for carrier scorecards.',
  EKPO.PROCUREMENT_SPEND AS SUM(EKPO.NETWR)
    WITH SYNONYMS = ('spend', 'purchase spend', 'total spend')
    COMMENT = 'Total net value of purchase order lines (USD), across every supplier.'
)
COMMENT = 'SAP procurement: vendors, materials, purchase orders, shipments, carriers, inspections and BOMs, with the procurement metrics';

-- Query the official metrics and their look-alikes side by side.
-- Expected: SUPPLIER_COUNT 14, VENDOR_RECORD_COUNT 15.
SELECT * FROM SEMANTIC_VIEW(
  SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV
  METRICS LFA1.SUPPLIER_COUNT, LFA1.VENDOR_RECORD_COUNT
);

-- Expected: ON_TIME_DELIVERY_RATE 66.67, CARRIER_REPORTED_ON_TIME_RATE 90.00.
SELECT
  (SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LIKP.ON_TIME_DELIVERY_RATE)) AS on_time_delivery_rate,
  (SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS LFA2.CARRIER_REPORTED_ON_TIME_RATE)) AS carrier_reported_on_time_rate;

-- Expected: PROCUREMENT_SPEND 1353690.00.
SELECT * FROM SEMANTIC_VIEW(SENSE_ONTOLOGY_QS.SAP.PROCUREMENT_SV METRICS EKPO.PROCUREMENT_SPEND);
