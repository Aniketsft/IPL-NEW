-- Create the Hipo database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'Hipo')
BEGIN
    CREATE DATABASE Hipo;
END
GO

USE Hipo;
GO

-- Create Schema if needed (all in dbo for now)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'INLPROD')
BEGIN
    EXEC('CREATE SCHEMA INLPROD');
END
GO

-- --------------------------------------------------
-- Enterprise Auth Tables (from ApplicationDbContext)
-- --------------------------------------------------

CREATE TABLE [dbo].[Permissions] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [Name] NVARCHAR(255) NOT NULL,
    [Description] NVARCHAR(MAX) NULL
);
CREATE UNIQUE INDEX [IX_Permissions_Name] ON [dbo].[Permissions] ([Name]);

CREATE TABLE [dbo].[Roles] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [Name] NVARCHAR(255) NOT NULL,
    [Description] NVARCHAR(MAX) NULL
);
CREATE UNIQUE INDEX [IX_Roles_Name] ON [dbo].[Roles] ([Name]);

CREATE TABLE [dbo].[RolePermissions] (
    [PermissionsId] UNIQUEIDENTIFIER NOT NULL,
    [RolesId] UNIQUEIDENTIFIER NOT NULL,
    PRIMARY KEY ([PermissionsId], [RolesId]),
    FOREIGN KEY ([PermissionsId]) REFERENCES [dbo].[Permissions]([Id]) ON DELETE CASCADE,
    FOREIGN KEY ([RolesId]) REFERENCES [dbo].[Roles]([Id]) ON DELETE CASCADE
);

CREATE TABLE [dbo].[UserGroups] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [Name] NVARCHAR(255) NOT NULL,
    [Description] NVARCHAR(MAX) NULL,
    [RoleId] UNIQUEIDENTIFIER NOT NULL,
    FOREIGN KEY ([RoleId]) REFERENCES [dbo].[Roles]([Id])
);
CREATE UNIQUE INDEX [IX_UserGroups_Name] ON [dbo].[UserGroups] ([Name]);

CREATE TABLE [dbo].[Users] (
    [Id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [Email] NVARCHAR(255) NOT NULL,
    [Username] NVARCHAR(255) NOT NULL,
    [PasswordHash] NVARCHAR(MAX) NOT NULL,
    [Salt] NVARCHAR(MAX) NOT NULL,
    [IsActive] BIT NOT NULL DEFAULT 1,
    [CreatedAt] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [UpdatedAt] DATETIME2 NULL,
    [UserGroupId] UNIQUEIDENTIFIER NULL,
    FOREIGN KEY ([UserGroupId]) REFERENCES [dbo].[UserGroups]([Id])
);
CREATE UNIQUE INDEX [IX_Users_Email] ON [dbo].[Users] ([Email]);
CREATE UNIQUE INDEX [IX_Users_Username] ON [dbo].[Users] ([Username]);

CREATE TABLE [dbo].[UserRoles] (
    [RolesId] UNIQUEIDENTIFIER NOT NULL,
    [UsersId] UNIQUEIDENTIFIER NOT NULL,
    PRIMARY KEY ([RolesId], [UsersId]),
    FOREIGN KEY ([RolesId]) REFERENCES [dbo].[Roles]([Id]) ON DELETE CASCADE,
    FOREIGN KEY ([UsersId]) REFERENCES [dbo].[Users]([Id]) ON DELETE CASCADE
);

CREATE TABLE [dbo].[CutBulkEntries] (
    [Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [EntryNumber] NVARCHAR(50) NOT NULL,
    [Type] NVARCHAR(20) NOT NULL,
    [CustomerCode] NVARCHAR(50) NOT NULL,
    [CustomerName] NVARCHAR(100) NOT NULL,
    [Date] DATETIME NOT NULL,
    [PoNumber] NVARCHAR(50) NULL,
    [Salesman1Code] NVARCHAR(50) NULL,
    [Salesman2Code] NVARCHAR(50) NULL,
    [AmountKg] DECIMAL(18, 2) NOT NULL
);
CREATE UNIQUE INDEX [IX_CutBulkEntries_EntryNumber] ON [dbo].[CutBulkEntries] ([EntryNumber]);

-- --------------------------------------------------
-- Scan Production Tables (from ScanProductionDbContext)
-- --------------------------------------------------

CREATE TABLE [dbo].[production_scan] (
    [scan_id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [product_id] NVARCHAR(100) NOT NULL,
    [line_no] INT NOT NULL,
    [scan_amount_kg] DECIMAL(18, 2) NOT NULL,
    [so_number] NVARCHAR(100) NOT NULL,
    [order_status] NVARCHAR(10) NULL,
    [item_status] NVARCHAR(10) NULL,
    [location] NVARCHAR(100) NULL,
    [lot] NVARCHAR(100) NULL,
    [created_by] NVARCHAR(100) NULL,
    [created_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [updated_by] NVARCHAR(100) NULL,
    [updated_at] DATETIME2 NULL,
    [is_deleted] BIT NOT NULL DEFAULT 0,
    [deleted_by] NVARCHAR(100) NULL,
    [deleted_at] DATETIME2 NULL,
    [is_prepared] BIT NOT NULL DEFAULT 0,
    [is_prepared_for_shipment] BIT NOT NULL DEFAULT 0,
    [sync_id] NVARCHAR(100) NULL
);

CREATE TABLE [dbo].[cut_bulk_entries] (
    [Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [EntryNumber] NVARCHAR(50) NOT NULL,
    [Type] NVARCHAR(20) NOT NULL,
    [CustomerCode] NVARCHAR(50) NOT NULL,
    [CustomerName] NVARCHAR(100) NOT NULL,
    [Date] DATETIME NOT NULL,
    [PoNumber] NVARCHAR(50) NULL,
    [Salesman1Code] NVARCHAR(50) NULL,
    [Salesman2Code] NVARCHAR(50) NULL,
    [AmountKg] DECIMAL(18, 2) NOT NULL,
    [DeviceId] NVARCHAR(MAX) NULL,
    [SyncStatus] NVARCHAR(MAX) NULL,
    [SyncTimestamp] DATETIME2 NULL
);
CREATE UNIQUE INDEX [IX_cut_bulk_entries_EntryNumber] ON [dbo].[cut_bulk_entries] ([EntryNumber]);

CREATE TABLE [dbo].[salesorderdetailscutsbulk] (
    [Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [SoNumber] NVARCHAR(50) NOT NULL,
    [ItemCode] NVARCHAR(50) NOT NULL,
    [Description] NVARCHAR(MAX) NOT NULL,
    [BarcodeType] NVARCHAR(50) NOT NULL DEFAULT 'Variable Weight',
    [Quantity] DECIMAL(18, 2) NOT NULL,
    [ManufacturedQuantity] DECIMAL(18, 2) NOT NULL DEFAULT 0,
    [IsPrepared] BIT NOT NULL DEFAULT 0,
    [SyncStatus] NVARCHAR(50) NOT NULL DEFAULT 'Synced',
    [CreatedAt] DATETIME2 NULL DEFAULT GETUTCDATE()
);
CREATE INDEX [IX_salesorderdetailscutsbulk_SoNumber_ItemCode] ON [dbo].[salesorderdetailscutsbulk] ([SoNumber], [ItemCode]);

CREATE TABLE [dbo].[audit_log] (
    [audit_id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [entity_name] NVARCHAR(100) NOT NULL,
    [entity_id] INT NOT NULL,
    [action_type] NVARCHAR(20) NOT NULL,
    [payload] NVARCHAR(MAX) NULL,
    [performed_by] NVARCHAR(100) NULL,
    [performed_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

GO
SET IDENTITY_INSERT [dbo].[CutBulkEntries] ON;
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('3bc7770c-c824-48a3-ba2c-048869ab5a71', N'manufacturing.all.update', N'Update access to all in manufacturing');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('0577cc35-cf14-4b3d-a913-0bd8f54f6379', N'inventory.by_identifier.read', N'Read access to by_identifier in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('87531753-fecd-4bd9-8027-1033ecdedaa3', N'inventory.picking.update', N'Update access to picking in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('331a59a5-0ec9-4957-b2ef-15984c64881d', N'inventory.picking.delete', N'Delete access to picking in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('c370ba9b-a51d-4796-b763-18d30b464bff', N'inventory.by_identifier.create', N'Create access to by_identifier in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('8aa5073f-2944-46c9-87be-1a0ff4e75dc4', N'settings.printer.create', N'Create access to printer in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('7087de35-d252-4f4d-ac0b-1d88a22f8efb', N'manufacturing.all.create', N'Create access to all in manufacturing');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('aea39c8e-44c3-4e2e-9b2f-25f2ef94652a', N'administration.user_management.update', N'Update access to user_management in administration');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('5a1db44c-8c11-4762-bb6f-2af1a4e9143a', N'logistics.receipt.read', N'Read access to receipt in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('634db90f-37b7-47a8-8e6d-37da8a9cbfb1', N'logistics.transfer.create', N'Create access to transfer in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('fe6bafd0-6e4b-4b7e-ba63-384fd29d75a4', N'settings.general.create', N'Create access to general in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('cdaffabf-05bb-4276-b7be-3bbab8301c62', N'inventory.stock_control.delete', N'Delete access to stock_control in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('693a0468-cd82-4415-8d96-40ad00d41879', N'settings.printer.update', N'Update access to printer in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('71651908-75ae-4592-b26b-44bcbbb098de', N'administration.user_management.read', N'Read access to user_management in administration');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('315b0254-2f3a-4257-a261-613364b67e97', N'settings.printer.read', N'Read access to printer in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('e1e892d2-8870-4ffe-9813-66a6661a208e', N'logistics.receipt.create', N'Create access to receipt in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('73e22c54-13fa-42f9-bdc7-6b29d8eecce4', N'logistics.transfer.delete', N'Delete access to transfer in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('0063a5a6-36f4-4e17-a5e3-6bc5aa5b072b', N'administration.user_management.create', N'Create access to user_management in administration');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('dc14c34e-2ba2-42b0-a556-6cfdeed5e943', N'inventory.by_identifier.delete', N'Delete access to by_identifier in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('b95f9648-3098-4784-a59c-6d176bc7c764', N'inventory.stock_control.update', N'Update access to stock_control in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('0df5bb0d-26d7-4252-9227-6dd7f7f47b34', N'inventory.stock_control.read', N'Read access to stock_control in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('344e37aa-5390-4014-85e8-74571ccdc487', N'logistics.delivery.update', N'Update access to delivery in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('eaa97398-2561-4a63-8bc3-7b120def436d', N'logistics.delivery.create', N'Create access to delivery in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('90c667a2-b32b-48c4-81ab-88454c720273', N'logistics.transfer.read', N'Read access to transfer in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('82421a5c-f261-4c86-be4c-99be25ef56c4', N'logistics.delivery.read', N'Read access to delivery in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('3cb68f29-c2f9-4692-bcab-a6c7b5cec191', N'settings.printer.delete', N'Delete access to printer in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('aa11eca4-3238-4d99-a17a-b44aadd98874', N'logistics.transfer.update', N'Update access to transfer in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('3207ceb0-4274-47e5-af2c-c12acd6b6040', N'inventory.by_identifier.update', N'Update access to by_identifier in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('3f9d96b3-32dc-46fd-ac0e-c2eb1196a9aa', N'logistics.delivery.delete', N'Delete access to delivery in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('6b292bd5-1654-40f5-ac87-c37dfe6af3a5', N'inventory.picking.create', N'Create access to picking in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('1387d610-6bf6-4089-9577-cc596ca2c04f', N'settings.general.read', N'Read access to general in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), N'settings.lot.read', N'Read access to lot in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), N'settings.lot.create', N'Create access to lot in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), N'settings.lot.update', N'Update access to lot in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), N'settings.lot.delete', N'Delete access to lot in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('109aeada-c8cd-49e3-93cb-d37660e98c31', N'settings.general.delete', N'Delete access to general in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('ad8cd39e-2f9b-479a-8578-d5137ab421e1', N'inventory.picking.read', N'Read access to picking in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('d216a7ff-41ee-45c4-92ce-e1bc23d54bf5', N'administration.user_management.delete', N'Delete access to user_management in administration');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('55cf0a3a-e3a6-4026-b5cb-e1febfb73bd6', N'logistics.receipt.delete', N'Delete access to receipt in logistics');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('f990f2a2-e659-4991-acc6-e752b951a988', N'inventory.stock_control.create', N'Create access to stock_control in inventory');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('bd807cbc-216b-41b4-a3dc-e8c0df82a9cf', N'manufacturing.all.read', N'Read access to all in manufacturing');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('373efe61-3aae-445e-9e5e-ee598daff720', N'manufacturing.all.delete', N'Delete access to all in manufacturing');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('50d55441-ecf5-450a-a255-f629df5cb8b0', N'settings.general.update', N'Update access to general in settings');
INSERT INTO [dbo].[Permissions] ([Id], [Name], [Description]) VALUES ('9c9e646a-e0f6-4483-a9ea-f7c2d4e52d16', N'logistics.receipt.update', N'Update access to receipt in logistics');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('af2b4589-63b5-4a51-a49a-0cc31e52867a', N'Custom:MRATEST:15ae', N'Custom permissions for MRATEST');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('ba02b2d5-6df0-487f-bdee-15cdf162fc2e', N'Viewer', N'Read-only access');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('6f17e4da-7234-408b-86ad-1911afc3e45c', N'Custom:MRATEST:669c', N'Custom permissions for MRATEST');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('f851259d-a26d-444e-ad9d-1cfc1ffb8596', N'Custom:test:61d1', N'Custom permissions for test');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('b20a626a-e6a0-4ada-8740-4d5441e11322', N'Operator', N'Limited operational access');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('4da68bc9-2e76-46c7-ad05-7c7890966835', N'Custom:MRATEST:1785', N'Custom permissions for MRATEST');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('87d4147e-ff98-418a-995b-8de859a31b74', N'Admin', N'Full system access');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('f7e7ba51-d912-4a5c-be6b-a56abb508a80', N'Custom:MRATEST :2c01', N'Custom permissions for MRATEST ');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('fb9b3077-0c91-41a7-a602-ad144cbfc7af', N'Custom:MRATEST :77f8', N'Custom permissions for MRATEST ');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('d1015d5b-ebf4-4d6c-a987-d6e6c26ed452', N'Custom:testmanufacturing:f07d', N'Custom permissions for testmanufacturing');
INSERT INTO [dbo].[Roles] ([Id], [Name], [Description]) VALUES ('ae0265d0-f35b-4d26-a233-de781e40b140', N'Custom:MRATEST:e9de', N'Custom permissions for MRATEST');
INSERT INTO [dbo].[UserGroups] ([Id], [Name], [Description], [RoleId]) VALUES ('9ee0d6f3-914e-4b71-b716-498d855e11cb', N'Logistics', N'Logistics and delivery team', 'b20a626a-e6a0-4ada-8740-4d5441e11322');
INSERT INTO [dbo].[UserGroups] ([Id], [Name], [Description], [RoleId]) VALUES ('2a2b9428-25d8-4bf3-9e8b-68a128a95a15', N'IT Administration', N'System administrators', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[Users] ([Id], [Email], [Username], [PasswordHash], [Salt], [IsActive], [CreatedAt], [UpdatedAt], [UserGroupId]) VALUES ('3c7937ef-b219-4340-9e34-87306f74aadc', N'admin@enterprise.com', N'admin', N'$2a$11$KphWDr9U56gLcBdo8rNWb.HlBzFHv30hJ1ur4ZcpdM5kT75kE1fV.', N'$2a$11$KphWDr9U56gLcBdo8rNWb.', 1, '2026-03-03 07:53:53.288', NULL, '2a2b9428-25d8-4bf3-9e8b-68a128a95a15');
INSERT INTO [dbo].[Users] ([Id], [Email], [Username], [PasswordHash], [Salt], [IsActive], [CreatedAt], [UpdatedAt], [UserGroupId]) VALUES ('7f761032-2f7b-469b-90f2-bfbd43f2a106', N'MRATEST@gmail.com', N'MRATEST ', N'$2a$11$x./mZLb/hcl8AUfgFfwdDetaBllnNo2AL1fC9PXUS84jrth2B2ORi', N'$2a$11$x./mZLb/hcl8AUfgFfwdDe', 1, '2026-04-08 11:06:21.820', NULL, '2a2b9428-25d8-4bf3-9e8b-68a128a95a15');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('3bc7770c-c824-48a3-ba2c-048869ab5a71', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('0577cc35-cf14-4b3d-a913-0bd8f54f6379', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('87531753-fecd-4bd9-8027-1033ecdedaa3', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('331a59a5-0ec9-4957-b2ef-15984c64881d', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('c370ba9b-a51d-4796-b763-18d30b464bff', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('8aa5073f-2944-46c9-87be-1a0ff4e75dc4', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('7087de35-d252-4f4d-ac0b-1d88a22f8efb', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('aea39c8e-44c3-4e2e-9b2f-25f2ef94652a', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('5a1db44c-8c11-4762-bb6f-2af1a4e9143a', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('634db90f-37b7-47a8-8e6d-37da8a9cbfb1', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('fe6bafd0-6e4b-4b7e-ba63-384fd29d75a4', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('cdaffabf-05bb-4276-b7be-3bbab8301c62', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('693a0468-cd82-4415-8d96-40ad00d41879', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('71651908-75ae-4592-b26b-44bcbbb098de', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('315b0254-2f3a-4257-a261-613364b67e97', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('e1e892d2-8870-4ffe-9813-66a6661a208e', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('73e22c54-13fa-42f9-bdc7-6b29d8eecce4', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('0063a5a6-36f4-4e17-a5e3-6bc5aa5b072b', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('dc14c34e-2ba2-42b0-a556-6cfdeed5e943', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('b95f9648-3098-4784-a59c-6d176bc7c764', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('0df5bb0d-26d7-4252-9227-6dd7f7f47b34', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('344e37aa-5390-4014-85e8-74571ccdc487', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('eaa97398-2561-4a63-8bc3-7b120def436d', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('90c667a2-b32b-48c4-81ab-88454c720273', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('82421a5c-f261-4c86-be4c-99be25ef56c4', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('3cb68f29-c2f9-4692-bcab-a6c7b5cec191', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('aa11eca4-3238-4d99-a17a-b44aadd98874', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('3207ceb0-4274-47e5-af2c-c12acd6b6040', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('3f9d96b3-32dc-46fd-ac0e-c2eb1196a9aa', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('6b292bd5-1654-40f5-ac87-c37dfe6af3a5', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('1387d610-6bf6-4089-9577-cc596ca2c04f', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('109aeada-c8cd-49e3-93cb-d37660e98c31', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('ad8cd39e-2f9b-479a-8578-d5137ab421e1', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('d216a7ff-41ee-45c4-92ce-e1bc23d54bf5', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('55cf0a3a-e3a6-4026-b5cb-e1febfb73bd6', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('f990f2a2-e659-4991-acc6-e752b951a988', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('bd807cbc-216b-41b4-a3dc-e8c0df82a9cf', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('373efe61-3aae-445e-9e5e-ee598daff720', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('50d55441-ecf5-450a-a255-f629df5cb8b0', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[RolePermissions] ([PermissionsId], [RolesId]) VALUES ('9c9e646a-e0f6-4483-a9ea-f7c2d4e52d16', '87d4147e-ff98-418a-995b-8de859a31b74');
INSERT INTO [dbo].[UserRoles] ([RolesId], [UsersId]) VALUES ('87d4147e-ff98-418a-995b-8de859a31b74', '3c7937ef-b219-4340-9e34-87306f74aadc');
INSERT INTO [dbo].[CutBulkEntries] ([Id], [EntryNumber], [Type], [CustomerCode], [CustomerName], [Date], [PoNumber], [Salesman1Code], [Salesman2Code], [AmountKg]) VALUES (1, N'CB-20260308-0001', N'Cuts', N'DUD001', N'3 R STORE - DUDLEE : (VAC)', '2026-03-08 13:31:50.723', N'soh815', N'AT', N'I7', 58.00);
INSERT INTO [dbo].[CutBulkEntries] ([Id], [EntryNumber], [Type], [CustomerCode], [CustomerName], [Date], [PoNumber], [Salesman1Code], [Salesman2Code], [AmountKg]) VALUES (2, N'CB-20260308-0002', N'Bulks', N'3RD001', N'3RD WORLD THIRD WORLD BTK - (T.BAY)', '2026-03-08 18:51:51.570', N'ghj', N'06', N'AT', 80.00);
INSERT INTO [dbo].[CutBulkEntries] ([Id], [EntryNumber], [Type], [CustomerCode], [CustomerName], [Date], [PoNumber], [Salesman1Code], [Salesman2Code], [AmountKg]) VALUES (1002, N'CB-20260309-0001', N'Bulks', N'DUD001', N'3 R STORE - DUDLEE : (VAC)', '2026-03-09 14:01:10.403', N'123', N'AJ', NULL, 58.00);
INSERT INTO [dbo].[CutBulkEntries] ([Id], [EntryNumber], [Type], [CustomerCode], [CustomerName], [Date], [PoNumber], [Salesman1Code], [Salesman2Code], [AmountKg]) VALUES (1003, N'CB-20260310-0001', N'Bulks', N'CORNISHPOULTRY', N' ', '2026-03-10 13:59:39.300', N'234', N'AJ', NULL, 2.00);
INSERT INTO [dbo].[CutBulkEntries] ([Id], [EntryNumber], [Type], [CustomerCode], [CustomerName], [Date], [PoNumber], [Salesman1Code], [Salesman2Code], [AmountKg]) VALUES (1004, N'CB-20260310-0002', N'Cuts', N'CORNISHPOULTRY', N' ', '2026-03-10 15:48:16.757', N'gh', NULL, NULL, 20.00);
SET IDENTITY_INSERT [dbo].[CutBulkEntries] OFF;
GO
SET IDENTITY_INSERT [dbo].[production_scan] ON;
SET IDENTITY_INSERT [dbo].[salesorderdetailscutsbulk] ON;
SET IDENTITY_INSERT [dbo].[audit_log] ON;
SET IDENTITY_INSERT [dbo].[cut_bulk_entries] ON;
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (1226, N'31881', 0, 4.94, N'PODSO260300059', N'1', N'A', N'IPLCH', NULL, N'system', '2026-04-07 06:18:07.193', NULL, NULL, 0, NULL, NULL, 1, N'01c18632-71e4-4d8c-ad75-56bee828b028', 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2206, N'ORDER-CLOSE', 0, 0.00, N'PODSO260300061', N'2', N'A', NULL, NULL, N'system', '2026-04-09 07:36:12.873', NULL, NULL, 0, NULL, NULL, 0, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2207, N'31881', 0, 4.94, N'PODSO260300060', N'1', N'A', N'IPLCH', NULL, N'system', '2026-04-09 10:24:17.500', NULL, NULL, 0, NULL, NULL, 0, N'7def70e8-39bc-4079-a8bd-c79463a81130', 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2208, N'31169', 0, 0.00, N'PODSO260300059', NULL, NULL, NULL, NULL, N'status-update-sentinel', '2026-04-09 10:38:48.127', NULL, NULL, 0, NULL, NULL, 1, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2209, N'31901', 0, 0.00, N'PODSO260300059', NULL, NULL, NULL, NULL, N'status-update-sentinel', '2026-04-09 10:39:14.060', NULL, NULL, 0, NULL, NULL, 1, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2210, N'3364', 0, 0.00, N'PODSO260300059', NULL, NULL, NULL, NULL, N'status-update-sentinel', '2026-04-09 10:39:15.617', NULL, NULL, 0, NULL, NULL, 1, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2211, N'3715', 0, 0.00, N'PODSO260300059', NULL, NULL, NULL, NULL, N'status-update-sentinel', '2026-04-09 10:39:17.203', NULL, NULL, 0, NULL, NULL, 1, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2212, N'38278', 0, 0.00, N'PODSO260300059', NULL, NULL, NULL, NULL, N'status-update-sentinel', '2026-04-09 10:39:18.863', NULL, NULL, 0, NULL, NULL, 1, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2213, N'ORDER-CLOSE', 0, 0.00, N'PODSO260300059', N'2', N'A', NULL, NULL, N'system', '2026-04-09 10:39:20.697', NULL, NULL, 0, NULL, NULL, 0, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2214, N'34459', 0, 0.00, N'PODSO260300063', NULL, NULL, NULL, NULL, N'status-update-sentinel', '2026-04-09 11:09:16.633', NULL, NULL, 0, NULL, NULL, 1, NULL, 0);
INSERT INTO [dbo].[production_scan] ([scan_id], [product_id], [line_no], [scan_amount_kg], [so_number], [order_status], [item_status], [location], [lot], [created_by], [created_at], [updated_by], [updated_at], [is_deleted], [deleted_by], [deleted_at], [is_prepared], [sync_id], [is_prepared_for_shipment]) VALUES (2215, N'ORDER-CLOSE', 0, 0.00, N'PODSO260300063', N'2', N'A', NULL, NULL, N'system', '2026-04-09 11:09:18.867', NULL, NULL, 0, NULL, NULL, 0, NULL, 0);
INSERT INTO [dbo].[salesorderdetailscutsbulk] ([Id], [SoNumber], [ItemCode], [Description], [BarcodeType], [Quantity], [SyncStatus], [CreatedAt], [ManufacturedQuantity], [IsPrepared]) VALUES (22, N'CB-20260403-0001', N'3001', N'Escaloppe pannee', N'Variable Weight', 3.00, N'Synced', '2026-04-03 06:32:12.463', 9.00, 0);
INSERT INTO [dbo].[salesorderdetailscutsbulk] ([Id], [SoNumber], [ItemCode], [Description], [BarcodeType], [Quantity], [SyncStatus], [CreatedAt], [ManufacturedQuantity], [IsPrepared]) VALUES (23, N'CUT-20260403-0001', N'73639', N'Crates CHK TAR2.1KG Yellow', N'Variable Weight', 1.00, N'Synced', '2026-04-03 09:13:40.317', 1.00, 0);
INSERT INTO [dbo].[salesorderdetailscutsbulk] ([Id], [SoNumber], [ItemCode], [Description], [BarcodeType], [Quantity], [SyncStatus], [CreatedAt], [ManufacturedQuantity], [IsPrepared]) VALUES (24, N'BLK-20260403-0001', N'73659', N'PALLETS (Poultry)', N'Variable Weight', 1.00, N'Synced', '2026-04-03 09:13:40.347', 1.00, 1);
INSERT INTO [dbo].[salesorderdetailscutsbulk] ([Id], [SoNumber], [ItemCode], [Description], [BarcodeType], [Quantity], [SyncStatus], [CreatedAt], [ManufacturedQuantity], [IsPrepared]) VALUES (25, N'CUT-20260403-0002', N'3001', N'Escaloppe pannee', N'Variable Weight', 4.00, N'Synced', '2026-04-03 09:13:40.347', 4.00, 0);
INSERT INTO [dbo].[audit_log] ([audit_id], [entity_name], [entity_id], [action_type], [payload], [performed_by], [performed_at]) VALUES (153, N'production_scan', 0, N'CLOSE_ORDER', N'{"soNumber":"BLK-20260403-0001","closedBy":"system"}', N'system', '2026-04-03 11:56:43.460');
INSERT INTO [dbo].[audit_log] ([audit_id], [entity_name], [entity_id], [action_type], [payload], [performed_by], [performed_at]) VALUES (1153, N'production_scan', 0, N'CLOSE_ORDER', N'{"soNumber":"PODSO260300061","closedBy":"system"}', N'system', '2026-04-09 07:36:12.873');
INSERT INTO [dbo].[audit_log] ([audit_id], [entity_name], [entity_id], [action_type], [payload], [performed_by], [performed_at]) VALUES (1154, N'production_scan', 0, N'CLOSE_ORDER', N'{"soNumber":"PODSO260300059","closedBy":"system"}', N'system', '2026-04-09 10:39:20.700');
INSERT INTO [dbo].[audit_log] ([audit_id], [entity_name], [entity_id], [action_type], [payload], [performed_by], [performed_at]) VALUES (1155, N'production_scan', 0, N'CLOSE_ORDER', N'{"soNumber":"PODSO260300063","closedBy":"system"}', N'system', '2026-04-09 11:09:18.867');
SET IDENTITY_INSERT [dbo].[production_scan] OFF;
SET IDENTITY_INSERT [dbo].[salesorderdetailscutsbulk] OFF;
SET IDENTITY_INSERT [dbo].[audit_log] OFF;
SET IDENTITY_INSERT [dbo].[cut_bulk_entries] OFF;
GO

