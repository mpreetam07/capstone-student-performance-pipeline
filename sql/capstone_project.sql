CREATE DATABASE IF NOT EXISTS CAPSTONE;
USE DATABASE CAPSTONE;
USE SCHEMA PUBLIC;

CREATE OR REPLACE STAGE gold_stage;

LIST @gold_stage;

CREATE OR REPLACE TABLE GOLD_STUDENT_SUBJECT_SEM (
  student_id STRING, branch STRING, section STRING, semester INT,
  subject_code STRING, subject_name STRING, classes_held INT, classes_attended INT,
  attendance_pct FLOAT, attendance_band STRING, internal_marks INT, external_marks INT,
  total_marks INT, sem_total_marks INT, is_complete BOOLEAN, sem_rank INT
);

COPY INTO GOLD_STUDENT_SUBJECT_SEM
FROM @gold_stage
FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"');

SELECT COUNT(*) FROM GOLD_STUDENT_SUBJECT_SEM;   -- must read 21,160

COPY INTO GOLD_STUDENT_SUBJECT_SEM
FROM @gold_stage
FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"');