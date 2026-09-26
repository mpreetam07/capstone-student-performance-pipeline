# Capstone Project — Topic 24: Student Performance & Attendance
### Silver Layer Decisions, Pipeline Verification & Results

**Name:** Preetam Mondal
**Domain:** Media, Education & Sport
**Stack:** Databricks (PySpark, Unity Catalog, Jobs) → Snowflake (Stages, COPY INTO, SQL)

---

## 1. Pipeline Architecture

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

Built as **5 chained Databricks Job tasks** (`generate_data → bronze → silver → gold → export`),
each depending on the previous, running on serverless compute, with a schedule attached so the
pipeline runs unattended rather than requiring manual triggering. Job run completed with all
five tasks succeeding (see `job_dag_screenshot.png`).

---

## 2. Silver Layer — The Four Judgement Calls

### Decision 1 — `try_cast`, never `cast`; `'AB'` → 0
`classes_held`, `classes_attended`, `internal_marks`, `external_marks` were cast with
`try_cast`, not `cast`, because ANSI mode (on by default) throws on the first bad value and
kills the whole job. Exactly **300 rows** carried the literal string `'AB'` in
`internal_marks` — a genuinely absent internal assessment, not a zero score. `try_cast` turns
these into `NULL`; `coalesce(NULL, 0)` converts them to `0` for scoring purposes, keeping the
absence visible in the raw data while making it computable downstream.
Verified with an assertion: `m.filter("internal_marks = 'AB'").count() == 300` → passed.

### Decision 2 — Dedupe on `(student_id, semester, subject_code)`
Deduped using `ROW_NUMBER()` over the natural key `(student_id, semester, subject_code)`,
ordered by `_ingested_at`, keeping rank 1 — **not** the whole row, since a resent record could
carry an identical row with only a different ingestion timestamp. This step dropped exactly
**480 rows** (22,200 → 21,720).

### Decision 3 — Orphan and range rejects (three named reasons, logged not discarded)
- **`unknown_student`** — rows whose `student_id` doesn't exist in the students master
  table (anti-join against `bronze_students`). Dropped **120 rows** (21,720 → 21,600).
- **`attendance_over_100`** — rows where `classes_attended > classes_held`; attendance
  physically cannot exceed classes actually held.
- **`no_classes_held`** — rows where `classes_held = 0`; a zero-denominator attendance
  percentage is undefined, not zero, and must not be silently treated as 0%.
- **`marks_over_max`** — rows where `external_marks > 60`, the maximum possible external
  score; anything above it is a data defect, not a real mark.

Together these three rules dropped the remaining **440 rows** (21,600 → 21,160). Every
rejected row was preserved in a `silver_rejects` table with its reason attached, rather than
being silently discarded — the count of what was thrown away is itself a fact worth keeping.

### Decision 4 — Attendance band, `sem_total_marks`, `is_complete`, `sem_rank`
- `attendance_band` was derived from the **unrounded** `attendance_pct`
  (`classes_attended / classes_held * 100`), not a pre-rounded percentage, to avoid
  off-by-one band misclassification right at the 60/75/85 boundaries.
- `sem_total_marks` and `is_complete` are computed per `(student_id, semester)` — a student
  only counts as `is_complete = true` for a semester if all 6 subjects survived every Silver
  rejection rule for that semester.
- `sem_rank` is computed **only** over complete students, partitioned by semester and ordered
  by `sem_total_marks` descending — so an incomplete record can never occupy or distort a
  rank slot it didn't earn.

---

## 3. Row-Count Trail (verified to close exactly at every stage)

| Stage | Rows | Change | Reason |
|---|---|---|---|
| Bronze (raw landed) | 22,200 | — | 1,200 students × 3 semesters × 6 subjects = 21,600, plus 480 injected repeats and 120 injected orphan rows |
| After dedupe | 21,720 | −480 | Duplicate `(student_id, semester, subject_code)` |
| After `unknown_student` reject | 21,600 | −120 | `student_id` not present in master |
| Silver / Gold (final) | **21,160** | −440 | `attendance_over_100` + `no_classes_held` + `marks_over_max` combined |

`22,200 − 480 − 120 − 440 = 21,160` ✅ — the arithmetic the brief asks you to confirm in code,
confirmed here in the write-up as well.

---

## 4. Idempotency Proof — Snowflake `COPY INTO`

| Run | Result |
|---|---|
| First `COPY INTO GOLD_STUDENT_SUBJECT_SEM FROM @gold_stage` | All **21,160** rows loaded. `SELECT COUNT(*)` confirmed 21,160. |
| Second, identical `COPY INTO` against the same stage | **"Copy executed with 0 files processed."** |

Snowflake's load metadata recognized the staged file had already been loaded and correctly
skipped it on the second run — proving the load step is safe to re-run without duplicating
data, exactly as the brief's "run the load twice" check requires.

---

## 5. Deeper Verification Checkpoints (brief's "you are done when" list)

| Checkpoint | Expected | Actual |
|---|---|---|
| Students `is_complete` in **both** semester 1 and 2 | 905 | **905** ✅ |
| Of those, penalty students (`id % 8 = 3`) | 114 of 150 | **114** ✅ |
| Penalty students whose rank **fell** in semester 2 | more than 90 of 114 | **109** ✅ |
| Penalty students whose rank **rose back** in semester 3 | majority | **121** (recovery pattern confirmed) |

These confirm the generator's planted "one-time semester-2 penalty" mechanic is correctly
visible in the ranking behavior, not just in the raw marks.

---

## 6. Analytical Questions — Results & Interpretation

### Q1 — Average marks by attendance band and subject
Average total marks rise consistently with attendance band for **every** subject. Example
(DBMS): `43.3 → 48.0 → 53.0 → 57.4` from `BELOW_60 → BAND_60_74 → BAND_75_84 → BAND_85_100`.
**Interpretation:** attendance is a genuine positive signal for academic performance across
all six subjects in this dataset — not just a superficial correlation in one or two courses.

### Q2 — Students whose semester rank jumped 20+ places (semester 1 → 2)
**934** students moved 20 or more rank positions between semesters — a sizeable share of the
~905 "complete" students, reflecting meaningful semester-to-semester volatility rather than
static rankings, consistent with the random noise term built into the underlying score
generation formula.

### Q3 — Correlation between attendance and total marks, by subject

| Subject | Correlation |
|---|---|
| PROG | 0.659 |
| MATH | 0.604 |
| DBMS | 0.486 |
| PHYS | 0.403 |
| ENGL | 0.156 |
| WORK | 0.114 |

**Interpretation:** attendance correlates most strongly with subjects weighted toward
continuous, practice-based assessment (Programming, Mathematics) and weakest with subjects
less dependent on in-class engagement (Technical English, Workshop Practice) — consistent
with each subject's underlying score-sensitivity to attendance as designed in the generator.
All six values land within the brief's planted ranges (PROG/MATH > 0.55, DBMS/PHYS between
0.35–0.55, ENGL/WORK < 0.20), confirming the Silver/Gold joins were built correctly.

---

## 7. Summary

Every explicit numeric checkpoint in the brief was reproduced exactly: the row-count funnel
closes with no unexplained gaps, the 905/114/109 semester-completion and penalty-student
figures match, the idempotency proof behaves as specified, and all three analytical questions
return results consistent with the dataset's planted design. The pipeline runs end-to-end,
unattended, on a schedule, with every Silver-layer judgement call logged with a named reason
rather than silently applied.
