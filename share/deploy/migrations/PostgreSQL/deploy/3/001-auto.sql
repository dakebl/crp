-- 
-- Created by SQL::Translator::Producer::PostgreSQL
-- Created on Sat Nov 15 17:15:12 2014
-- 
;
--
-- Table: enquiry.
--
CREATE TABLE "enquiry" (
  "id" serial NOT NULL,
  "name" text,
  "email" text NOT NULL,
  "create_date" timestamp DEFAULT (now()) NOT NULL,
  "suspend_date" timestamp,
  "location" text,
  "latitude" numeric,
  "longitude" numeric,
  "notify_new_courses" boolean,
  "notify_tutors" boolean,
  "send_newsletter" boolean,
  PRIMARY KEY ("id"),
  CONSTRAINT "enquiry_email_key" UNIQUE ("email")
);
CREATE INDEX "enquiry_suspend_date_idx" on "enquiry" ("suspend_date");
CREATE INDEX "enquiry_latitude_idx" on "enquiry" ("latitude");
CREATE INDEX "enquiry_longitude_idx" on "enquiry" ("longitude");

;
--
-- Table: login.
--
CREATE TABLE "login" (
  "id" serial NOT NULL,
  "email" text,
  "create_date" timestamp DEFAULT (now()) NOT NULL,
  "last_login_date" timestamp,
  "password_hash" text,
  "otp_hash" text,
  "otp_expiry_date" timestamp,
  "is_administrator" boolean,
  "auto_login" boolean,
  PRIMARY KEY ("id"),
  CONSTRAINT "login_email_key" UNIQUE ("email")
);

;