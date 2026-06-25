IF OBJECT_ID(N'[__EFMigrationsHistory]') IS NULL
BEGIN
    CREATE TABLE [__EFMigrationsHistory] (
        [MigrationId] nvarchar(150) NOT NULL,
        [ProductVersion] nvarchar(32) NOT NULL,
        CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId])
    );
END;
GO

BEGIN TRANSACTION;
GO

CREATE TABLE [AuditLogs] (
    [AuditId] int NOT NULL IDENTITY,
    [EntityName] nvarchar(100) NOT NULL,
    [EntityId] int NOT NULL,
    [ActionType] nvarchar(20) NOT NULL,
    [Payload] nvarchar(max) NULL,
    [PerformedBy] nvarchar(100) NULL,
    [PerformedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_AuditLogs] PRIMARY KEY ([AuditId])
);
GO

CREATE TABLE [Excesses] (
    [Id] uniqueidentifier NOT NULL,
    [SourceBulkSoNumber] nvarchar(450) NOT NULL,
    [ItemCode] nvarchar(450) NOT NULL,
    [DeliveryDate] datetime2 NOT NULL,
    [TotalManufacturedQuantity] decimal(18,5) NOT NULL,
    [AllocatedQuantity] decimal(18,5) NOT NULL,
    [RemainingExcess] decimal(18,5) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [CreatedBy] nvarchar(max) NOT NULL,
    [UpdatedAt] datetime2 NULL,
    [UpdatedBy] nvarchar(max) NOT NULL,
    CONSTRAINT [PK_Excesses] PRIMARY KEY ([Id])
);
GO

CREATE TABLE [OrderShipmentStatus] (
    [Id] int NOT NULL IDENTITY,
    [SoNumber] nvarchar(100) NOT NULL,
    [IsPreparedForShipment] bit NOT NULL,
    [IsValidated] bit NOT NULL,
    [UpdatedBy] nvarchar(100) NULL,
    [UpdatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_OrderShipmentStatus] PRIMARY KEY ([Id])
);
GO

CREATE TABLE [OrderStatusHistory] (
    [Id] int NOT NULL IDENTITY,
    [SoNumber] nvarchar(100) NOT NULL,
    [Status] int NOT NULL,
    [ChangedBy] nvarchar(100) NULL,
    [ChangedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_OrderStatusHistory] PRIMARY KEY ([Id])
);
GO

CREATE TABLE [SalesOrders] (
    [Id] uniqueidentifier NOT NULL,
    [SourceOrderId] nvarchar(100) NOT NULL,
    [SourceSystem] nvarchar(20) NOT NULL,
    [PoNumber] nvarchar(100) NULL,
    [OrderDate] datetime2 NULL,
    [DeliveryDate] datetime2 NULL,
    [Salesman] nvarchar(200) NULL,
    [CustomerCode] nvarchar(100) NULL,
    [CustomerName] nvarchar(255) NULL,
    [Site] nvarchar(100) NULL,
    [Status] int NOT NULL,
    [IsArchived] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [UpdatedAt] datetime2 NULL,
    CONSTRAINT [PK_SalesOrders] PRIMARY KEY ([Id])
);
GO

CREATE TABLE [SalesOrderLines] (
    [Id] uniqueidentifier NOT NULL,
    [SalesOrderId] uniqueidentifier NOT NULL,
    [ItemCode] nvarchar(100) NOT NULL,
    [Description] nvarchar(255) NULL,
    [OrderedQuantity] decimal(18,5) NOT NULL,
    [Unit] nvarchar(50) NULL,
    [Location] nvarchar(100) NULL,
    [Lot] nvarchar(100) NULL,
    [LineNumber] int NOT NULL,
    [LineStatus] int NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_SalesOrderLines] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_SalesOrderLines_SalesOrders_SalesOrderId] FOREIGN KEY ([SalesOrderId]) REFERENCES [SalesOrders] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [ProductionLineStates] (
    [SalesOrderLineId] uniqueidentifier NOT NULL,
    [TotalManufacturedQty] decimal(18,5) NOT NULL,
    [TotalPreparedQty] decimal(18,5) NOT NULL,
    [TotalValidatedQty] decimal(18,5) NOT NULL,
    [IsLineCompleted] bit NOT NULL,
    [IsPrepared] bit NOT NULL,
    [LastScanId] uniqueidentifier NULL,
    [UpdatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_ProductionLineStates] PRIMARY KEY ([SalesOrderLineId]),
    CONSTRAINT [FK_ProductionLineStates_SalesOrderLines_SalesOrderLineId] FOREIGN KEY ([SalesOrderLineId]) REFERENCES [SalesOrderLines] ([Id]) ON DELETE CASCADE
);
GO

CREATE TABLE [ProductionScanTransactions] (
    [Id] uniqueidentifier NOT NULL,
    [SalesOrderLineId] uniqueidentifier NOT NULL,
    [ScanAmountKg] decimal(18,5) NOT NULL,
    [Barcode] nvarchar(100) NULL,
    [LotNumber] nvarchar(100) NULL,
    [Location] nvarchar(100) NULL,
    [SyncId] nvarchar(100) NOT NULL,
    [ItemStatus] nvarchar(100) NULL,
    [DeviceId] nvarchar(100) NULL,
    [CreatedBy] nvarchar(100) NULL,
    [CreatedAt] datetime2 NOT NULL,
    [IsDeleted] bit NOT NULL,
    [IsArchived] bit NOT NULL,
    CONSTRAINT [PK_ProductionScanTransactions] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_ProductionScanTransactions_SalesOrderLines_SalesOrderLineId] FOREIGN KEY ([SalesOrderLineId]) REFERENCES [SalesOrderLines] ([Id]) ON DELETE CASCADE
);
GO

CREATE INDEX [IX_AuditLogs_EntityLookup] ON [AuditLogs] ([EntityName], [EntityId]);
GO

CREATE INDEX [IX_Excesses_ItemCode_DeliveryDate] ON [Excesses] ([ItemCode], [DeliveryDate]);
GO

CREATE INDEX [IX_Excesses_SourceBulkSoNumber] ON [Excesses] ([SourceBulkSoNumber]);
GO

CREATE UNIQUE INDEX [UQ_OrderShipmentStatus_SoNumber] ON [OrderShipmentStatus] ([SoNumber]);
GO

CREATE INDEX [IX_OrderStatusHistory_SoNumber] ON [OrderStatusHistory] ([SoNumber]);
GO

CREATE INDEX [IX_ProductionScanTransactions_SalesOrderLineId_IsDeleted_IsArchived] ON [ProductionScanTransactions] ([SalesOrderLineId], [IsDeleted], [IsArchived]);
GO

CREATE UNIQUE INDEX [IX_ProductionScanTransactions_SyncId] ON [ProductionScanTransactions] ([SyncId]);
GO

CREATE INDEX [IX_SalesOrderLines_SalesOrderId_ItemCode] ON [SalesOrderLines] ([SalesOrderId], [ItemCode]);
GO

CREATE UNIQUE INDEX [IX_SalesOrders_SourceOrderId] ON [SalesOrders] ([SourceOrderId]);
GO

CREATE INDEX [IX_SalesOrders_SourceSystem_Status_IsArchived] ON [SalesOrders] ([SourceSystem], [Status], [IsArchived]);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260415111437_AddExcessTable', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

DROP INDEX [IX_Excesses_ItemCode_DeliveryDate] ON [Excesses];
GO

DROP INDEX [IX_Excesses_SourceBulkSoNumber] ON [Excesses];
GO

CREATE TABLE [LabelAudits] (
    [Id] uniqueidentifier NOT NULL,
    [LabelId] nvarchar(450) NOT NULL,
    [ReferenceNumber] nvarchar(450) NOT NULL,
    [LabelType] nvarchar(450) NOT NULL,
    [CustomerName] nvarchar(max) NOT NULL,
    [ProductCode] nvarchar(max) NOT NULL,
    [TotalWeight] decimal(18,5) NOT NULL,
    [ManifestJson] nvarchar(max) NOT NULL,
    [PrintedBy] nvarchar(max) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_LabelAudits] PRIMARY KEY ([Id])
);
GO

CREATE INDEX [IX_Excess_Date_Item] ON [Excesses] ([DeliveryDate], [ItemCode]);
GO

CREATE UNIQUE INDEX [UQ_Excess_BulkSO_Item] ON [Excesses] ([SourceBulkSoNumber], [ItemCode]);
GO

CREATE UNIQUE INDEX [IX_LabelAudits_LabelId] ON [LabelAudits] ([LabelId]);
GO

CREATE INDEX [IX_LabelAudits_LabelType_CreatedAt] ON [LabelAudits] ([LabelType], [CreatedAt]);
GO

CREATE INDEX [IX_LabelAudits_ReferenceNumber] ON [LabelAudits] ([ReferenceNumber]);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260416100752_AddLabelAuditsTable', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

DROP INDEX [IX_LabelAudits_LabelType_CreatedAt] ON [LabelAudits];
GO

DROP INDEX [IX_LabelAudits_ReferenceNumber] ON [LabelAudits];
GO

DECLARE @var0 sysname;
SELECT @var0 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'ReferenceNumber');
IF @var0 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var0 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [ReferenceNumber] nvarchar(100) NULL;
GO

DECLARE @var1 sysname;
SELECT @var1 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'ProductCode');
IF @var1 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var1 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [ProductCode] nvarchar(100) NULL;
GO

DECLARE @var2 sysname;
SELECT @var2 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'PrintedBy');
IF @var2 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var2 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [PrintedBy] nvarchar(100) NULL;
GO

DECLARE @var3 sysname;
SELECT @var3 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'ManifestJson');
IF @var3 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var3 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [ManifestJson] nvarchar(max) NULL;
GO

DECLARE @var4 sysname;
SELECT @var4 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'LabelType');
IF @var4 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var4 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [LabelType] nvarchar(50) NULL;
GO

DROP INDEX [IX_LabelAudits_LabelId] ON [LabelAudits];
DECLARE @var5 sysname;
SELECT @var5 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'LabelId');
IF @var5 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var5 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [LabelId] nvarchar(50) NOT NULL;
CREATE UNIQUE INDEX [IX_LabelAudits_LabelId] ON [LabelAudits] ([LabelId]);
GO

DECLARE @var6 sysname;
SELECT @var6 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[LabelAudits]') AND [c].[name] = N'CustomerName');
IF @var6 IS NOT NULL EXEC(N'ALTER TABLE [LabelAudits] DROP CONSTRAINT [' + @var6 + '];');
ALTER TABLE [LabelAudits] ALTER COLUMN [CustomerName] nvarchar(200) NULL;
GO

ALTER TABLE [LabelAudits] ADD [IsOfflineCreated] bit NOT NULL DEFAULT CAST(0 AS bit);
GO

CREATE TABLE [GlobalSettings] (
    [SettingKey] nvarchar(100) NOT NULL,
    [SettingValue] nvarchar(max) NOT NULL,
    [LastUpdatedBy] nvarchar(100) NULL,
    [UpdatedAt] datetime2 NOT NULL DEFAULT (GETUTCDATE()),
    CONSTRAINT [PK_GlobalSettings] PRIMARY KEY ([SettingKey])
);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260417051748_AddGlobalSettingsTable', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

ALTER TABLE [Excesses] ADD [CustomerCode] nvarchar(max) NULL;
GO

ALTER TABLE [Excesses] ADD [Salesman] nvarchar(max) NULL;
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260417063058_AddCustomerSalesmanToExcess', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

ALTER TABLE [GlobalSettings] ADD [Action] nvarchar(20) NOT NULL DEFAULT N'';
GO

ALTER TABLE [GlobalSettings] ADD [Id] int NOT NULL IDENTITY;
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260417104507_MakeGlobalSettingsAppendOnly', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

ALTER TABLE [GlobalSettings] DROP CONSTRAINT [PK_GlobalSettings];
GO

ALTER TABLE [GlobalSettings] ADD CONSTRAINT [PK_GlobalSettings] PRIMARY KEY ([Id]);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260417111125_FixGlobalSettingsPK', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

DROP INDEX [IX_AuditLogs_EntityLookup] ON [AuditLogs];
GO

DECLARE @var7 sysname;
SELECT @var7 = [d].[name]
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[AuditLogs]') AND [c].[name] = N'EntityId');
IF @var7 IS NOT NULL EXEC(N'ALTER TABLE [AuditLogs] DROP CONSTRAINT [' + @var7 + '];');
ALTER TABLE [AuditLogs] DROP COLUMN [EntityId];
GO

ALTER TABLE [AuditLogs] ADD [EntityIdString] nvarchar(200) NOT NULL DEFAULT N'';
GO

CREATE INDEX [IX_AuditLogs_EntityLookup] ON [AuditLogs] ([EntityName], [EntityIdString]);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260417121759_RefactorAuditLogEntityIdToString', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

ALTER TABLE [ProductionLineStates] ADD [IsValidated] bit NOT NULL DEFAULT CAST(0 AS bit);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260419093244_AddIsValidatedToProductionLineState', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

CREATE TABLE [Staging] (
    [Id] int NOT NULL IDENTITY,
    [ZSDHTYP_0] nvarchar(5) NOT NULL,
    [ZSALFCY_0] nvarchar(5) NULL,
    [ZSTOFCY_0] nvarchar(5) NOT NULL,
    [ZSDHNUM_0] nvarchar(20) NULL,
    [ZBPCORD_0] nvarchar(20) NULL,
    [ZSUR_0] nvarchar(5) NOT NULL,
    [ZSHIDAT_0] datetime2 NULL,
    [ZDLVDAT_0] datetime2 NULL,
    [ZCFMFLG_0] int NOT NULL,
    [ZLOCFCY_0] nvarchar(100) NULL,
    [ZLOC_0] nvarchar(100) NULL,
    [ZSOHNUM_0] nvarchar(20) NOT NULL,
    [ZSOPLIN_0] int NOT NULL,
    [ZITMREF_0] nvarchar(50) NULL,
    [ZSAU_0] nvarchar(10) NULL,
    [ZQTY_0] decimal(18,5) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Staging] PRIMARY KEY ([Id])
);
GO

CREATE INDEX [IX_Staging_ZSOHNUM_0] ON [Staging] ([ZSOHNUM_0]);
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20260420042522_AddStagingTable', N'8.0.0');
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (SELECT 1 FROM [Permissions] WHERE [Name] = 'settings.lot.read')
BEGIN
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'settings.lot.read', 'Read access to lot in settings');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'settings.lot.create', 'Create access to lot in settings');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'settings.lot.update', 'Update access to lot in settings');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'settings.lot.delete', 'Delete access to lot in settings');
END
GO

IF NOT EXISTS (SELECT 1 FROM [Permissions] WHERE [Name] = 'manufacturing.eod.read')
BEGIN
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.eod.read', 'Read access to eod in manufacturing');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.eod.create', 'Create access to eod in manufacturing');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.eod.update', 'Update access to eod in manufacturing');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.eod.delete', 'Delete access to eod in manufacturing');
END
GO

COMMIT;
GO
