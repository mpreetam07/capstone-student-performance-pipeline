# Capstone — Student Performance & Attendance Pipeline

An end-to-end data pipeline that generates a synthetic student-performance dataset,
processes it through a Bronze → Silver → Gold Medallion architecture in Databricks
(PySpark, Unity Catalog), exports it to Snowflake, and answers three analytical
questions on attendance vs. academic performance. Orchestrated as a scheduled,
5-task Databricks Job that runs unattended end to end.

**Name:** Preetam Mondal · **Topic:** 24 — Student Performance & Attendance (Media,
Education & Sport domain)

---

## Architecture

```
Generate (synthetic data, seeded)
      │
      ▼
   BRONZE   — land raw CSVs as-is, every column STRING, add provenance columns
      │
      ▼
   SILVER   — try_cast, dedupe, reject orphans/out-of-range rows, derive bands & ranks
      │
      ▼
    GOLD    — one row per student × semester × subject, joined with dims
      │
      ▼
   EXPORT   — coalesce to single CSV → Databricks Volume
      │
      ▼
  SNOWFLAKE — stage → COPY INTO → SQL analysis (Q1–Q3)
```

Built as 5 chained Databricks Job tasks (`generate_data → bronze → silver → gold →
export`), each depending on the previous, running on serverless compute, with a
schedule attached.

## Key numbers

| Stage | Rows |
|---|---|
| Bronze (raw) | 22,200 |
| After dedupe | 21,720 |
| After unknown_student reject | 21,600 |
| Silver / Gold (final) | 21,160 |

Full breakdown of every Silver-layer decision, the idempotency proof, and Q1–Q3
results with interpretation: see [`writeup.md`](./writeup.md).

## Repository structure

```
notebooks/     01_generate_data, 02_bronze, 03_silver, 04_gold, 05_export (.ipynb)
sql/           capstone_project.sql, capstone_questions.sql (Snowflake DDL + queries)
exports/       gold_student_subject_sem.csv (Gold layer export)
screenshots/   job DAG, COPY INTO results (load + idempotency), Q1–Q3 query results
writeup.md     detailed Silver decisions, row-count trail, idempotency proof, Q1–Q3
```

## How to run it

1. In a Databricks workspace with Unity Catalog enabled, import the 5 notebooks
   from `/notebooks` in order.
2. Set `MY_ID` at the top of each notebook to your own identifier.
3. Run `01_generate_data` → `02_bronze` → `03_silver` → `04_gold` → `05_export`,
   in that order (or wire them as a Databricks Job with sequential dependencies,
   as this project does).
4. Download the exported Gold CSV from your Databricks Volume.
5. In Snowflake, run the DDL/stage/`COPY INTO` statements in
   [`sql/capstone_project.sql`](./sql/capstone_project.sql), uploading the Gold
   CSV to the created stage when prompted.
6. Run the analytical queries in
   [`sql/capstone_questions.sql`](./sql/capstone_questions.sql) to reproduce
   Q1–Q3.

## Results summary

- **Q1:** Average marks rise consistently with attendance band across all six subjects.
- **Q2:** 934 students shifted 20+ semester-rank positions between semesters 1 and 2.
- **Q3:** Attendance correlates most strongly with PROG (0.659) and MATH (0.604), and
  least with ENGL (0.156) and WORK (0.114) — consistent with each subject's
  assessment style.

Full detail and interpretation in [`writeup.md`](./writeup.md).
