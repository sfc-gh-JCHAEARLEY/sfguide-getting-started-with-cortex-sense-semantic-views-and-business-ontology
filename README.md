# Getting Started with Cortex Sense, Semantic Views, and Business Ontology

Companion repo for the Snowflake guide **[Getting Started with Cortex Sense, Semantic Views, and Business Ontology](https://www.snowflake.com/en/developers/guides/getting-started-with-cortex-sense-semantic-views-and-business-ontology/)**.

A manufacturer's SAP procurement data has two numbers with a plausible look-alike: the supplier count (14, not the 15 vendor records) and the on-time delivery rate (66.67%, not the 90% carriers report). In the guide you calculate the metrics in a semantic view, define and approve what they mean in Business Ontology, build a Cortex Sense context that brings it all together, and ask CoCo in plain English.

## How to use this repo

Open it in Snowsight as a **Git-backed workspace** (**Projects** » **Workspaces**, then **From Git repository** in the **Workspaces** menu) and follow the guide. Before that, the guide has you run a short SQL snippet that creates the API integration the workspace needs. You run the files in this order:

| File | When |
|------|------|
| `setup.sql` | Setup. Creates `SENSE_ONTOLOGY_ROLE`, `SENSE_ONTOLOGY_WH`, `SENSE_ONTOLOGY_QS` and 17 SAP tables. Run it as ACCOUNTADMIN. |
| `semantic_view.sql` | Step 1. Creates the `PROCUREMENT_SV` semantic view. |
| `ontology.sql` | Step 2. Creates the Procurement and Logistics domains, and drafts, approves and connects 12 terms. |
| `sense.sql` | Step 3. Builds the `PROCUREMENT` Cortex Sense context and shows what it found. |
| `checks.sql` | After each step. Run the matching CHECK block; every row should say PASS. |
| `teardown.sql` | When you're done. Removes everything the lab created. |
| `optional/agents.sql` | Optional. Compares two Cortex Agents on the same questions. |

## Expected results

| Question | Official answer | Look-alike |
|----------|-----------------|------------|
| How many suppliers do we have? | 14 | 15 vendor records |
| What is our on-time delivery rate? | 66.67% | 90% carrier-reported |
| How many storage locations does plant PLT-001 have? | 3 | |

## Clean up

1. Open `teardown.sql` and run it. It deletes the Cortex Sense context, empties and deletes the two ontology domains (only if they carry this lab's `[sense-ontology-qs]` marker), and drops the database, warehouse, role and the `GITHUB_SENSE_ONTOLOGY_LAB` API integration.
2. Delete your lab workspace in **Projects** » **Workspaces**.
3. In the SQL file in **My Workspace**, run `DROP DATABASE IF EXISTS SENSE_ONTOLOGY_GIT;` as ACCOUNTADMIN to remove the database you created for the workspace. Then delete the SQL file.

## License

Apache 2.0. See [LICENSE](LICENSE).
