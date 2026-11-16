-- ============================================
-- HUL DBMS Mini Project - User Setup Script (v2)
-- ============================================

USE hul_db;

-- Drop the table if it already exists to make this script runnable multiple times
DROP TABLE IF EXISTS Users;

-- ============================================
-- 9. USER AUTHENTICATION
-- ============================================

CREATE TABLE Users (
    UserID INT PRIMARY KEY AUTO_INCREMENT,
    Username VARCHAR(50) NOT NULL UNIQUE,
    -- This column will be populated by our Python script
    PasswordHash VARCHAR(255) NOT NULL,
    Role VARCHAR(20) NOT NULL CHECK (Role IN ('admin', 'warehouse'))
);

-- NOTE: We no longer insert users here.
-- The 'create_users.py' script will handle this.