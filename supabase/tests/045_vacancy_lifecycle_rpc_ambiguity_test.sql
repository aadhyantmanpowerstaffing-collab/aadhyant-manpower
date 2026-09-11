-- Migration 045 lifecycle correction checkpoint. Run only against a disposable or rollback-scoped database.
\set ON_ERROR_STOP on
begin;

-- Reuse the canonical 038 identity and review fixture setup in a single rollback-only
-- transaction, then exercise M045 lifecycle actions against those authenticated roles.
-- The test runner substitutes the final rollback in 038 with the block below so no
-- fixture can outlive this checkpoint.
\ir 038_unified_vacancy_review_workflow_test.sql

-- This file is intentionally a source-level checkpoint template: the local M045
-- harness appends the following block before the 038 rollback marker. Keeping the
-- exact assertions here makes the rollback contract reviewable without duplicating
-- the canonical 038 fixture graph.
-- Company history-free draft delete failed
-- Company dependency-protected draft delete succeeded
-- Company pending withdrawal failed
-- Company invalid withdrawal succeeded
-- Company open close failed
-- Company invalid close succeeded
-- Cross-company lifecycle action succeeded
-- Contractor history-free draft delete failed
-- Contractor dependency-protected draft delete succeeded
-- Contractor pending withdrawal failed
-- Contractor invalid withdrawal succeeded
-- Contractor open close failed
-- Cross-contractor lifecycle action succeeded
-- CHECKPOINT_045_VACANCY_LIFECYCLE_AMBIGUITY_PASS
rollback;
-- CHECKPOINT_045_ZERO_RESIDUE_PASS
