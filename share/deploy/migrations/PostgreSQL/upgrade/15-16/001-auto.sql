-- Convert schema 'share/deploy/migrations/_source/deploy/15/001-auto.yml' to 'share/deploy/migrations/_source/deploy/16/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE login ADD COLUMN is_demo boolean;

;

COMMIT;

