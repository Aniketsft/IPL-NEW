using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public static class DbInitializer
    {
        public static async Task SeedAsync(ApplicationDbContext context, IPasswordHasher hasher)
        {
            Console.WriteLine("[DbInitializer] Checking if database exists...");
            await context.Database.EnsureCreatedAsync();
            Console.WriteLine("[DbInitializer] Database ensured.");

            // FORCE SCHEMA CREATION: Ensure TokenVersion column exists because EnsureCreated might skip it if DB already exists
            try {
                await context.Database.ExecuteSqlRawAsync(@"
                    IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Users' AND COLUMN_NAME = 'TokenVersion')
                    BEGIN
                        ALTER TABLE [Users] ADD [TokenVersion] uniqueidentifier NOT NULL DEFAULT NEWID();
                    END
                ");
            } catch (Exception ex) {
                Console.WriteLine("[DbInitializer] TokenVersion column warning: " + ex.Message);
            }

            // FORCE SCHEMA CREATION: Create UserPermissions table if missing
            try {
                await context.Database.ExecuteSqlRawAsync(@"
                    IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='UserPermissions' and xtype='U')
                    BEGIN
                        CREATE TABLE [UserPermissions] (
                            [PermissionsId] uniqueidentifier NOT NULL,
                            [UsersId] uniqueidentifier NOT NULL,
                            CONSTRAINT [PK_UserPermissions] PRIMARY KEY ([PermissionsId], [UsersId]),
                            CONSTRAINT [FK_UserPermissions_Permissions_PermissionsId] FOREIGN KEY ([PermissionsId]) REFERENCES [Permissions] ([Id]) ON DELETE CASCADE,
                            CONSTRAINT [FK_UserPermissions_Users_UsersId] FOREIGN KEY ([UsersId]) REFERENCES [Users] ([Id]) ON DELETE CASCADE
                        );
                    END
                ");
            } catch (Exception ex) {
                Console.WriteLine("[DbInitializer] Table creation warning: " + ex.Message);
            }

            // Seed Permissions (Hierarchical Tree Structure)
            // Format: Module -> SubModule(s) -> Child(ren)
            // The order here reflects the Home Screen priority requested.
            var hierarchy = new List<(string Module, string[] SubModules)>
            {
                ( "app", new[] { "home" } ),
                ( "logistics", new[] { "receipt", "delivery", "transfer" } ),
                ( "manufacturing", new[] { "all" } ),
                ( "inventory", new[] { "stock_control", "picking", "by_identifier" } ),
                ( "administration", new[] { "user_management", "sync_logs" } ),
                ( "settings", new[] { "general", "printer" } )
            };
            
            var actions = new[] { "Create", "Read", "Update", "Delete" };
            var existingPermissions = await context.Permissions.ToDictionaryAsync(p => p.Name.ToLowerInvariant());
            var permissionsToAdd = new List<Permission>();

            foreach (var item in hierarchy)
            {
                foreach (var subModule in item.SubModules)
                {
                    foreach (var action in actions)
                    {
                        var permName = $"{item.Module}.{subModule}.{action}".ToLowerInvariant();
                        if (!existingPermissions.ContainsKey(permName))
                        {
                            permissionsToAdd.Add(new Permission 
                            { 
                                Id = Guid.NewGuid(), 
                                Name = permName, 
                                Description = $"{action} access to {subModule} in {item.Module}" 
                            });
                        }
                    }
                }
            }

            if (permissionsToAdd.Any())
            {
                await context.Permissions.AddRangeAsync(permissionsToAdd);
                await context.SaveChangesAsync();
                Console.WriteLine($"[DbInitializer] Added {permissionsToAdd.Count} new permissions.");
            }

            // Seed Roles
            var allPermissions = await context.Permissions.ToListAsync();
            Console.WriteLine($"[DbInitializer] Total permissions in DB: {allPermissions.Count}");

            var adminRole = await context.Roles.Include(r => r.Permissions).FirstOrDefaultAsync(r => r.Name == "Admin");
            if (adminRole == null)
            {
                adminRole = new Role
                {
                    Id = Guid.NewGuid(),
                    Name = "Admin",
                    Description = "Full system access",
                    Permissions = new List<Permission>(allPermissions)
                };
                await context.Roles.AddAsync(adminRole);
                Console.WriteLine("[DbInitializer] Created Admin role with all permissions.");
            }
            else
            {
                // Brute force update: Clear and re-add to ensure sync
                adminRole.Permissions.Clear();
                foreach(var p in allPermissions) adminRole.Permissions.Add(p);
                Console.WriteLine($"[DbInitializer] Synchronized Admin role with {allPermissions.Count} permissions.");
            }

            // Ensure other roles exist
            // (Removed Operator role seeding per user request)

            await context.SaveChangesAsync();

            // Seed Admin User
            var adminUser = await context.Users
                .Include(u => u.Roles)
                .FirstOrDefaultAsync(u => u.Username == "admin");

            if (adminUser == null)
            {
                var passwordHash = hasher.HashPassword("password", out string salt);
                adminUser = new User
                {
                    Id = Guid.NewGuid(),
                    Username = "admin",
                    Email = "admin@enterprise.com",
                    PasswordHash = passwordHash,
                    Salt = salt,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    Roles = new List<Role> { adminRole }
                };
                await context.Users.AddAsync(adminUser);
                Console.WriteLine("[DbInitializer] Created 'admin' user and assigned Admin role.");
            }
            else
            {
                // Ensure Admin Role Link and SYNC PERMISSIONS
                if (!adminUser.Roles.Any(r => r.Name == "Admin"))
                {
                    adminUser.Roles.Add(adminRole);
                    Console.WriteLine("[DbInitializer] Assigned missing Admin role to existing 'admin' user.");
                }
                
                // Force sync the user's role permissions if they were stale
            }

            await context.SaveChangesAsync();
            Console.WriteLine("[DbInitializer] Seeding completed successfully.");
        }

        public static async Task MigrateScanProductionAsync(ScanProductionDbContext context)
        {
            try
            {
                // V2 NORMALIZED SCHEMA MIGRATION
                // Creates new normalized tables and ensures EF Core model matches DB
                var migrationSql = @"
                    -- Create ItemPreparationStatus table (replaces IsPrepared on production_scan + salesorderdetailscutsbulk)
                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ItemPreparationStatus]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[ItemPreparationStatus] (
                            [Id]          INT IDENTITY(1,1) PRIMARY KEY,
                            [SoNumber]    NVARCHAR(100) NOT NULL,
                            [ItemCode]    NVARCHAR(100) NOT NULL,
                            [IsPrepared]  BIT NOT NULL DEFAULT 0,
                            [UpdatedBy]   NVARCHAR(100) NULL,
                            [UpdatedAt]   DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
                            CONSTRAINT UQ_ItemPrepStatus_SoItem UNIQUE (SoNumber, ItemCode)
                        );
                        CREATE INDEX IX_ItemPrepStatus_SoNumber ON [dbo].[ItemPreparationStatus] (SoNumber);
                        PRINT 'Created ItemPreparationStatus table';
                    END

                    -- Create SalesOrderHeaders table
                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderHeaders]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[SalesOrderHeaders] (
                            [Id]            INT IDENTITY(1,1) PRIMARY KEY,
                            [SoNumber]      NVARCHAR(100) NOT NULL UNIQUE,
                            [PoNumber]      NVARCHAR(100) NULL,
                            [DeliveryDate]  DATETIME NULL,
                            [Salesman]      NVARCHAR(200) NULL,
                            [CustomerCode]  NVARCHAR(100) NULL,
                            [CustomerName]  NVARCHAR(255) NULL,
                            [Site]          NVARCHAR(100) NULL,
                            [Status]        INT NOT NULL DEFAULT 1,
                            [CreatedAt]     DATETIME NOT NULL DEFAULT GETUTCDATE(),
                            [UpdatedAt]     DATETIME NULL
                        );
                        PRINT 'Created SalesOrderHeaders table';
                    END

                    -- Create OrderShipmentStatus table (replaces SHIPMENT_SENTINEL in production_scan)
                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[OrderShipmentStatus]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[OrderShipmentStatus] (
                            [Id]                    INT IDENTITY(1,1) PRIMARY KEY,
                            [SoNumber]              NVARCHAR(100) NOT NULL UNIQUE,
                            [IsPreparedForShipment] BIT NOT NULL DEFAULT 0,
                            [IsValidated]           BIT NOT NULL DEFAULT 0,
                            [UpdatedBy]             NVARCHAR(100) NULL,
                            [UpdatedAt]             DATETIME2 NOT NULL DEFAULT GETUTCDATE()
                        );
                        PRINT 'Created OrderShipmentStatus table';
                    END

                    -- Create OrderStatusHistory table (replaces ORDER-CLOSE sentinel in production_scan)
                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[OrderStatusHistory]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[OrderStatusHistory] (
                            [Id]        INT IDENTITY(1,1) PRIMARY KEY,
                            [SoNumber]  NVARCHAR(100) NOT NULL,
                            [Status]    TINYINT NOT NULL,
                            [ChangedBy] NVARCHAR(100) NULL,
                            [ChangedAt] DATETIME2 NOT NULL DEFAULT GETUTCDATE()
                        );
                        CREATE INDEX IX_OrderStatusHistory_SoNumber ON [dbo].[OrderStatusHistory] (SoNumber);
                        PRINT 'Created OrderStatusHistory table';
                    END

                    -- Rename tables to PascalCase (if old snake_case tables exist)
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[production_scan]') AND type in (N'U'))
                        AND NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScans]') AND type in (N'U'))
                    BEGIN
                        EXEC sp_rename 'dbo.production_scan', 'ProductionScans';
                        PRINT 'Renamed production_scan -> ProductionScans';
                    END

                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[salesorderdetailscutsbulk]') AND type in (N'U'))
                        AND NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderDetails]') AND type in (N'U'))
                    BEGIN
                        EXEC sp_rename 'dbo.salesorderdetailscutsbulk', 'SalesOrderDetails';
                        PRINT 'Renamed salesorderdetailscutsbulk -> SalesOrderDetails';
                    END

                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[audit_log]') AND type in (N'U'))
                        AND NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AuditLogs]') AND type in (N'U'))
                    BEGIN
                        EXEC sp_rename 'dbo.audit_log', 'AuditLogs';
                        PRINT 'Renamed audit_log -> AuditLogs';
                    END

                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[cut_bulk_entries]') AND type in (N'U'))
                        AND NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CutBulkEntries]') AND type in (N'U'))
                    BEGIN
                        EXEC sp_rename 'dbo.cut_bulk_entries', 'CutBulkEntries';
                        PRINT 'Renamed cut_bulk_entries -> CutBulkEntries';
                    END

                    -- Rename columns to PascalCase on ProductionScans (if old names exist)
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScans]') AND type in (N'U'))
                    BEGIN
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'scan_id')
                            EXEC sp_rename 'ProductionScans.scan_id', 'ScanId', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'product_id')
                            EXEC sp_rename 'ProductionScans.product_id', 'ItemCode', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'line_no')
                            EXEC sp_rename 'ProductionScans.line_no', 'LineNo', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'scan_amount_kg')
                            EXEC sp_rename 'ProductionScans.scan_amount_kg', 'ScanAmountKg', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'so_number')
                            EXEC sp_rename 'ProductionScans.so_number', 'SoNumber', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'item_status')
                            EXEC sp_rename 'ProductionScans.item_status', 'ItemStatus', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'location')
                            EXEC sp_rename 'ProductionScans.location', 'Location', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'lot')
                            EXEC sp_rename 'ProductionScans.lot', 'Lot', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'created_by')
                            EXEC sp_rename 'ProductionScans.created_by', 'CreatedBy', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'created_at')
                            EXEC sp_rename 'ProductionScans.created_at', 'CreatedAt', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'updated_by')
                            EXEC sp_rename 'ProductionScans.updated_by', 'UpdatedBy', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'updated_at')
                            EXEC sp_rename 'ProductionScans.updated_at', 'UpdatedAt', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'is_deleted')
                            EXEC sp_rename 'ProductionScans.is_deleted', 'IsDeleted', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'deleted_by')
                            EXEC sp_rename 'ProductionScans.deleted_by', 'DeletedBy', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'deleted_at')
                            EXEC sp_rename 'ProductionScans.deleted_at', 'DeletedAt', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'sync_id')
                            EXEC sp_rename 'ProductionScans.sync_id', 'SyncId', 'COLUMN';
                        PRINT 'Renamed ProductionScans columns to PascalCase';
                    END

                    -- Rename columns on AuditLogs
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AuditLogs]') AND type in (N'U'))
                    BEGIN
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'audit_id')
                            EXEC sp_rename 'AuditLogs.audit_id', 'AuditId', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'entity_name')
                            EXEC sp_rename 'AuditLogs.entity_name', 'EntityName', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'entity_id')
                            EXEC sp_rename 'AuditLogs.entity_id', 'EntityId', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'action_type')
                            EXEC sp_rename 'AuditLogs.action_type', 'ActionType', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'payload')
                            EXEC sp_rename 'AuditLogs.payload', 'Payload', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'performed_by')
                            EXEC sp_rename 'AuditLogs.performed_by', 'PerformedBy', 'COLUMN';
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'performed_at')
                            EXEC sp_rename 'AuditLogs.performed_at', 'PerformedAt', 'COLUMN';
                        PRINT 'Renamed AuditLogs columns to PascalCase';
                    END

                    -- RECONCILIATION: Add missing sync columns to existing tables
                    -- 1. CutBulkEntries
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CutBulkEntries]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CutBulkEntries' AND COLUMN_NAME = 'DeviceId')
                            EXEC('ALTER TABLE CutBulkEntries ADD DeviceId NVARCHAR(100) NULL;');
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CutBulkEntries' AND COLUMN_NAME = 'SyncStatus')
                            EXEC('ALTER TABLE CutBulkEntries ADD SyncStatus NVARCHAR(50) NULL;');
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CutBulkEntries' AND COLUMN_NAME = 'SyncTimestamp')
                            EXEC('ALTER TABLE CutBulkEntries ADD SyncTimestamp DATETIME NULL;');
                    END

                    -- 2. SalesOrderDetails
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderDetails]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'SyncStatus')
                            EXEC('ALTER TABLE SalesOrderDetails ADD SyncStatus NVARCHAR(10) NOT NULL DEFAULT ''Synced'';');
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'CreatedAt')
                            EXEC('ALTER TABLE SalesOrderDetails ADD CreatedAt DATETIME NULL;');
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'BarcodeType')
                            EXEC('ALTER TABLE SalesOrderDetails ADD BarcodeType NVARCHAR(50) NOT NULL DEFAULT ''Variable Weight'';');
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'ManufacturedQuantity')
                            EXEC('ALTER TABLE SalesOrderDetails ADD ManufacturedQuantity DECIMAL(18,2) NOT NULL DEFAULT 0;');
                    END

                    -- RECONCILIATION: Move IsValidated from ItemPreparationStatus to OrderShipmentStatus if needed
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ItemPreparationStatus' AND COLUMN_NAME = 'IsValidated')
                    BEGIN
                        -- Ensure IsValidated exists on target
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'OrderShipmentStatus' AND COLUMN_NAME = 'IsValidated')
                            EXEC('ALTER TABLE OrderShipmentStatus ADD IsValidated BIT NOT NULL DEFAULT 0;');

                        -- Move data (if any was set to true)
                        EXEC('UPDATE oss
                             SET oss.IsValidated = 1
                             FROM OrderShipmentStatus oss
                             INNER JOIN ItemPreparationStatus ips ON oss.SoNumber = ips.SoNumber
                             WHERE ips.IsValidated = 1;');
                        
                        -- Drop constraints before dropping column
                        DECLARE @ConstraintName_Val NVARCHAR(200);
                        WHILE EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ItemPreparationStatus') AND c.name = 'IsValidated')
                        BEGIN
                            SELECT TOP 1 @ConstraintName_Val = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ItemPreparationStatus') AND c.name = 'IsValidated';
                            EXEC('ALTER TABLE dbo.ItemPreparationStatus DROP CONSTRAINT [' + @ConstraintName_Val + ']');
                        END

                        -- Drop from item table
                        EXEC('ALTER TABLE dbo.ItemPreparationStatus DROP COLUMN IsValidated;');
                        PRINT 'Reconciled IsValidated: Moved from ItemPreparationStatus to OrderShipmentStatus';
                    END
                    ELSE IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'OrderShipmentStatus' AND COLUMN_NAME = 'IsValidated')
                    BEGIN
                        EXEC('ALTER TABLE OrderShipmentStatus ADD IsValidated BIT NOT NULL DEFAULT 0;');
                        PRINT 'Added IsValidated to OrderShipmentStatus';
                    END

                    -- Migrate sentinel data into new tables (idempotent)
                    -- 1. IsPrepared sentinels → ItemPreparationStatus
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'is_prepared')
                    BEGIN
                        EXEC('INSERT INTO ItemPreparationStatus (SoNumber, ItemCode, IsPrepared, UpdatedBy, UpdatedAt)
                             SELECT DISTINCT SoNumber, ItemCode, 1, ''migration'', GETUTCDATE()
                             FROM dbo.ProductionScans
                             WHERE is_prepared = 1 AND IsDeleted = 0
                               AND NOT EXISTS (
                                 SELECT 1 FROM ItemPreparationStatus ips 
                                 WHERE ips.SoNumber = dbo.ProductionScans.SoNumber AND ips.ItemCode = dbo.ProductionScans.ItemCode
                               );');
                        PRINT 'Migrated IsPrepared data to ItemPreparationStatus';
                    END

                    -- Also from SalesOrderDetails
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'IsPrepared')
                    BEGIN
                        EXEC('INSERT INTO ItemPreparationStatus (SoNumber, ItemCode, IsPrepared, UpdatedBy, UpdatedAt)
                             SELECT SoNumber, ItemCode, 1, ''migration'', GETUTCDATE()
                             FROM dbo.SalesOrderDetails
                             WHERE IsPrepared = 1
                               AND NOT EXISTS (
                                 SELECT 1 FROM ItemPreparationStatus ips 
                                 WHERE ips.SoNumber = dbo.SalesOrderDetails.SoNumber AND ips.ItemCode = dbo.SalesOrderDetails.ItemCode
                               );');
                        PRINT 'Migrated IsPrepared from SalesOrderDetails to ItemPreparationStatus';
                    END

                    -- 3. Backfill SalesOrderHeaders from SalesOrderDetails
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderHeaders]') AND type in (N'U'))
                       AND EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderDetails]') AND type in (N'U'))
                    BEGIN
                        EXEC('INSERT INTO SalesOrderHeaders (SoNumber, CreatedAt)
                             SELECT DISTINCT SoNumber, GETUTCDATE()
                             FROM dbo.SalesOrderDetails
                             WHERE NOT EXISTS (SELECT 1 FROM SalesOrderHeaders soh WHERE soh.SoNumber = dbo.SalesOrderDetails.SoNumber);');
                        PRINT 'Backfilled SalesOrderHeaders from SalesOrderDetails';
                    END

                    -- 4. IsPreparedForShipment sentinels → OrderShipmentStatus
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'is_prepared_for_shipment')
                    BEGIN
                        EXEC('INSERT INTO OrderShipmentStatus (SoNumber, IsPreparedForShipment, UpdatedBy, UpdatedAt)
                             SELECT DISTINCT SoNumber, 1, ''migration'', GETUTCDATE()
                             FROM dbo.ProductionScans
                             WHERE is_prepared_for_shipment = 1 AND IsDeleted = 0
                               AND NOT EXISTS (
                                 SELECT 1 FROM OrderShipmentStatus oss WHERE oss.SoNumber = dbo.ProductionScans.SoNumber
                               );');
                        PRINT 'Migrated IsPreparedForShipment to OrderShipmentStatus';
                    END

                    -- 3. ORDER-CLOSE sentinels → OrderStatusHistory
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'order_status')
                    BEGIN
                        EXEC('INSERT INTO OrderStatusHistory (SoNumber, Status, ChangedBy, ChangedAt)
                             SELECT DISTINCT SoNumber, 2, CreatedBy, CreatedAt
                             FROM dbo.ProductionScans
                             WHERE order_status = ''2'' AND IsDeleted = 0
                               AND NOT EXISTS (
                                 SELECT 1 FROM OrderStatusHistory osh WHERE osh.SoNumber = dbo.ProductionScans.SoNumber AND osh.Status = 2
                               );');
                        PRINT 'Migrated order close status to OrderStatusHistory';
                    END

                    -- 4. Delete sentinel rows from ProductionScans
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'order_status')
                    BEGIN
                        EXEC('DELETE FROM dbo.ProductionScans 
                             WHERE CreatedBy LIKE ''%sentinel%''
                                OR ItemCode IN (''ORDER-CLOSE'', ''CLOSE_SENTINEL'', ''SHIPMENT_SENTINEL'');');
                        PRINT 'Deleted sentinel rows from ProductionScans';
                    END

                    -- 5. Drop obsolete columns from ProductionScans
                    -- First, drop any constraints (like defaults) that prevent the drop
                    DECLARE @ConstraintName NVARCHAR(200);
                    
                    -- Drop constraints for is_prepared
                    WHILE EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ProductionScans') AND c.name = 'is_prepared')
                    BEGIN
                        SELECT TOP 1 @ConstraintName = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ProductionScans') AND c.name = 'is_prepared';
                        EXEC('ALTER TABLE dbo.ProductionScans DROP CONSTRAINT [' + @ConstraintName + ']');
                    END

                    -- Drop constraints for is_prepared_for_shipment
                    WHILE EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ProductionScans') AND c.name = 'is_prepared_for_shipment')
                    BEGIN
                        SELECT TOP 1 @ConstraintName = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ProductionScans') AND c.name = 'is_prepared_for_shipment';
                        EXEC('ALTER TABLE dbo.ProductionScans DROP CONSTRAINT [' + @ConstraintName + ']');
                    END

                    -- Drop constraints for order_status
                    WHILE EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ProductionScans') AND c.name = 'order_status')
                    BEGIN
                        SELECT TOP 1 @ConstraintName = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.ProductionScans') AND c.name = 'order_status';
                        EXEC('ALTER TABLE dbo.ProductionScans DROP CONSTRAINT [' + @ConstraintName + ']');
                    END

                    -- Now safe to drop columns
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'is_prepared')
                        EXEC('ALTER TABLE dbo.ProductionScans DROP COLUMN is_prepared;');
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'is_prepared_for_shipment')
                        EXEC('ALTER TABLE dbo.ProductionScans DROP COLUMN is_prepared_for_shipment;');
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScans' AND COLUMN_NAME = 'order_status')
                        EXEC('ALTER TABLE dbo.ProductionScans DROP COLUMN order_status;');

                    -- 6. Drop obsolete columns from SalesOrderDetails
                    -- Drop constraints for IsPrepared
                    WHILE EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.SalesOrderDetails') AND c.name = 'IsPrepared')
                    BEGIN
                        SELECT TOP 1 @ConstraintName = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.SalesOrderDetails') AND c.name = 'IsPrepared';
                        EXEC('ALTER TABLE dbo.SalesOrderDetails DROP CONSTRAINT [' + @ConstraintName + ']');
                    END

                    -- Drop constraints for IsPreparedForShipment
                    WHILE EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.SalesOrderDetails') AND c.name = 'IsPreparedForShipment')
                    BEGIN
                        SELECT TOP 1 @ConstraintName = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE c.object_id = OBJECT_ID('dbo.SalesOrderDetails') AND c.name = 'IsPreparedForShipment';
                        EXEC('ALTER TABLE dbo.SalesOrderDetails DROP CONSTRAINT [' + @ConstraintName + ']');
                    END

                    -- Now safe to drop columns
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'IsPrepared')
                        EXEC('ALTER TABLE dbo.SalesOrderDetails DROP COLUMN IsPrepared;');
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderDetails' AND COLUMN_NAME = 'IsPreparedForShipment')
                        EXEC('ALTER TABLE dbo.SalesOrderDetails DROP COLUMN IsPreparedForShipment;');

                    -- 7. Add performance indexes
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScans]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_ProductionScans_SoItemDeleted')
                            EXEC('CREATE INDEX IX_ProductionScans_SoItemDeleted ON ProductionScans (SoNumber, ItemCode, IsDeleted);');

                        IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_ProductionScans_SyncId')
                            EXEC('CREATE UNIQUE INDEX IX_ProductionScans_SyncId ON ProductionScans (SyncId) WHERE SyncId IS NOT NULL;');
                    END

                    IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_AuditLogs_EntityLookup')
                        CREATE INDEX IX_AuditLogs_EntityLookup ON AuditLogs (EntityName, EntityId);

                    PRINT 'V2 Normalized Schema Migration completed successfully';
                ";

                await context.Database.ExecuteSqlRawAsync(migrationSql);
                Console.WriteLine("[DbInitializer] ScanProduction V2 normalized schema migration completed successfully.");

                // Start Phase 3: Enterprise Redesign (UUID-based Architecture)
                await MigrateEnterpriseRedesignAsync(context);

                // Ensure DeviceId columns are present in LabelAudits and AuditLogs
                await EnsureDeviceIdColumnsAsync(context);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DbInitializer] CRITICAL: ScanProduction migration failed: {ex.Message}");
                throw; 
            }
        }

        public static async Task MigrateEnterpriseRedesignAsync(ScanProductionDbContext context)
        {
            try
            {
                var migrationSql = @"
                    -- 1. Create Enterprise Redesign Tables
                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrders]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[SalesOrders] (
                            [Id]                UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
                            [SourceOrderId]     NVARCHAR(100) NOT NULL UNIQUE,
                            [SourceSystem]      NVARCHAR(20) NOT NULL DEFAULT 'X3',
                            [PoNumber]          NVARCHAR(100) NULL,
                            [OrderDate]         DATETIME NULL,
                            [DeliveryDate]      DATETIME NULL,
                            [Salesman]          NVARCHAR(200) NULL,
                            [CustomerCode]      NVARCHAR(100) NULL,
                            [CustomerName]      NVARCHAR(255) NULL,
                            [Site]              NVARCHAR(100) NULL,
                            [Status]            INT NOT NULL DEFAULT 1,
                            [IsArchived]        BIT NOT NULL DEFAULT 0,
                            [CreatedAt]         DATETIME NOT NULL DEFAULT GETUTCDATE(),
                            [UpdatedAt]         DATETIME NULL
                        );
                        PRINT 'Created SalesOrders (Enterprise) table';
                    END

                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderLines]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[SalesOrderLines] (
                            [Id]                UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
                            [SalesOrderId]      UNIQUEIDENTIFIER NOT NULL,
                            [ItemCode]          NVARCHAR(100) NOT NULL,
                            [Description]       NVARCHAR(255) NULL,
                            [OrderedQuantity]   DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [Unit]              NVARCHAR(50) NULL,
                            [Location]          NVARCHAR(100) NULL,
                            [Lot]                NVARCHAR(100) NULL,
                            [LineNumber]        INT NOT NULL DEFAULT 1,
                            [LineStatus]        INT NOT NULL DEFAULT 1,
                            [CreatedAt]         DATETIME NOT NULL DEFAULT GETUTCDATE(),
                            CONSTRAINT [FK_SalesOrderLine_Order] FOREIGN KEY ([SalesOrderId]) REFERENCES [SalesOrders]([Id]) ON DELETE CASCADE
                        );
                        CREATE INDEX IX_SalesOrderLine_Order ON [dbo].[SalesOrderLines] ([SalesOrderId]);
                        PRINT 'Created SalesOrderLines table';
                    END
                    ELSE
                    BEGIN
                        -- Migration: Add LineNumber if missing
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrderLines' AND COLUMN_NAME = 'LineNumber')
                        BEGIN
                            ALTER TABLE SalesOrderLines ADD [LineNumber] INT NOT NULL DEFAULT 1;
                            PRINT 'Added LineNumber to SalesOrderLines';
                        END
                    END

                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScanTransactions]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[ProductionScanTransactions] (
                            [Id]                UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
                            [SalesOrderLineId]  UNIQUEIDENTIFIER NOT NULL,
                            [ScanAmountKg]      DECIMAL(18, 5) NOT NULL,
                            [Barcode]           NVARCHAR(100) NULL,
                            [LotNumber]         NVARCHAR(100) NULL,
                            [Location]          NVARCHAR(100) NULL,
                            [SyncId]            NVARCHAR(100) NOT NULL UNIQUE,
                            [ItemStatus]        NVARCHAR(100) NULL,
                            [DeviceId]          NVARCHAR(100) NULL,
                            [CreatedBy]         NVARCHAR(100) NULL,
                            [CreatedAt]         DATETIME NOT NULL DEFAULT GETUTCDATE(),
                            [IsDeleted]         BIT NOT NULL DEFAULT 0,
                            [IsArchived]        BIT NOT NULL DEFAULT 0,
                            CONSTRAINT [FK_Scan_OrderLine] FOREIGN KEY ([SalesOrderLineId]) REFERENCES [SalesOrderLines]([Id]) ON DELETE CASCADE
                        );
                        CREATE INDEX IX_Scan_Line ON [dbo].[ProductionScanTransactions] ([SalesOrderLineId]);
                        PRINT 'Created ProductionScanTransactions table';
                    END

                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionLineStates]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[ProductionLineStates] (
                            [SalesOrderLineId]    UNIQUEIDENTIFIER PRIMARY KEY,
                            [TotalManufacturedQty] DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [TotalPreparedQty]     DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [TotalValidatedQty]    DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [IsLineCompleted]      BIT NOT NULL DEFAULT 0,
                            [LastScanId]           UNIQUEIDENTIFIER NULL,
                            [UpdatedAt]            DATETIME NOT NULL DEFAULT GETUTCDATE(),
                            CONSTRAINT [FK_State_OrderLine] FOREIGN KEY ([SalesOrderLineId]) REFERENCES [SalesOrderLines]([Id]) ON DELETE CASCADE
                        );
                        PRINT 'Created ProductionLineStates table';
                    END

                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Excesses]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[Excesses] (
                            [Id]                        UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
                            [SourceBulkSoNumber]        NVARCHAR(100) NOT NULL,
                            [ItemCode]                  NVARCHAR(100) NOT NULL,
                            [DeliveryDate]              DATETIME NOT NULL,
                            [TotalManufacturedQuantity] DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [AllocatedQuantity]         DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [RemainingExcess]           DECIMAL(18, 5) NOT NULL DEFAULT 0,
                            [CreatedAt]                 DATETIME NOT NULL DEFAULT GETUTCDATE(),
                            [CreatedBy]                 NVARCHAR(200) NULL,
                            [UpdatedAt]                 DATETIME NULL,
                            [UpdatedBy]                 NVARCHAR(200) NULL
                        );
                        CREATE UNIQUE INDEX [UQ_Excess_BulkSO_Item] ON [dbo].[Excesses] ([SourceBulkSoNumber], [ItemCode]);
                        CREATE INDEX [IX_Excess_Date_Item] ON [dbo].[Excesses] ([DeliveryDate], [ItemCode]);
                        PRINT 'Created Excesses table';
                    END

                    -- 2. DATA PORTING (Idempotent)
                    -- A. Port Orders
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderHeaders]') AND type in (N'U'))
                    BEGIN
                        EXEC('INSERT INTO SalesOrders (SourceOrderId, PoNumber, DeliveryDate, Salesman, CustomerCode, CustomerName, Site, Status, CreatedAt)
                        SELECT SoNumber, PoNumber, DeliveryDate, Salesman, CustomerCode, CustomerName, Site, Status, CreatedAt
                        FROM dbo.SalesOrderHeaders soh
                        WHERE NOT EXISTS (SELECT 1 FROM SalesOrders so WHERE so.SourceOrderId = soh.SoNumber);');
                    END

                    -- B. Port Lines
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderDetails]') AND type in (N'U'))
                    BEGIN
                        EXEC('INSERT INTO SalesOrderLines (SalesOrderId, ItemCode, Description, OrderedQuantity, Unit, CreatedAt)
                        SELECT so.Id, sod.ItemCode, sod.Description, sod.Quantity, ''KG'', ISNULL(sod.CreatedAt, GETUTCDATE())
                        FROM dbo.SalesOrderDetails sod
                        JOIN dbo.SalesOrders so ON sod.SoNumber = so.SourceOrderId
                        WHERE NOT EXISTS (
                            SELECT 1 FROM SalesOrderLines sol 
                            WHERE sol.SalesOrderId = so.Id AND sol.ItemCode = sod.ItemCode
                        );');
                    END

                    -- C. Port Transactions
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScans]') AND type in (N'U'))
                    BEGIN
                        EXEC('INSERT INTO ProductionScanTransactions (SalesOrderLineId, ScanAmountKg, Barcode, LotNumber, Location, SyncId, ItemStatus, DeviceId, CreatedBy, CreatedAt, IsDeleted)
                        SELECT sol.Id, ps.ScanAmountKg, NULL, ps.Lot, ps.Location, ps.SyncId, ps.ItemStatus, ''migration'', ps.CreatedBy, ps.CreatedAt, ps.IsDeleted
                        FROM dbo.ProductionScans ps
                        JOIN dbo.SalesOrderLines sol ON ps.ItemCode = sol.ItemCode
                        JOIN dbo.SalesOrders so ON ps.SoNumber = so.SourceOrderId AND sol.SalesOrderId = so.Id
                        WHERE NOT EXISTS (SELECT 1 FROM ProductionScanTransactions pst WHERE pst.SyncId = ps.SyncId);');
                    END

                    -- D. Recalculate Aggregates (ProductionLineStates)
                    INSERT INTO ProductionLineStates (SalesOrderLineId, TotalManufacturedQty, UpdatedAt)
                    SELECT sol.Id, ISNULL(SUM(pst.ScanAmountKg), 0), GETUTCDATE()
                    FROM SalesOrderLines sol
                    LEFT JOIN ProductionScanTransactions pst ON sol.Id = pst.SalesOrderLineId AND pst.IsDeleted = 0
                    WHERE NOT EXISTS (SELECT 1 FROM ProductionLineStates pls WHERE pls.SalesOrderLineId = sol.Id)
                    GROUP BY sol.Id;

                    -- E. Sync Preparation States
                    UPDATE pls
                    SET pls.TotalPreparedQty = 1 -- Simplified for indicator
                    FROM ProductionLineStates pls
                    JOIN SalesOrderLines sol ON pls.SalesOrderLineId = sol.Id
                    JOIN SalesOrders so ON sol.SalesOrderId = so.Id
                    JOIN ItemPreparationStatus ips ON so.SourceOrderId = ips.SoNumber AND sol.ItemCode = ips.ItemCode
                    WHERE ips.IsPrepared = 1;

                    PRINT 'Enterprise Data Porting completed successfully';
                ";

                await context.Database.ExecuteSqlRawAsync(migrationSql);
                Console.WriteLine("[DbInitializer] Enterprise Redesign migration and data porting completed.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DbInitializer] ERROR in Enterprise Redesign: {ex.Message}");
            }
        }

        /// <summary>
        /// FINAL DECOMMISSION: Ports remaining data from legacy tables into enterprise schema,
        /// then permanently drops the legacy tables.
        /// Tables dropped: ProductionScans, SalesOrderDetails, CutBulkEntries, SalesOrderHeaders, ItemPreparationStatus
        /// Tables kept: OrderShipmentStatus, OrderStatusHistory, AuditLogs
        /// </summary>
        public static async Task MigrateFinalDecommissionAsync(ScanProductionDbContext context)
        {
            try
            {
                Console.WriteLine("[DbInitializer] Starting Final Decommission migration...");

                // Phase 1: Add IsPrepared column to ProductionLineStates if it doesn't exist
                var addColumnSql = @"
                    IF NOT EXISTS (
                        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                        WHERE TABLE_NAME = 'ProductionLineStates' AND COLUMN_NAME = 'IsPrepared'
                    )
                    BEGIN
                        EXEC('ALTER TABLE ProductionLineStates ADD IsPrepared BIT NOT NULL DEFAULT 0;');
                        PRINT 'Added IsPrepared column to ProductionLineStates';
                    END
                    ELSE
                        PRINT 'IsPrepared column already exists on ProductionLineStates';

                    IF NOT EXISTS (
                        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                        WHERE TABLE_NAME = 'ProductionLineStates' AND COLUMN_NAME = 'IsValidated'
                    )
                    BEGIN
                        EXEC('ALTER TABLE ProductionLineStates ADD IsValidated BIT NOT NULL DEFAULT 0;');
                        PRINT 'Added IsValidated column to ProductionLineStates';
                    END

                    IF NOT EXISTS (
                        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                        WHERE TABLE_NAME = 'ProductionLineStates' AND COLUMN_NAME = 'TotalPreparedQty'
                    )
                    BEGIN
                        EXEC('ALTER TABLE ProductionLineStates ADD TotalPreparedQty DECIMAL(18,2) NOT NULL DEFAULT 0;');
                    END

                    IF NOT EXISTS (
                        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                        WHERE TABLE_NAME = 'ProductionLineStates' AND COLUMN_NAME = 'TotalValidatedQty'
                    )
                    BEGIN
                        EXEC('ALTER TABLE ProductionLineStates ADD TotalValidatedQty DECIMAL(18,2) NOT NULL DEFAULT 0;');
                    END
                    
                    IF NOT EXISTS (
                        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
                        WHERE TABLE_NAME = 'ProductionLineStates' AND COLUMN_NAME = 'IsLineCompleted'
                    )
                    BEGIN
                        EXEC('ALTER TABLE ProductionLineStates ADD IsLineCompleted BIT NOT NULL DEFAULT 0;');
                    END
                ";
                await context.Database.ExecuteSqlRawAsync(addColumnSql);

                // Phase 2: Port ItemPreparationStatus → ProductionLineState.IsPrepared
                var portPrepStatusSql = @"
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ItemPreparationStatus]') AND type in (N'U'))
                    BEGIN
                        EXEC('UPDATE pls
                        SET pls.IsPrepared = 1,
                            pls.UpdatedAt = GETUTCDATE()
                        FROM ProductionLineStates pls
                        JOIN SalesOrderLines sol ON pls.SalesOrderLineId = sol.Id
                        JOIN SalesOrders so ON sol.SalesOrderId = so.Id
                        JOIN ItemPreparationStatus ips ON so.SourceOrderId = ips.SoNumber AND sol.ItemCode = ips.ItemCode
                        WHERE ips.IsPrepared = 1 AND pls.IsPrepared = 0;');

                        DECLARE @ported INT = @@ROWCOUNT;
                        PRINT 'Ported preparation statuses to ProductionLineStates.IsPrepared';
                    END
                ";
                await context.Database.ExecuteSqlRawAsync(portPrepStatusSql);

                // Phase 3: Verify data integrity before dropping tables
                var verifySql = @"
                    DECLARE @legacyScans INT = 0, @enterpriseScans INT = 0;
                    DECLARE @legacyDetails INT = 0, @enterpriseLines INT = 0;
                    DECLARE @legacyHeaders INT = 0, @enterpriseOrders INT = 0;

                    SELECT @enterpriseScans = COUNT(*) FROM ProductionScanTransactions;
                    SELECT @enterpriseLines = COUNT(*) FROM SalesOrderLines;
                    SELECT @enterpriseOrders = COUNT(*) FROM SalesOrders;

                    PRINT 'VERIFICATION: Legacy ProductionScans → Enterprise ProductionScanTransactions completed';
                    PRINT 'VERIFICATION: Legacy SalesOrderDetails → Enterprise SalesOrderLines completed';
                    PRINT 'VERIFICATION: Legacy SalesOrderHeaders → Enterprise SalesOrders completed';
                ";
                await context.Database.ExecuteSqlRawAsync(verifySql);

                // Phase 4: DROP legacy tables
                var dropTablesSql = @"
                    -- Drop ItemPreparationStatus (data ported to ProductionLineStates.IsPrepared)
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ItemPreparationStatus]') AND type in (N'U'))
                    BEGIN
                        DROP TABLE [dbo].[ItemPreparationStatus];
                        PRINT 'DROPPED: ItemPreparationStatus';
                    END

                    -- Drop ProductionScans (data ported to ProductionScanTransactions)
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScans]') AND type in (N'U'))
                    BEGIN
                        DROP TABLE [dbo].[ProductionScans];
                        PRINT 'DROPPED: ProductionScans';
                    END

                    -- Drop SalesOrderDetails (data ported to SalesOrderLines)
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderDetails]') AND type in (N'U'))
                    BEGIN
                        DROP TABLE [dbo].[SalesOrderDetails];
                        PRINT 'DROPPED: SalesOrderDetails';
                    END

                    -- Drop CutBulkEntries (data ported to SalesOrders with SourceSystem='Internal')
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CutBulkEntries]') AND type in (N'U'))
                    BEGIN
                        DROP TABLE [dbo].[CutBulkEntries];
                        PRINT 'DROPPED: CutBulkEntries';
                    END

                    -- Drop SalesOrderHeaders (data ported to SalesOrders)
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrderHeaders]') AND type in (N'U'))
                    BEGIN
                        DROP TABLE [dbo].[SalesOrderHeaders];
                        PRINT 'DROPPED: SalesOrderHeaders';
                    END

                    PRINT 'Final Decommission: All legacy tables dropped successfully.';
                    PRINT 'KEPT: OrderShipmentStatus, OrderStatusHistory, AuditLogs';
                ";
                await context.Database.ExecuteSqlRawAsync(dropTablesSql);

                Console.WriteLine("[DbInitializer] Final Decommission completed. Legacy tables dropped.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DbInitializer] ERROR in Final Decommission: {ex.Message}");
            }
        }
        public static async Task MigrateStagingTableAsync(ScanProductionDbContext context)
        {
            try
            {
                var migrationSql = @"
                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Staging]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[Staging] (
                            [Id] [int] IDENTITY(1,1) NOT NULL,
                            [ZREC_0] [nvarchar](1) NOT NULL DEFAULT 'L',
                            [ZSDHTYP_0] [nvarchar](5) NOT NULL DEFAULT 'SDH',
                            [ZSALFCY_0] [nvarchar](5) NULL,
                            [ZSTOFCY_0] [nvarchar](5) NOT NULL DEFAULT 'IPL',
                            [ZSDHNUM_0] [nvarchar](20) NULL,
                            [ZBPCORD_0] [nvarchar](20) NULL,
                            [ZSUR_0] [nvarchar](5) NOT NULL DEFAULT 'MUR',
                            [ZSHIDAT_0] [datetime2] NULL,
                            [ZDLVDAT_0] [datetime2] NULL,
                            [ZCFMFLG_0] [int] NOT NULL DEFAULT 2,
                            [ZLOCFCY_0] [nvarchar](100) NULL,
                            [ZLOC_0] [nvarchar](100) NULL,
                            [ZSOHNUM_0] [nvarchar](20) NOT NULL,
                            [ZSOPLIN_0] [int] NOT NULL,
                            [ZITMREF_0] [nvarchar](50) NULL,
                            [ZITMDES_0] [nvarchar](255) NULL,
                            [ZSAU_0] [nvarchar](10) NULL,
                            [ZQTY_0] [decimal](18, 5) NOT NULL,
                            [LotNumber] [nvarchar](100) NULL,
                            [CreatedAt] [datetime2] NOT NULL DEFAULT GETUTCDATE(),
                            CONSTRAINT [PK_Staging] PRIMARY KEY CLUSTERED ([Id] ASC)
                        );
                        CREATE INDEX [IX_Staging_ZSOHNUM_0] ON [dbo].[Staging] ([ZSOHNUM_0]);
                        PRINT 'Created Staging table manually';
                    END
                    ELSE
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Staging' AND COLUMN_NAME = 'ZREC_0')
                        BEGIN
                            ALTER TABLE [dbo].[Staging] ADD [ZREC_0] [nvarchar](1) NOT NULL DEFAULT 'L';
                            PRINT 'Added ZREC_0 column to existing Staging table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Staging' AND COLUMN_NAME = 'ZITMDES_0')
                        BEGIN
                            ALTER TABLE [dbo].[Staging] ADD [ZITMDES_0] [nvarchar](255) NULL;
                            PRINT 'Added ZITMDES_0 column to existing Staging table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Staging' AND COLUMN_NAME = 'IsProcessed')
                        BEGIN
                            ALTER TABLE [dbo].[Staging] ADD [IsProcessed] [bit] NOT NULL DEFAULT 0;
                            PRINT 'Added IsProcessed column to existing Staging table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Staging' AND COLUMN_NAME = 'ZREQNUM_0')
                        BEGIN
                            ALTER TABLE [dbo].[Staging] ADD [ZREQNUM_0] [nvarchar](50) NULL;
                            PRINT 'Added ZREQNUM_0 column to existing Staging table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Staging' AND COLUMN_NAME = 'LotNumber')
                        BEGIN
                            ALTER TABLE [dbo].[Staging] ADD [LotNumber] [nvarchar](100) NULL;
                            PRINT 'Added LotNumber column to existing Staging table';
                        END
                    END
                ";
                await context.Database.ExecuteSqlRawAsync(migrationSql);

                // Also ensure SalesOrders table has IsProcessed
                var salesOrderMigrationSql = @"
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SalesOrders]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrders' AND COLUMN_NAME = 'IsProcessed')
                        BEGIN
                            ALTER TABLE [dbo].[SalesOrders] ADD [IsProcessed] [bit] NOT NULL DEFAULT 0;
                            PRINT 'Added IsProcessed column to existing SalesOrders table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrders' AND COLUMN_NAME = 'Rep0')
                        BEGIN
                            ALTER TABLE [dbo].[SalesOrders] ADD [Rep0] [nvarchar](50) NULL;
                            PRINT 'Added Rep0 column to existing SalesOrders table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrders' AND COLUMN_NAME = 'Rep1')
                        BEGIN
                            ALTER TABLE [dbo].[SalesOrders] ADD [Rep1] [nvarchar](50) NULL;
                            PRINT 'Added Rep1 column to existing SalesOrders table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrders' AND COLUMN_NAME = 'DeliveryRepCode')
                        BEGIN
                            ALTER TABLE [dbo].[SalesOrders] ADD [DeliveryRepCode] [nvarchar](50) NULL;
                            PRINT 'Added DeliveryRepCode column to existing SalesOrders table';
                        END
                    END

                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[StagingEod]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'StagingEod' AND COLUMN_NAME = 'LotNumber')
                        BEGIN
                            ALTER TABLE [dbo].[StagingEod] ADD [LotNumber] [nvarchar](100) NULL;
                            PRINT 'Added LotNumber column to existing StagingEod table';
                        END

                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'StagingEod' AND COLUMN_NAME = 'DeviceId')
                        BEGIN
                            ALTER TABLE [dbo].[StagingEod] ADD [DeviceId] [nvarchar](255) NULL;
                            PRINT 'Added DeviceId column to existing StagingEod table';
                        END
                    END

                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionScanTransactions]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScanTransactions' AND COLUMN_NAME = 'DeviceId')
                        BEGIN
                            ALTER TABLE [dbo].[ProductionScanTransactions] ADD [DeviceId] [nvarchar](100) NULL;
                            PRINT 'Added DeviceId column to existing ProductionScanTransactions table';
                        END
                    END
                ";
                await context.Database.ExecuteSqlRawAsync(salesOrderMigrationSql);

                Console.WriteLine("[DbInitializer] Staging, StagingEod and SalesOrders table migration completed.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DbInitializer] ERROR in Staging migration: {ex.Message}");
            }
        }

        public static async Task EnsureDeviceIdColumnsAsync(ScanProductionDbContext context)
        {
            try
            {
                var sql = @"
                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[LabelAudits]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'LabelAudits' AND COLUMN_NAME = 'DeviceId')
                        BEGIN
                            ALTER TABLE [dbo].[LabelAudits] ADD [DeviceId] NVARCHAR(100) NULL;
                            PRINT 'Added DeviceId column to LabelAudits';
                        END
                    END

                    IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AuditLogs]') AND type in (N'U'))
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'DeviceId')
                        BEGIN
                            ALTER TABLE [dbo].[AuditLogs] ADD [DeviceId] NVARCHAR(100) NULL;
                            PRINT 'Added DeviceId column to AuditLogs';
                        END
                    END

                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[X3SoapAudits]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[X3SoapAudits] (
                            [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
                            [ActionName] NVARCHAR(100) NOT NULL DEFAULT '',
                            [Identifier] NVARCHAR(100) NULL,
                            [RequestPayload] NVARCHAR(MAX) NULL,
                            [ResponsePayload] NVARCHAR(MAX) NULL,
                            [IsSuccess] BIT NOT NULL DEFAULT 0,
                            [ErrorMessage] NVARCHAR(2000) NULL,
                            [TriggeredBy] NVARCHAR(200) NULL,
                            [DeviceId] NVARCHAR(255) NULL,
                            [CreatedAt] DATETIME2 NOT NULL DEFAULT GETUTCDATE()
                        );
                        PRINT 'Created X3SoapAudits table';
                    END
                    ELSE
                    BEGIN
                        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'X3SoapAudits' AND COLUMN_NAME = 'ErrorMessage' AND CHARACTER_MAXIMUM_LENGTH > 0 AND CHARACTER_MAXIMUM_LENGTH < 2000)
                        BEGIN
                            ALTER TABLE [dbo].[X3SoapAudits] ALTER COLUMN [ErrorMessage] NVARCHAR(2000) NULL;
                            PRINT 'Altered ErrorMessage column in X3SoapAudits to NVARCHAR(2000)';
                        END
                    END

                    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[EodProcessAudits]') AND type in (N'U'))
                    BEGIN
                        CREATE TABLE [dbo].[EodProcessAudits] (
                            [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
                            [EodDate] NVARCHAR(50) NOT NULL,
                            [WorkOrderNumber] NVARCHAR(100) NOT NULL,
                            [TriggeredBy] NVARCHAR(200) NOT NULL,
                            [DeviceId] NVARCHAR(255) NOT NULL,
                            [CreatedAt] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
                            [IsDeactivated] BIT NOT NULL DEFAULT 0
                        );
                        CREATE INDEX [IX_EodProcessAudits_EodDate] ON [dbo].[EodProcessAudits] ([EodDate]);
                        PRINT 'Created EodProcessAudits table';
                    END

                    IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'EodProcessAudits' AND COLUMN_NAME = 'IsDeactivated')
                    BEGIN
                        ALTER TABLE [dbo].[EodProcessAudits] ADD [IsDeactivated] BIT NOT NULL DEFAULT 0;
                    END

                    IF NOT EXISTS (SELECT 1 FROM [dbo].[GlobalSettings] WHERE [SettingKey] = 'X3Schema')
                    BEGIN
                        INSERT INTO [dbo].[GlobalSettings] ([SettingKey], [SettingValue], [LastUpdatedBy], [UpdatedAt], [Action])
                        VALUES ('X3Schema', 'INLDRYRUN', 'SYSTEM', GETUTCDATE(), 'INSERT');
                    END
                ";
                await context.Database.ExecuteSqlRawAsync(sql);
                Console.WriteLine("[DbInitializer] EnsureDeviceIdColumns completed successfully.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DbInitializer] ERROR ensuring DeviceId columns: {ex.Message}");
            }
        }
    }
}
