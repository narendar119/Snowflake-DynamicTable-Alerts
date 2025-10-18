# Snowflake Real-Time Data Pipeline: Dynamic Tables & Automated Alerts 🚀

This repository contains the SQL scripts for building an end-to-end, real-time data ingestion and transformation pipeline entirely within **Snowflake**. The project leverages **Dynamic Tables (DTs)** for continuous, dependency-managed transformations and **Snowflake Alerts** for proactive error notification, creating a resilient and autonomous data flow.

---

## 🎯 Project Goal

The primary objective is to demonstrate how to use native Snowflake capabilities to build a production-ready pipeline that:

1.  **Ingests** raw data (simulated staging).
2.  **Transforms** data continuously using business logic (Dynamic Tables).
3.  **Monitors** pipeline health and sends **instant email notifications** upon failure (Snowflake Alerts).

---

## 🏛️ Architecture and Key Components

The pipeline is designed using native **Snowflake** capabilities, following a multi-layered approach to ensure continuous data flow and dependency management.

### Pipeline Flow

1.  **Ingestion Layer (Stage Tables):**
    * **Components:** `STG_CUSTOMER` and `STG_ITEM`.
    * **Function:** These tables represent the raw data landing zone. **(Note:** In a real-world setup, these would be loaded continuously by **Snowpipe** from a cloud storage bucket like AWS S3 or Azure Blob. We simulate this here with manual data inserts.)

2.  **Transformation Layer (Dynamic Tables):**
    * This is the core of the pipeline, where business logic is applied using **Dynamic Tables (DTs)**. DTs automatically manage refresh dependencies and ensure the downstream tables are updated only when their source data changes.
    * **Customer DT (`CUSTOMER_DT`):** Transforms the raw customer data to filter for the **latest record** for each unique customer (`C_ID`) based on the `CREATION_DATE`.
    * **Item DT (`ITEM_DT`):** Transforms the raw item data to filter for the item with the **highest price** for each unique item (`I_ID`).

3.  **Target Layer (Reporting DT):**
    * **Component:** `CUSTOMER_ITEM_DT`.
    * **Function:** This table joins the cleansed data from `CUSTOMER_DT` and `ITEM_DT` to calculate the final business metric: **`PRICE_PER_ITEM`** (Price divided by Count). It is configured with a **`TARGET_LAG = '1 minute'`** to maintain near real-time freshness.

4.  **Error Handling & Monitoring:**
    * **Component:** **Snowflake Alert** (`DT_FAILURE_NOTIFICATION`).
    * **Function:** The alert is scheduled to run every minute and checks the refresh history of the target Dynamic Table (`CUSTOMER_ITEM_DT`). If a failure is detected (e.g., the Division by Zero error we simulate), it automatically sends an **email notification** to the registered recipient, enabling proactive troubleshooting.

---

## 🛠️ Setup and Execution

### Prerequisites

1.  An active Snowflake Account.
2.  A designated Warehouse (e.g., `COMPUTE_WH`).
3.  An email address for testing the alert system.
