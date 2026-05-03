/*
 Navicat Premium Data Transfer

 Source Server         : C - la_db - new.db3
 Source Server Type    : SQLite
 Source Server Version : 3035005 (3.35.5)
 Source Schema         : main

 Target Server Type    : SQLite
 Target Server Version : 3035005 (3.35.5)
 File Encoding         : 65001

 Date: 03/05/2026 22:40:18
*/

PRAGMA foreign_keys = false;

-- ----------------------------
-- Table structure for extra
-- ----------------------------
DROP TABLE IF EXISTS "extra";
CREATE TABLE "extra" (
  "link_id" INTEGER,
  "action_data" VARCHAR,
  "weight" INTEGER DEFAULT 0,
  "info" TEXT,
  PRIMARY KEY ("link_id")
);

-- ----------------------------
-- Table structure for groups
-- ----------------------------
DROP TABLE IF EXISTS "groups";
CREATE TABLE "groups" (
  "id" INTEGER NOT NULL,
  "name" TEXT,
  PRIMARY KEY ("id")
);

-- ----------------------------
-- Table structure for items
-- ----------------------------
DROP TABLE IF EXISTS "items";
CREATE TABLE "items" (
  "id" integer NOT NULL,
  "name" text,
  "sort_order" integer,
  "group" integer,
  "allow_deposit" integer DEFAULT NULL,
  "crystal_type" text DEFAULT NULL,
  "type" text,
  "default_action" text DEFAULT NULL,
  "is_tradable" text DEFAULT NULL,
  "is_dropable" text DEFAULT NULL,
  "is_sellable" text DEFAULT NULL,
  "is_stackable" text DEFAULT NULL,
  "etcitem_type" text DEFAULT NULL,
  "is_depositable" text DEFAULT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "fk_group" FOREIGN KEY ("group") REFERENCES "groups" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ----------------------------
-- Table structure for link
-- ----------------------------
DROP TABLE IF EXISTS "link";
CREATE TABLE "link" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "start_point_id" INTEGER NOT NULL,
  "end_point_id" INTEGER NOT NULL,
  "one_way" INTEGER NOT NULL DEFAULT (0),
  "temp_link" INTEGER NOT NULL DEFAULT (0),
  FOREIGN KEY ("start_point_id") REFERENCES "POINT" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY ("end_point_id") REFERENCES "POINT" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- ----------------------------
-- Table structure for point
-- ----------------------------
DROP TABLE IF EXISTS "point";
CREATE TABLE "point" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "x" REAL,
  "y" REAL,
  "z" REAL,
  "name" VARCHAR,
  "radius" REAL NOT NULL DEFAULT (0),
  "temp_point" INTEGER NOT NULL DEFAULT (0)
);

-- ----------------------------
-- Table structure for point_extra
-- ----------------------------
DROP TABLE IF EXISTS "point_extra";
CREATE TABLE "point_extra" (
  "pointId" INTEGER NOT NULL,
  "catName" TEXT,
  "pointDescr" TEXT,
  PRIMARY KEY ("pointId")
);

-- ----------------------------
-- Table structure for sqlite_sequence
-- ----------------------------
DROP TABLE IF EXISTS "sqlite_sequence";
CREATE TABLE "sqlite_sequence" (
  "name",
  "seq"
);

-- ----------------------------
-- Table structure for sqlite_stat1
-- ----------------------------
DROP TABLE IF EXISTS "sqlite_stat1";
CREATE TABLE "sqlite_stat1" (
  "tbl",
  "idx",
  "stat"
);

-- ----------------------------
-- Indexes structure for table items
-- ----------------------------
CREATE INDEX "idx_itemname"
ON "items" (
  "name" ASC
);
CREATE INDEX "idx_itemsort"
ON "items" (
  "sort_order" DESC
);

-- ----------------------------
-- Auto increment value for link
-- ----------------------------
UPDATE "sqlite_sequence" SET seq = 13597 WHERE name = 'link';

-- ----------------------------
-- Auto increment value for point
-- ----------------------------
UPDATE "sqlite_sequence" SET seq = 12925 WHERE name = 'point';

PRAGMA foreign_keys = true;
