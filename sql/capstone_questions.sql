USE DATABASE CAPSTONE;
USE SCHEMA PUBLIC;

-- Q1 — Average marks by attendance band and subject
SELECT DISTINCT attendance_band, subject_code, total_marks
FROM GOLD_STUDENT_SUBJECT_SEM;

SELECT attendance_band, subject_code, ROUND(AVG(total_marks), 1) AS avg_marks
FROM GOLD_STUDENT_SUBJECT_SEM
GROUP BY attendance_band, subject_code
ORDER BY subject_code, attendance_band;

-- Q2 — Students whose semester rank jumped 20+ places (the LAG/RANK query)
WITH s AS (
  SELECT DISTINCT student_id, branch, semester, sem_total_marks
  FROM GOLD_STUDENT_SUBJECT_SEM WHERE is_complete = TRUE),
r AS (
  SELECT student_id, branch, semester, sem_total_marks,
         RANK() OVER (PARTITION BY semester ORDER BY sem_total_marks DESC) AS sem_rank
  FROM s)
SELECT student_id, branch, semester, sem_rank,
       LAG(sem_rank) OVER (PARTITION BY student_id ORDER BY semester) AS prev_rank,
       sem_rank - LAG(sem_rank) OVER (PARTITION BY student_id ORDER BY semester) AS chg
FROM r
QUALIFY sem_rank - LAG(sem_rank) OVER (PARTITION BY student_id ORDER BY semester) >= 20
ORDER BY chg DESC;

-- Q3 — Correlation between attendance and marks, per subject
SELECT subject_code,
       ROUND(CORR(attendance_pct, total_marks), 3) AS corr_attendance_marks
FROM GOLD_STUDENT_SUBJECT_SEM
GROUP BY subject_code
ORDER BY corr_attendance_marks DESC;

-- Verify - Exactly 905 of the 1,200 students are is_complete in both semesters 1 and 2, and exactly 114 of the 150 penalty students (id%8=3) are among them.
-- Step 1a: how many of the 1,200 students are complete in BOTH semester 1 and 2
WITH sem_complete AS (
  SELECT DISTINCT student_id, semester, is_complete
  FROM GOLD_STUDENT_SUBJECT_SEM
)
SELECT COUNT(*) AS complete_in_both_sem1_sem2
FROM (
  SELECT student_id
  FROM sem_complete
  WHERE semester IN (1,2) AND is_complete = TRUE
  GROUP BY student_id
  HAVING COUNT(DISTINCT semester) = 2
);

-- Step 1b: of those, how many are "penalty students" (id % 8 = 3 from the generator)
-- student_id is formatted 'S%04d' = id+1, so recover id as SUBSTR(student_id,2)::INT - 1
WITH sem_complete AS (
  SELECT DISTINCT student_id, semester, is_complete
  FROM GOLD_STUDENT_SUBJECT_SEM
),
complete_both AS (
  SELECT student_id
  FROM sem_complete
  WHERE semester IN (1,2) AND is_complete = TRUE
  GROUP BY student_id
  HAVING COUNT(DISTINCT semester) = 2
),
penalty_students AS (
  SELECT DISTINCT student_id
  FROM GOLD_STUDENT_SUBJECT_SEM
  WHERE MOD(TRY_CAST(SUBSTR(student_id, 2) AS INT) - 1, 8) = 3
)
SELECT COUNT(*) AS penalty_and_complete
FROM complete_both c
JOIN penalty_students p ON c.student_id = p.student_id;


-- Veify - More than 90 of those 114 appear in the semester-2 fall list.
WITH s AS (
  SELECT DISTINCT student_id, semester, sem_total_marks
  FROM GOLD_STUDENT_SUBJECT_SEM WHERE is_complete = TRUE),
r AS (
  SELECT student_id, semester, sem_total_marks,
         RANK() OVER (PARTITION BY semester ORDER BY sem_total_marks DESC) AS sem_rank
  FROM s),
chg AS (
  SELECT student_id, semester, sem_rank,
         LAG(sem_rank) OVER (PARTITION BY student_id ORDER BY semester) AS prev_rank,
         sem_rank - LAG(sem_rank) OVER (PARTITION BY student_id ORDER BY semester) AS chg
  FROM r
),
penalty_students AS (
  SELECT DISTINCT student_id
  FROM GOLD_STUDENT_SUBJECT_SEM
  WHERE MOD(TRY_CAST(SUBSTR(student_id, 2) AS INT) - 1, 8) = 3
)
SELECT
  COUNT_IF(c.semester = 2 AND c.chg > 0) AS penalty_fell_in_sem2,
  COUNT_IF(c.semester = 3 AND c.chg < 0) AS penalty_rose_in_sem3
FROM chg c
JOIN penalty_students p ON c.student_id = p.student_id;