-- SQL Migration: Create Item Status Lookup Table
-- Database: ScanProduction

USE ScanProduction;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[item_status_lookup]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[item_status_lookup] (
        [status_code] NVARCHAR(10) NOT NULL,
        [status_name] NVARCHAR(100) NOT NULL,
        CONSTRAINT [pk_item_status_lookup] PRIMARY KEY CLUSTERED ([status_code] ASC)
    );

    -- Insert Default Statuses
    INSERT INTO [dbo].[item_status_lookup] ([status_code], [status_name]) VALUES ('Q', 'Quarantine');
    INSERT INTO [dbo].[item_status_lookup] ([status_code], [status_name]) VALUES ('A', 'Accepted');
    INSERT INTO [dbo].[item_status_lookup] ([status_code], [status_name]) VALUES ('R', 'Rejected');
END
GO
