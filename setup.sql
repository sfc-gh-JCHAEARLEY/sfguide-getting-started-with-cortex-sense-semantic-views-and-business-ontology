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
-- Getting Started with Cortex Sense, Semantic Views, and Business Ontology
-- Setup script: run this once, top to bottom (Run All).
--
-- A manufacturer runs procurement on SAP. Its tables use SAP's short German
-- names (LFA1 is the vendor master, LIKP holds shipments), and two of its
-- numbers have look-alikes that give a different answer:
--   - the vendor master has 15 records, but the official supplier count is 14
--   - carriers report a 90% on-time rate, but the official rate is 66.67%
--
-- The data is synthetic and fixed, so everyone gets the same rows and answers.
-- Re-running this script resets the data. It does not touch ontology domains
-- or Cortex Sense contexts; teardown.sql removes those.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Part 1 (ACCOUNTADMIN): create a lab role that owns only what this lab needs.
-- You and CoCo work as SENSE_ONTOLOGY_ROLE for the rest of the lab.
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS SENSE_ONTOLOGY_ROLE
  COMMENT = 'Lab role for the Cortex Sense and Business Ontology quickstart';
GRANT ROLE SENSE_ONTOLOGY_ROLE TO ROLE SYSADMIN;

-- Quoted so usernames with dots, @ signs, or lowercase letters work
SET MY_USER = '"' || CURRENT_USER() || '"';
GRANT ROLE SENSE_ONTOLOGY_ROLE TO USER IDENTIFIER($MY_USER);

-- CoCo and Cortex Agents need CORTEX_USER. Building a Cortex Sense context needs
-- CORTEX_SENSE_USER. Creating an ontology domain needs CREATE ONTOLOGY DOMAIN.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SENSE_ONTOLOGY_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_SENSE_USER TO ROLE SENSE_ONTOLOGY_ROLE;
GRANT CREATE ONTOLOGY DOMAIN ON ACCOUNT TO ROLE SENSE_ONTOLOGY_ROLE;

CREATE WAREHOUSE IF NOT EXISTS SENSE_ONTOLOGY_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
GRANT USAGE, OPERATE ON WAREHOUSE SENSE_ONTOLOGY_WH TO ROLE SENSE_ONTOLOGY_ROLE;

-- Re-running this script resets the lab data: it replaces SENSE_ONTOLOGY_QS.
CREATE OR REPLACE DATABASE SENSE_ONTOLOGY_QS;
GRANT OWNERSHIP ON DATABASE SENSE_ONTOLOGY_QS TO ROLE SENSE_ONTOLOGY_ROLE;

-- -----------------------------------------------------------------------------
-- Part 2 (SENSE_ONTOLOGY_ROLE): load the SAP procurement tables.
-- -----------------------------------------------------------------------------
USE ROLE SENSE_ONTOLOGY_ROLE;
USE WAREHOUSE SENSE_ONTOLOGY_WH;

CREATE SCHEMA IF NOT EXISTS SENSE_ONTOLOGY_QS.SAP
  COMMENT = 'Synthetic SAP procurement data for the Cortex Sense and Business Ontology quickstart';
USE SCHEMA SENSE_ONTOLOGY_QS.SAP;

CREATE OR REPLACE TABLE LFA1 (
    LIFNR VARCHAR(10) NOT NULL PRIMARY KEY, -- Vendor number
    NAME1 VARCHAR(100),                     -- Vendor name
    ORT01 VARCHAR(50),                      -- City
    LAND1 VARCHAR(5),                       -- Country code
    STCD1 VARCHAR(30),                      -- Tax ID
    KRAUS VARCHAR(15),                      -- DUNS number (SAP uses KRAUS field)
    KTOKK VARCHAR(10),                      -- Account group (ZSTR=Strategic, ZSTD=Standard, ZPRB=Probationary)
    ZTERM VARCHAR(10)                       -- Payment terms
);

INSERT INTO LFA1 VALUES
    ('V10045', 'SHENZHEN ELECTRONICS CO. LTD', 'Shenzhen', 'CN', '91440300MA5FPQG72B', '54-138-7209', 'ZSTR', 'NET45'),
    ('V10078', 'PACIFIC METALS CORPORATION', 'Long Beach', 'US', '95-4821073', '07-823-6541', 'ZSTD', 'NET30'),
    ('V10089', 'ADVANCED SILICON SOLUTIONS INC.', 'Santa Clara', 'US', '77-3920184', '15-738-2904', 'ZSTR', 'NET45'),
    ('V10098', 'TOKYO SENSOR TECHNOLOGIES K.K.', 'Tokyo', 'JP', 'JP5010401098234', '71-385-6249', 'ZSTD', 'NET45'),
    ('V10102', 'RHINE CHEMICAL GMBH', 'Ludwigshafen', 'DE', 'DE283741956', '31-592-4780', 'ZSTR', 'NET30'),
    ('V10134', 'BAYERN KUNSTSTOFFE AG', 'Munich', 'DE', 'DE192847563', '44-591-7823', 'ZSTD', 'NET30'),
    ('V10156', 'OSAKA PRECISION INSTRUMENTS CO.', 'Osaka', 'JP', 'JP8120001098765', '69-247-1058', 'ZSTR', 'NET60'),
    ('V10167', 'GUANGZHOU RARE EARTH MATERIALS LTD', 'Guangzhou', 'CN', '91440101MA9URXG44N', '63-904-2175', 'ZSTD', 'NET60'),
    ('V10190', 'SCHWARZWALD PRECISION TOOLS GMBH', 'Freiburg', 'DE', 'DE314725890', '37-462-8105', 'ZSTD', 'NET30'),
    ('V10201', 'MONTERREY PACKAGING S.A. DE C.V.', 'Monterrey', 'MX', 'MPS040512QR7', '82-461-3097', 'ZSTD', 'NET30'),
    ('V10223', 'LONE STAR INDUSTRIAL SUPPLY CO.', 'Houston', 'US', '76-1948302', '28-617-4930', 'ZSTD', 'NET30'),
    ('V10245', 'PUEBLA CORRUGATED PRODUCTS SA', 'Puebla', 'MX', 'PCP090318HV5', NULL, 'ZPRB', 'NET30'),
    ('V10278', 'JIANGSU COPPER ALLOYS CO. LTD', 'Nanjing', 'CN', '91320100MA1MPKG28R', '56-813-4027', 'ZSTD', 'NET45'),
    ('V10312', 'ACME LOGISTICS INC', 'Chicago', 'US', '36-4829107', '09-284-5716', 'ZSTD', 'NET30'),
    ('V10334', 'NAGOYA STEEL WORKS LTD', 'Nagoya', 'JP', 'JP3180001054321', '48-729-3061', 'ZSTD', 'NET60');

-- =====================================================
-- LFA2: Carriers (Forwarding Agents)
-- =====================================================
CREATE OR REPLACE TABLE LFA2 (
    TDLNR VARCHAR(10) NOT NULL PRIMARY KEY, -- Forwarding agent number
    NAME1 VARCHAR(100),                     -- Carrier name
    VSART VARCHAR(5),                       -- Transport type (01=Ocean, 02=FTL, 03=Air, 04=Intermodal, 05=LTL)
    LZEIT NUMBER(38,0),                     -- Transit time (days)
    OTRAT NUMBER(4,2)                       -- On-time rate (carrier self-reported)
);

INSERT INTO LFA2 VALUES
    ('CAR-001', 'TransGlobal Freight Inc.', '01', 28, 0.87),
    ('CAR-002', 'EuroHaul Logistics GmbH', '02', 4, 0.94),
    ('CAR-003', 'SkyBridge Air Cargo', '03', 3, 0.96),
    ('CAR-004', 'Pacific Intermodal Corp.', '04', 18, 0.91),
    ('CAR-005', 'MexLine Transportes S.A.', '05', 6, 0.83),
    ('CAR-006', 'Shenzhen Coastal Shipping Ltd.', '01', 22, 0.89);

-- =====================================================
-- MARA: Material Master
-- =====================================================
CREATE OR REPLACE TABLE MARA (
    MATNR VARCHAR(10) NOT NULL PRIMARY KEY, -- Material number
    MAKTX VARCHAR(100),                     -- Material description
    MATKL VARCHAR(5),                       -- Material group code
    STPRS NUMBER(10,2)                      -- Standard price
);

INSERT INTO MARA VALUES
    ('ASSY-001', 'Sensor Module Assembly', '048', 45.00),
    ('ASSY-002', 'Power Distribution Board', '048', 32.00),
    ('ASSY-003', 'Ruggedized Enclosure', '048', 380.00),
    ('ASSY-004', 'Integrated System Module', '048', 520.00),
    ('MAT-001', 'Multilayer Ceramic Capacitor 100nF', '043', 0.12),
    ('MAT-002', 'Epoxy Resin ER-4500', '044', 18.50),
    ('MAT-003', 'Aluminum Sheet 6061-T6 2mm', '045', 42.00),
    ('MAT-004', 'MEMS Accelerometer IC', '043', 3.75),
    ('MAT-005', 'Corrugated Box 400x300x200mm', '046', 1.85),
    ('MAT-006', 'Isopropyl Alcohol 99.7%', '044', 5.20),
    ('MAT-007', 'Copper Alloy Strip C17200', '045', 28.90),
    ('MAT-008', 'ARM Cortex-M4 Microcontroller', '043', 6.40),
    ('MAT-009', 'Anti-Static Foam Insert', '046', 0.95),
    ('MAT-010', 'Stainless Steel Rod 304L 10mm', '045', 12.30),
    ('MAT-011', 'Neodymium Rare Earth Magnet N52', '047', 2.10),
    ('MAT-012', 'Silicone Thermal Paste TG-7', '044', 85.00),
    ('MAT-013', 'Power MOSFET IRF540N', '043', 0.85),
    ('MAT-014', 'Polyethylene Stretch Wrap 500mm', '046', 14.50),
    ('MAT-015', 'Titanium Alloy Ti-6Al-4V Plate', '045', 120.00),
    ('MAT-016', 'Fiber Optic Transceiver SFP+ 10G', '043', 22.00),
    ('MAT-017', 'Hydrochloric Acid 37% ACS Grade', '044', 8.75),
    ('MAT-018', 'Precision Ball Bearing 6205-2RS', '047', 4.50),
    ('MAT-019', 'Carbon Fiber Sheet 3K Twill 2mm', '047', 65.00),
    ('MAT-020', 'ESD Protective Bag 200x300mm', '046', 0.35);

-- =====================================================
-- T001W: Plants
-- =====================================================
CREATE OR REPLACE TABLE T001W (
    WERKS VARCHAR(10) NOT NULL PRIMARY KEY, -- Plant code
    NAME1 VARCHAR(100),                     -- Plant name
    REGIO VARCHAR(20)                       -- Region
);

INSERT INTO T001W VALUES
    ('PLT-001', 'Austin Manufacturing Center', 'AMERICAS'),
    ('PLT-002', 'Stuttgart Assembly Plant', 'EMEA'),
    ('PLT-003', 'Shanghai Production Facility', 'APAC'),
    ('PLT-004', 'Monterrey Operations Plant', 'AMERICAS'),
    ('PLT-005', 'Nagoya Precision Works', 'APAC');

-- =====================================================
-- T320: Storage Locations (Warehouses)
-- =====================================================
CREATE OR REPLACE TABLE T320 (
    LGORT VARCHAR(10) NOT NULL PRIMARY KEY, -- Storage location
    LGOBE VARCHAR(100),                     -- Storage location description
    WERKS VARCHAR(10),                      -- Plant
    LKAPA NUMBER(5,1)                       -- Capacity utilization %
);

INSERT INTO T320 VALUES
    ('WH-001', 'Austin Raw Materials Hub', 'PLT-001', 72.5),
    ('WH-002', 'Austin Finished Goods Depot', 'PLT-001', 61.0),
    ('WH-003', 'Stuttgart Inbound Logistics Center', 'PLT-002', 88.3),
    ('WH-004', 'Shanghai Bonded Warehouse', 'PLT-003', 55.2),
    ('WH-005', 'Shanghai Distribution Center', 'PLT-003', 79.8),
    ('WH-006', 'Monterrey Cross-Dock Facility', 'PLT-004', 42.1),
    ('WH-007', 'Nagoya JIT Storage', 'PLT-005', 91.7),
    ('WH-008', 'Houston Regional Distribution Hub', 'PLT-001', 67.4);

-- =============================================================================
-- TRANSACTIONS
-- =============================================================================

-- =====================================================
-- EKPO: Purchase Order Items
-- =====================================================
CREATE OR REPLACE TABLE EKPO (
    EBELN VARCHAR(20) NOT NULL,             -- PO number
    EBELP VARCHAR(5) NOT NULL,              -- PO item number
    LIFNR VARCHAR(10),                      -- Vendor number
    MATNR VARCHAR(10),                      -- Material number
    WERKS VARCHAR(10),                      -- Plant
    BEDAT DATE,                             -- Order date
    MENGE NUMBER(38,0),                     -- Quantity
    NETWR NUMBER(12,2),                     -- Net value (USD)
    STATU VARCHAR(5),                       -- Status (O=Open, C=Closed, R=Received)
    PRIMARY KEY (EBELN, EBELP)
);

INSERT INTO EKPO VALUES
    ('PO-2024-001', '10', 'V10045', 'MAT-001', 'PLT-003', '2024-09-15', 100000, 11000.00, 'R'),
    ('PO-2024-002', '10', 'V10078', 'MAT-002', 'PLT-002', '2024-09-20', 5000, 89000.00, 'R'),
    ('PO-2024-003', '10', 'V10089', 'MAT-003', 'PLT-001', '2024-10-01', 1200, 48600.00, 'R'),
    ('PO-2024-004', '10', 'V10098', 'MAT-004', 'PLT-005', '2024-10-10', 20000, 72000.00, 'R'),
    ('PO-2024-005', '10', 'V10102', 'MAT-005', 'PLT-004', '2024-10-15', 15000, 26250.00, 'R'),
    ('PO-2024-006', '10', 'V10134', 'MAT-008', 'PLT-001', '2024-11-01', 10000, 62000.00, 'R'),
    ('PO-2024-007', '10', 'V10156', 'MAT-002', 'PLT-002', '2024-11-10', 3000, 57300.00, 'R'),
    ('PO-2024-008', '10', 'V10167', 'MAT-011', 'PLT-003', '2024-11-15', 50000, 97500.00, 'R'),
    ('PO-2024-009', '10', 'V10278', 'MAT-007', 'PLT-003', '2024-12-01', 2000, 55000.00, 'R'),
    ('PO-2024-010', '10', 'V10334', 'MAT-010', 'PLT-005', '2024-12-05', 5000, 59000.00, 'R'),
    ('PO-2024-011', '10', 'V10102', 'MAT-014', 'PLT-004', '2024-11-20', 800, 11040.00, 'R'),
    ('PO-2024-012', '10', 'V10201', 'MAT-004', 'PLT-001', '2024-12-10', 8000, 30400.00, 'O'),
    ('PO-2025-001', '10', 'V10045', 'MAT-013', 'PLT-003', '2025-01-10', 50000, 41000.00, 'R'),
    ('PO-2025-002', '10', 'V10201', 'MAT-016', 'PLT-005', '2025-01-20', 4000, 84000.00, 'R'),
    ('PO-2025-003', '10', 'V10190', 'MAT-006', 'PLT-001', '2025-02-01', 10000, 49000.00, 'R'),
    ('PO-2025-004', '10', 'V10312', 'MAT-018', 'PLT-002', '2025-02-15', 8000, 34400.00, 'R'),
    ('PO-2025-005', '10', 'V10089', 'MAT-015', 'PLT-001', '2025-03-01', 300, 34500.00, 'R'),
    ('PO-2025-006', '10', 'V10134', 'MAT-008', 'PLT-001', '2025-03-15', 15000, 93000.00, 'O'),
    ('PO-2025-007', '10', 'V10078', 'MAT-017', 'PLT-002', '2025-04-01', 8000, 67200.00, 'O'),
    ('PO-2025-008', '10', 'V10223', 'MAT-005', 'PLT-004', '2025-04-05', 20000, 33000.00, 'O'),
    ('PO-2025-009', '10', 'V10098', 'MAT-004', 'PLT-005', '2025-04-10', 25000, 90000.00, 'O'),
    ('PO-2025-010', '10', 'V10167', 'MAT-011', 'PLT-003', '2025-04-12', 40000, 80000.00, 'O'),
    ('PO-2025-011', '10', 'V10045', 'MAT-001', 'PLT-001', '2025-04-15', 200000, 22000.00, 'O'),
    ('PO-2025-012', '10', 'V10278', 'MAT-007', 'PLT-003', '2025-04-16', 3000, 84000.00, 'O'),
    ('PO-2025-013', '10', 'V10245', 'MAT-009', 'PLT-001', '2025-03-01', 25000, 22500.00, 'R');

-- =====================================================
-- LIKP: Shipments
-- =====================================================
CREATE OR REPLACE TABLE LIKP (
    TKNUM VARCHAR(10) NOT NULL PRIMARY KEY, -- Shipment number
    TDLNR VARCHAR(10),                      -- Forwarding agent (carrier)
    LGORT_SRC VARCHAR(10),                  -- Source storage location (origin warehouse)
    WERKS_DST VARCHAR(10),                  -- Destination plant
    MATNR VARCHAR(10),                      -- Material
    MENGE NUMBER(38,0),                     -- Quantity
    LFDAT DATE,                             -- Expected arrival
    WADAT DATE,                             -- Actual arrival
    FRTCO NUMBER(10,2),                     -- Freight cost
    STATU VARCHAR(5)                        -- Status (D=Delivered, T=In Transit, X=Delayed)
);

INSERT INTO LIKP VALUES
    ('SHP-001', 'CAR-006', 'WH-004', 'PLT-001', 'MAT-001', 100000, '2024-10-10', '2024-10-08', 2800.00, 'D'),
    ('SHP-002', 'CAR-002', 'WH-003', 'PLT-002', 'MAT-002', 5000, '2024-09-26', '2024-09-25', 1200.00, 'D'),
    ('SHP-003', 'CAR-003', 'WH-008', NULL, 'MAT-003', 1200, '2024-10-06', '2024-10-06', 3500.00, 'D'),
    ('SHP-004', 'CAR-004', 'WH-007', 'PLT-005', 'MAT-004', 20000, '2024-11-02', '2024-11-05', 4200.00, 'D'),
    ('SHP-005', 'CAR-005', 'WH-006', 'PLT-004', 'MAT-005', 15000, '2024-10-23', '2024-10-22', 850.00, 'D'),
    ('SHP-006', 'CAR-003', 'WH-001', NULL, 'MAT-008', 10000, '2024-11-11', '2024-11-11', 5100.00, 'D'),
    ('SHP-007', 'CAR-001', 'WH-004', NULL, 'MAT-011', 50000, '2024-12-18', '2024-12-22', 3100.00, 'D'),
    ('SHP-008', 'CAR-006', 'WH-005', NULL, 'MAT-007', 2000, '2024-12-27', '2024-12-26', 1900.00, 'D'),
    ('SHP-009', 'CAR-002', 'WH-003', 'PLT-002', 'MAT-018', 8000, '2025-02-22', '2025-02-21', 980.00, 'D'),
    ('SHP-010', 'CAR-004', 'WH-007', NULL, 'MAT-016', 4000, '2025-02-12', '2025-02-14', 3800.00, 'D'),
    ('SHP-011', 'CAR-001', 'WH-008', NULL, 'MAT-006', 10000, '2025-03-05', '2025-03-08', 2400.00, 'D'),
    ('SHP-012', 'CAR-003', 'WH-001', 'PLT-001', 'MAT-015', 300, '2025-03-23', '2025-03-23', 1800.00, 'D'),
    ('SHP-013', 'CAR-006', 'WH-004', 'PLT-003', 'MAT-013', 50000, '2025-02-06', '2025-02-04', 2200.00, 'D'),
    ('SHP-014', 'CAR-005', 'WH-006', 'PLT-004', 'MAT-014', 800, '2024-11-28', '2024-11-30', 450.00, 'D'),
    ('SHP-015', 'CAR-002', 'WH-003', 'PLT-002', 'MAT-002', 3000, '2025-03-29', '2025-03-28', 1100.00, 'D'),
    ('SHP-016', 'CAR-001', 'WH-005', NULL, 'MAT-011', 40000, '2025-05-12', NULL, 3050.00, 'T'),
    ('SHP-017', 'CAR-004', 'WH-007', 'PLT-005', 'MAT-004', 25000, '2025-05-03', NULL, 4500.00, 'T'),
    ('SHP-018', 'CAR-003', 'WH-001', NULL, 'MAT-008', 8000, '2025-04-13', NULL, 4800.00, 'X'),
    ('SHP-019', 'CAR-006', 'WH-004', NULL, 'MAT-007', 3000, '2025-05-10', NULL, 2600.00, 'T'),
    ('SHP-020', 'CAR-005', 'WH-006', 'PLT-004', 'MAT-005', 20000, '2025-04-14', NULL, 920.00, 'X');

-- =====================================================
-- LFB1: Vendor Contracts
-- =====================================================
CREATE OR REPLACE TABLE LFB1 (
    LIFNR VARCHAR(10) NOT NULL,             -- Vendor
    VKONT VARCHAR(10) NOT NULL,             -- Contract number
    VTART VARCHAR(5),                       -- Contract type (M=Master, F=Framework, S=Spot)
    DTEND DATE,                             -- Expiration date
    JWERT NUMBER(12,2),                     -- Annual value
    PRIMARY KEY (LIFNR, VKONT)
);

INSERT INTO LFB1 VALUES
    ('V10045', 'CTR-001', 'M', '2026-12-31', 4500000.00),
    ('V10078', 'CTR-002', 'M', '2026-06-30', 3200000.00),
    ('V10089', 'CTR-003', 'F', '2026-03-31', 2800000.00),
    ('V10098', 'CTR-004', 'M', '2027-12-31', 5200000.00),
    ('V10102', 'CTR-005', 'F', '2025-05-31', 450000.00),
    ('V10134', 'CTR-006', 'M', '2027-02-28', 7000000.00),
    ('V10156', 'CTR-007', 'F', '2025-12-31', 1200000.00),
    ('V10167', 'CTR-008', 'S', '2025-09-30', 980000.00),
    ('V10190', 'CTR-015', 'F', '2025-07-31', 600000.00),
    ('V10201', 'CTR-009', 'M', '2026-03-31', 3800000.00),
    ('V10223', 'CTR-014', 'S', '2025-07-15', 250000.00),
    ('V10245', 'CTR-010', 'F', '2025-12-31', 2000000.00),
    ('V10278', 'CTR-011', 'M', '2026-05-31', 1500000.00),
    ('V10312', 'CTR-012', 'F', '2025-12-31', 800000.00),
    ('V10334', 'CTR-013', 'M', '2026-09-30', 3500000.00);

-- =====================================================
-- QALS: Inspection Lots
-- =====================================================
CREATE OR REPLACE TABLE QALS (
    PRUEFLOS VARCHAR(10) NOT NULL PRIMARY KEY, -- Inspection lot
    MATNR VARCHAR(10),                         -- Material
    QAESSION NUMBER(6,3),                      -- Defect rate
    VCODE VARCHAR(5)                           -- Disposition (A=Accepted, R=Rejected, C=Conditional)
);

INSERT INTO QALS VALUES
    ('INS-001', 'MAT-001', 0.006, 'A'),
    ('INS-002', 'MAT-002', 0.060, 'C'),
    ('INS-003', 'MAT-003', 0.001, 'A'),
    ('INS-004', 'MAT-004', 0.150, 'A'),
    ('INS-005', 'MAT-005', 0.011, 'A'),
    ('INS-006', 'MAT-006', 0.005, 'A'),
    ('INS-007', 'MAT-007', 0.050, 'C'),
    ('INS-008', 'MAT-008', 0.000, 'A'),
    ('INS-009', 'MAT-001', 0.010, 'A'),
    ('INS-010', 'MAT-003', 0.002, 'A');

-- =============================================================================
-- STRUCTURE
-- =============================================================================

-- =====================================================
-- STPO: BOM Items
-- =====================================================
CREATE OR REPLACE TABLE STPO (
    STLNR VARCHAR(10) NOT NULL,             -- BOM number
    IDNRK VARCHAR(10) NOT NULL,             -- Component material
    MENGE NUMBER(10,3),                     -- Quantity per unit
    STUFE NUMBER(38,0),                     -- BOM level
    PRIMARY KEY (STLNR, IDNRK)
);

INSERT INTO STPO VALUES
    ('ASSY-001', 'MAT-001', 10.000, 1),
    ('ASSY-001', 'MAT-004', 2.000, 1),
    ('ASSY-001', 'MAT-008', 1.000, 1),
    ('ASSY-001', 'MAT-012', 0.050, 1),
    ('ASSY-002', 'MAT-001', 20.000, 1),
    ('ASSY-002', 'MAT-007', 0.500, 1),
    ('ASSY-002', 'MAT-013', 4.000, 1),
    ('ASSY-003', 'ASSY-001', 1.000, 1),
    ('ASSY-003', 'ASSY-002', 1.000, 1),
    ('ASSY-003', 'MAT-003', 2.000, 1),
    ('ASSY-003', 'MAT-015', 0.300, 1),
    ('ASSY-003', 'MAT-019', 1.000, 1),
    ('ASSY-004', 'ASSY-003', 1.000, 1),
    ('ASSY-004', 'MAT-016', 2.000, 1),
    ('ASSY-004', 'MAT-018', 4.000, 1);

-- =====================================================
-- QUAL_MATRIX: Alternate Supplier Qualifications
-- (Quality engineering data)
-- =====================================================
CREATE OR REPLACE TABLE QUAL_MATRIX (
    MATNR VARCHAR(10) NOT NULL,             -- Material number
    LIFNR VARCHAR(10) NOT NULL,             -- Vendor number
    QUAL_STATUS VARCHAR(10),                -- APPROVED, PENDING, EXPIRED, REJECTED
    QUAL_DATE DATE,                         -- Qualification date
    PRIMARY KEY (MATNR, LIFNR)
);

INSERT INTO QUAL_MATRIX VALUES
    ('MAT-001', 'V10045', 'APPROVED', '2023-06-15'),
    ('MAT-001', 'V10048', 'APPROVED', '2024-01-20'),
    ('MAT-001', 'V10052', 'PENDING', '2025-03-01'),
    ('MAT-002', 'V10054', 'APPROVED', '2023-07-01'),
    ('MAT-002', 'V10056', 'APPROVED', '2024-03-10'),
    ('MAT-003', 'V10053', 'APPROVED', '2023-04-01'),
    ('MAT-003', 'V10060', 'APPROVED', '2024-11-01'),
    ('MAT-004', 'V10055', 'APPROVED', '2023-09-01'),
    ('MAT-004', 'V10057', 'APPROVED', '2024-07-15'),
    ('MAT-005', 'V10057', 'APPROVED', '2024-08-20'),
    ('MAT-005', 'V10059', 'APPROVED', '2023-11-01'),
    ('MAT-006', 'V10049', 'APPROVED', '2023-06-01'),
    ('MAT-007', 'V10051', 'APPROVED', '2023-05-20'),
    ('MAT-008', 'V10045', 'EXPIRED', '2022-12-01'),
    ('MAT-008', 'V10055', 'APPROVED', '2024-05-10'),
    ('MAT-009', 'V10057', 'APPROVED', '2024-02-15'),
    ('MAT-010', 'V10055', 'APPROVED', '2023-12-01'),
    ('MAT-011', 'V10050', 'APPROVED', '2023-08-01'),
    ('MAT-012', 'V10049', 'APPROVED', '2023-05-01'),
    ('MAT-012', 'V10054', 'APPROVED', '2024-04-15'),
    ('MAT-013', 'V10045', 'APPROVED', '2023-06-15'),
    ('MAT-014', 'V10057', 'APPROVED', '2023-08-20'),
    ('MAT-015', 'V10053', 'APPROVED', '2023-10-15'),
    ('MAT-015', 'V10058', 'PENDING', '2025-06-01'),
    ('MAT-016', 'V10057', 'APPROVED', '2024-01-10'),
    ('MAT-017', 'V10049', 'APPROVED', '2023-09-01'),
    ('MAT-018', 'V10055', 'APPROVED', '2023-07-15'),
    ('MAT-019', 'V10049', 'APPROVED', '2023-06-01');

-- =============================================================================
-- FINANCE
-- =============================================================================

-- =====================================================
-- BSEG: Accounting Document Segment
-- =====================================================
CREATE OR REPLACE TABLE BSEG (
    BELNR VARCHAR(10) NOT NULL,             -- Accounting document number
    BUZEI VARCHAR(3) NOT NULL,              -- Line item number
    EBELN VARCHAR(20),                      -- Purchase order number
    LIFNR VARCHAR(10),                      -- Vendor number
    HKONT VARCHAR(15),                      -- G/L account number
    DMBTR NUMBER(12,2),                     -- Amount in local currency
    BUDAT DATE,                             -- Posting date
    BSCHL VARCHAR(3),                       -- Posting key (31=vendor invoice, 34=debit memo)
    GJAHR NUMBER(4,0),                      -- Fiscal year
    MONAT NUMBER(2,0),                      -- Fiscal period
    PRIMARY KEY (BELNR, BUZEI)
);

INSERT INTO BSEG VALUES
    ('5100000001', '001', 'PO-2024-001', 'V10045', '0040100000', 11000.00, '2024-10-15', '31', 2024, 10),
    ('5100000002', '001', 'PO-2024-002', 'V10078', '0040100000', 89000.00, '2024-10-20', '31', 2024, 10),
    ('5100000003', '001', 'PO-2024-003', 'V10089', '0040100000', 48600.00, '2024-11-01', '31', 2024, 11),
    ('5100000004', '001', 'PO-2024-004', 'V10098', '0040100000', 72000.00, '2024-11-10', '31', 2024, 11),
    ('5100000005', '001', 'PO-2024-005', 'V10102', '0040100000', 26250.00, '2024-11-15', '31', 2024, 11),
    ('5100000006', '001', 'PO-2024-006', 'V10134', '0040100000', 62000.00, '2024-12-01', '31', 2024, 12),
    ('5100000007', '001', 'PO-2024-007', 'V10156', '0040100000', 57300.00, '2024-12-10', '31', 2024, 12),
    ('5100000008', '001', 'PO-2024-008', 'V10167', '0040100000', 97500.00, '2024-12-15', '31', 2024, 12),
    ('5100000009', '001', 'PO-2024-009', 'V10278', '0040100000', 55000.00, '2025-01-01', '31', 2025, 1),
    ('5100000010', '001', 'PO-2024-010', 'V10334', '0040100000', 59000.00, '2025-01-05', '31', 2025, 1),
    ('5100000011', '001', 'PO-2024-011', 'V10102', '0040100000', 11040.00, '2024-12-20', '31', 2024, 12),
    ('5100000012', '001', 'PO-2024-012', 'V10201', '0040100000', 30400.00, '2025-01-10', '31', 2025, 1),
    ('5100000013', '001', 'PO-2025-001', 'V10045', '0040100000', 41000.00, '2025-02-10', '31', 2025, 2),
    ('5100000014', '001', 'PO-2025-002', 'V10201', '0040100000', 84000.00, '2025-02-20', '31', 2025, 2),
    ('5100000015', '001', 'PO-2025-003', 'V10190', '0040100000', 49000.00, '2025-03-01', '31', 2025, 3),
    ('5100000016', '001', 'PO-2025-004', 'V10312', '0040100000', 34400.00, '2025-03-15', '31', 2025, 3),
    ('5100000017', '001', 'PO-2025-005', 'V10089', '0040100000', 34500.00, '2025-04-01', '31', 2025, 4),
    ('5100000018', '001', 'PO-2025-006', 'V10134', '0040100000', 93000.00, '2025-04-15', '31', 2025, 4),
    ('5100000019', '001', 'PO-2025-007', 'V10078', '0040100000', 67200.00, '2025-05-01', '31', 2025, 5),
    ('5100000020', '001', 'PO-2025-008', 'V10223', '0040100000', 33000.00, '2025-05-05', '31', 2025, 5),
    ('5100000021', '001', 'PO-2025-009', 'V10098', '0040100000', 90000.00, '2025-05-10', '31', 2025, 5),
    ('5100000022', '001', 'PO-2025-010', 'V10167', '0040100000', 80000.00, '2025-05-12', '31', 2025, 5),
    ('5100000023', '001', 'PO-2025-011', 'V10045', '0040100000', 22000.00, '2025-05-15', '31', 2025, 5),
    ('5100000024', '001', 'PO-2025-012', 'V10278', '0040100000', 84000.00, '2025-05-16', '31', 2025, 5),
    ('5100000025', '001', 'PO-2025-013', 'V10245', '0040100000', 22500.00, '2025-04-01', '31', 2025, 4),
    ('5100000030', '001', 'PO-2024-003', 'V10089', '0040100000', 12150.00, '2024-12-01', '34', 2024, 12),
    ('5100000031', '001', 'PO-2024-008', 'V10167', '0040100000', 19500.00, '2025-01-15', '34', 2025, 1),
    ('5100000032', '001', 'PO-2025-003', 'V10190', '0040100000', 9800.00, '2025-04-01', '34', 2025, 4),
    ('5100000033', '001', 'PO-2025-007', 'V10078', '0040100000', 6720.00, '2025-06-01', '34', 2025, 6),
    ('5100000034', '001', 'PO-2024-006', 'V10134', '0040100000', 15500.00, '2025-02-01', '34', 2025, 2),
    ('5100000040', '001', 'PO-2024-001', 'V10045', '0040200000', 2200.00, '2024-10-20', '31', 2024, 10),
    ('5100000041', '001', 'PO-2024-004', 'V10098', '0040200000', 8500.00, '2024-11-15', '31', 2024, 11),
    ('5100000042', '001', 'PO-2025-002', 'V10201', '0040200000', 12600.00, '2025-03-01', '31', 2025, 3),
    ('5100000043', '001', 'PO-2025-009', 'V10098', '0040200000', 11000.00, '2025-05-15', '31', 2025, 5),
    ('5100000044', '001', 'PO-2025-006', 'V10134', '0040200000', 5500.00, '2025-04-20', '31', 2025, 4),
    ('5100000050', '001', 'PO-2024-001', 'V10045', '0021100000', 13200.00, '2024-10-15', '31', 2024, 10),
    ('5100000051', '001', 'PO-2025-009', 'V10098', '0021100000', 101000.00, '2025-05-10', '31', 2025, 5),
    ('5100000052', '001', 'PO-2025-006', 'V10134', '0021100000', 98500.00, '2025-04-15', '31', 2025, 4);

-- =====================================================
-- COEP: CO Line Items (Cost Element Postings)
-- =====================================================
CREATE OR REPLACE TABLE COEP (
    OBJNR VARCHAR(20),                      -- Cost center / object number
    KSTAR VARCHAR(15),                      -- Cost element
    WRTBTR NUMBER(12,2),                    -- Amount in controlling area currency
    GJAHR NUMBER(4,0),                      -- Fiscal year
    PERIO NUMBER(2,0),                      -- Posting period
    MATNR VARCHAR(10)                       -- Material number
);

INSERT INTO COEP VALUES
    ('KS-LOG', '0047000000', 39800.00, 2025, 1, NULL),
    ('KS-LOG', '0047000000', 42100.00, 2025, 2, NULL),
    ('KS-MFG-AP', '0040100000', 177500.00, 2025, 1, 'MAT-011'),
    ('KS-MFG-AP', '0040100000', 139000.00, 2025, 2, 'MAT-007'),
    ('KS-MFG-AP', '0040100000', 74000.00, 2025, 3, 'MAT-001'),
    ('KS-MFG-AP', '0047000000', 31200.00, 2025, 1, NULL),
    ('KS-MFG-AP', '0048000000', 14800.00, 2025, 2, NULL),
    ('KS-MFG-EU', '0040100000', 213500.00, 2025, 1, 'MAT-002'),
    ('KS-MFG-EU', '0040100000', 67200.00, 2025, 2, 'MAT-017'),
    ('KS-MFG-EU', '0040100000', 34400.00, 2025, 3, 'MAT-018'),
    ('KS-MFG-EU', '0047000000', 22300.00, 2025, 1, NULL),
    ('KS-MFG-EU', '0048000000', 11500.00, 2025, 2, NULL),
    ('KS-MFG-US', '0040100000', 172550.00, 2025, 1, 'MAT-003'),
    ('KS-MFG-US', '0040100000', 127500.00, 2025, 2, 'MAT-004'),
    ('KS-MFG-US', '0040100000', 93000.00, 2025, 3, 'MAT-008'),
    ('KS-MFG-US', '0047000000', 18500.00, 2025, 1, NULL),
    ('KS-MFG-US', '0048000000', 8200.00, 2025, 1, NULL),
    ('KS-QA', '0048000000', 22000.00, 2025, 1, NULL),
    ('KS-QA', '0048000000', 18500.00, 2025, 2, NULL);

-- =============================================================================
-- SALES
-- =============================================================================

-- =====================================================
-- VBAP: Sales Order Items
-- =====================================================
CREATE OR REPLACE TABLE VBAP (
    VBELN VARCHAR(10) NOT NULL,             -- Sales document number
    POSNR VARCHAR(5) NOT NULL,              -- Sales document item
    MATNR VARCHAR(10),                      -- Material number
    KWMENG NUMBER(10,0),                    -- Order quantity
    NETWR NUMBER(12,2),                     -- Net value
    KUNNR VARCHAR(10),                      -- Customer number
    ERDAT DATE,                             -- Created on date
    VKORG VARCHAR(5),                       -- Sales organization
    PRIMARY KEY (VBELN, POSNR)
);

INSERT INTO VBAP VALUES
    ('SO-001', '010', 'ASSY-004', 50, 60000.00, 'C-1001', '2025-01-15', '1000'),
    ('SO-001', '020', 'ASSY-003', 100, 85000.00, 'C-1001', '2025-01-15', '1000'),
    ('SO-002', '010', 'ASSY-004', 80, 96000.00, 'C-1002', '2025-02-10', '2000'),
    ('SO-002', '020', 'ASSY-003', 60, 51000.00, 'C-1002', '2025-02-10', '2000'),
    ('SO-003', '010', 'ASSY-004', 30, 36000.00, 'C-1003', '2025-03-01', '3000'),
    ('SO-004', '010', 'ASSY-004', 120, 144000.00, 'C-1001', '2025-04-01', '1000'),
    ('SO-005', '010', 'ASSY-004', 45, 54000.00, 'C-1004', '2025-04-15', '2000'),
    ('SO-006', '010', 'ASSY-003', 75, 63750.00, 'C-1005', '2025-03-20', '1000'),
    ('SO-007', '010', 'ASSY-003', 40, 34000.00, 'C-1003', '2025-05-01', '3000'),
    ('SO-008', '010', 'ASSY-001', 200, 24000.00, 'C-1001', '2025-02-01', '1000'),
    ('SO-009', '010', 'ASSY-001', 500, 60000.00, 'C-1004', '2025-04-10', '2000'),
    ('SO-010', '010', 'ASSY-002', 300, 25500.00, 'C-1002', '2025-03-05', '2000'),
    ('SO-011', '010', 'ASSY-002', 150, 12750.00, 'C-1005', '2025-05-10', '1000');

-- =====================================================
-- KONV: Pricing Conditions
-- =====================================================
CREATE OR REPLACE TABLE KONV (
    KNUMV VARCHAR(10) NOT NULL,             -- Condition document number
    KPOSN VARCHAR(5) NOT NULL,              -- Item number
    KSCHL VARCHAR(5) NOT NULL,              -- Condition type (PR00=Price, K007=Customer discount, KF00=Freight surcharge)
    KBETR NUMBER(8,2),                      -- Condition rate / percentage
    KWERT NUMBER(12,2),                     -- Condition value
    MATNR VARCHAR(10),                      -- Material number
    KUNNR VARCHAR(10),                      -- Customer number
    PRIMARY KEY (KNUMV, KPOSN, KSCHL)
);

INSERT INTO KONV VALUES
    ('KN-001', '010', 'K007', 5.00, -3000.00, 'ASSY-004', 'C-1001'),
    ('KN-001', '010', 'PR00', 1200.00, 60000.00, 'ASSY-004', 'C-1001'),
    ('KN-001', '020', 'K007', 5.00, -4250.00, 'ASSY-003', 'C-1001'),
    ('KN-001', '020', 'PR00', 850.00, 85000.00, 'ASSY-003', 'C-1001'),
    ('KN-002', '010', 'K007', 8.00, -7680.00, 'ASSY-004', 'C-1002'),
    ('KN-002', '010', 'PR00', 1200.00, 96000.00, 'ASSY-004', 'C-1002'),
    ('KN-002', '020', 'PR00', 850.00, 51000.00, 'ASSY-003', 'C-1002'),
    ('KN-003', '010', 'KF00', 2.00, 720.00, 'ASSY-004', 'C-1003'),
    ('KN-003', '010', 'PR00', 1200.00, 36000.00, 'ASSY-004', 'C-1003'),
    ('KN-004', '010', 'K007', 5.00, -7200.00, 'ASSY-004', 'C-1001'),
    ('KN-004', '010', 'PR00', 1200.00, 144000.00, 'ASSY-004', 'C-1001'),
    ('KN-005', '010', 'K007', 3.00, -1620.00, 'ASSY-004', 'C-1004'),
    ('KN-005', '010', 'PR00', 1200.00, 54000.00, 'ASSY-004', 'C-1004'),
    ('KN-006', '010', 'K007', 4.00, -2550.00, 'ASSY-003', 'C-1005'),
    ('KN-006', '010', 'PR00', 850.00, 63750.00, 'ASSY-003', 'C-1005'),
    ('KN-007', '010', 'KF00', 3.00, 1020.00, 'ASSY-003', 'C-1003'),
    ('KN-007', '010', 'PR00', 850.00, 34000.00, 'ASSY-003', 'C-1003'),
    ('KN-008', '010', 'KF00', 2.00, 480.00, 'ASSY-001', 'C-1001'),
    ('KN-008', '010', 'PR00', 120.00, 24000.00, 'ASSY-001', 'C-1001'),
    ('KN-009', '010', 'K007', 10.00, -6000.00, 'ASSY-001', 'C-1004'),
    ('KN-009', '010', 'PR00', 120.00, 60000.00, 'ASSY-001', 'C-1004'),
    ('KN-010', '010', 'K007', 7.00, -1785.00, 'ASSY-002', 'C-1002'),
    ('KN-010', '010', 'PR00', 85.00, 25500.00, 'ASSY-002', 'C-1002'),
    ('KN-011', '010', 'KF00', 3.00, 382.50, 'ASSY-002', 'C-1005'),
    ('KN-011', '010', 'PR00', 85.00, 12750.00, 'ASSY-002', 'C-1005');

-- Reference (code) tables. New codes arrive here through normal loads;
-- the ontology only changes when a business rule changes.
CREATE OR REPLACE TABLE T077K (
  KTOKK VARCHAR(10) PRIMARY KEY COMMENT 'Vendor account group code',
  TXT30 VARCHAR(60) COMMENT 'Account group description',
  EXCLUDE_FROM_ACTIVE_COUNT BOOLEAN COMMENT 'TRUE if vendors in this group are excluded from the active supplier count'
) COMMENT = 'Vendor account group reference (code table)' AS
SELECT * FROM VALUES ('ZSTR','Strategic partner',FALSE),('ZSTD','Standard vendor',FALSE),('ZPRB','Probationary vendor',TRUE);

CREATE OR REPLACE TABLE T023T (
  MATKL VARCHAR(5) PRIMARY KEY COMMENT 'Material group code',
  WGBEZ VARCHAR(60) COMMENT 'Material group description'
) COMMENT = 'Material group texts (code table)' AS
SELECT * FROM VALUES ('043','Electronics'),('044','Chemicals'),('045','Metals'),('046','Packaging'),('047','Raw Materials'),('048','Assembly');


-- -----------------------------------------------------------------------------
-- Done. Expected: 17 tables in SENSE_ONTOLOGY_QS.SAP. checks.sql CHECK 1 confirms it.
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS sap_tables
FROM SENSE_ONTOLOGY_QS.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SAP' AND TABLE_TYPE = 'BASE TABLE';
