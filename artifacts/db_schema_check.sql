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


CREATE TABLE [GlobalSettings] (
    [SettingKey] nvarchar(100) NOT NULL,
    [SettingValue] nvarchar(max) NOT NULL,
    [LastUpdatedBy] nvarchar(100) NULL,
    [UpdatedAt] datetime2 NOT NULL DEFAULT (GETUTCDATE()),
    CONSTRAINT [PK_GlobalSettings] PRIMARY KEY ([SettingKey])
);
GO


CREATE TABLE [LabelAudits] (
    [Id] uniqueidentifier NOT NULL,
    [LabelId] nvarchar(50) NOT NULL,
    [ReferenceNumber] nvarchar(100) NULL,
    [LabelType] nvarchar(50) NULL,
    [ProductCode] nvarchar(100) NULL,
    [CustomerName] nvarchar(200) NULL,
    [TotalWeight] decimal(18,5) NOT NULL,
    [ManifestJson] nvarchar(max) NULL,
    [PrintedBy] nvarchar(100) NULL,
    [CreatedAt] datetime2 NOT NULL,
    [IsOfflineCreated] bit NOT NULL,
    CONSTRAINT [PK_LabelAudits] PRIMARY KEY ([Id])
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


CREATE INDEX [IX_Excess_Date_Item] ON [Excesses] ([DeliveryDate], [ItemCode]);
GO


CREATE UNIQUE INDEX [UQ_Excess_BulkSO_Item] ON [Excesses] ([SourceBulkSoNumber], [ItemCode]);
GO


CREATE UNIQUE INDEX [IX_LabelAudits_LabelId] ON [LabelAudits] ([LabelId]);
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


