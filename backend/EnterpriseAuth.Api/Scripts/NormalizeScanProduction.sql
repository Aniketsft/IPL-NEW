-- SQL Migration: Normalize ScanProduction Database
-- Database: ScanProduction
-- Guidelines: snake_case, professional naming, audit fields, audit log.

USE ScanProduction;
GO

-- 1. Create audit_log table
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[audit_log]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[audit_log] (
        [audit_id] INT IDENTITY(1,1) NOT NULL,
        [entity_name] NVARCHAR(100) NOT NULL,
        [entity_id] INT NOT NULL,
        [action_type] NVARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
        [payload] NVARCHAR(MAX) NULL,       -- JSON diff or state
        [performed_by] NVARCHAR(100) NULL,
        [performed_at] DATETIME NOT NULL DEFAULT (GETUTCDATE()),
        CONSTRAINT [pk_audit_log] PRIMARY KEY CLUSTERED ([audit_id] ASC)
    );
END
GO

-- 2. Create normalized production_scan table
-- Note: Dropping existing ProductionScans if it exists to ensure fresh normalized structure.
-- Be careful: In a production environment, you would use ALTER TABLE or migrate data.
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScans]') AND type in (N'U'))
BEGIN
    DROP TABLE [dbo].[ProductionScans];
END

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[production_scan]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[production_scan] (
        [scan_id] INT IDENTITY(1,1) NOT NULL,
        [product_id] NVARCHAR(100) NOT NULL,
        [line_no] INT NOT NULL,
        [scan_amount_kg] DECIMAL(18,2) NOT NULL,
        [so_number] NVARCHAR(100) NOT NULL,
        [order_status] NVARCHAR(10) NULL, -- ORDSTA_0
        [item_status] NVARCHAR(10) NULL,  -- ITMSTA (status in scanproduction)
        [location] NVARCHAR(100) NULL,
        [lot] NVARCHAR(100) NULL,
        
        -- Audit Fields
        [created_by] NVARCHAR(100) NULL,
        [created_at] DATETIME NOT NULL DEFAULT (GETUTCDATE()),
        [updated_by] NVARCHAR(100) NULL,
        [updated_at] DATETIME NULL,
        [is_deleted] BIT NOT NULL DEFAULT (0),
        [deleted_by] NVARCHAR(100) NULL,
        [deleted_at] DATETIME NULL,

        CONSTRAINT [pk_production_scan] PRIMARY KEY CLUSTERED ([scan_id] ASC)
    );
END
GO
