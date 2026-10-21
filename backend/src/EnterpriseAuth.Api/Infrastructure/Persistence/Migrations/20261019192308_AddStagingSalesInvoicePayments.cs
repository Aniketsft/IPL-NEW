using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStagingSalesInvoicePayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[AuditLogs]') AND name = 'Site')
    ALTER TABLE [AuditLogs] ADD [Site] nvarchar(50) NULL;

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'DeviceLocations')
BEGIN
    CREATE TABLE [DeviceLocations] (
        [DeviceId] nvarchar(100) NOT NULL,
        [MacAddress] nvarchar(50) NULL,
        [DeviceName] nvarchar(150) NOT NULL,
        [SiteCode] nvarchar(20) NOT NULL,
        [WarehouseCode] nvarchar(20) NULL,
        [LocationCode] nvarchar(30) NOT NULL,
        [AssignedUserId] uniqueidentifier NULL,
        [AssignedUserName] nvarchar(100) NULL,
        [IsActive] bit NOT NULL,
        [CreatedAt] datetime2 NOT NULL,
        [UpdatedAt] datetime2 NOT NULL,
        [UpdatedBy] nvarchar(100) NOT NULL,
        CONSTRAINT [PK_DeviceLocations] PRIMARY KEY ([DeviceId])
    );
END;

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StagingCreditNoteHeaders')
BEGIN
    CREATE TABLE [StagingCreditNoteHeaders] (
        [CreditNoteId] nvarchar(100) NOT NULL,
        [CreditNoteType] nvarchar(50) NOT NULL,
        [X3CreditNoteType] nvarchar(50) NOT NULL,
        [SalesSite] nvarchar(50) NOT NULL,
        [CustomerCode] nvarchar(100) NOT NULL,
        [CustomerName] nvarchar(255) NOT NULL,
        [Currency] nvarchar(10) NOT NULL,
        [GrandTotal] float NOT NULL,
        [OriginalInvoiceId] nvarchar(100) NULL,
        [LinkedInvoiceIds] nvarchar(max) NULL,
        [SettlementType] nvarchar(50) NOT NULL,
        [Reference] nvarchar(100) NULL,
        [IsSynced] int NOT NULL,
        [X3DocumentId] nvarchar(100) NULL,
        [CreatedAt] nvarchar(50) NOT NULL,
        [CreatedBy] nvarchar(200) NOT NULL,
        [DeviceId] nvarchar(255) NULL,
        [IsProcessedByX3] bit NOT NULL,
        [SyncedAt] datetime2 NOT NULL,
        CONSTRAINT [PK_StagingCreditNoteHeaders] PRIMARY KEY ([CreditNoteId])
    );
END;

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StagingCreditNoteLines')
BEGIN
    CREATE TABLE [StagingCreditNoteLines] (
        [LineId] int IDENTITY(1,1) NOT NULL,
        [CreditNoteId] nvarchar(100) NOT NULL,
        [LineNo] int NOT NULL,
        [Quantity] float NOT NULL,
        [OriginInvoiceId] nvarchar(100) NULL,
        [OriginLineNo] int NULL,
        [StandaloneSku] nvarchar(100) NULL,
        [StandaloneName] nvarchar(500) NULL,
        [StandaloneSalesUnit] nvarchar(20) NULL,
        [StandalonePrice] float NULL,
        [StandaloneTaxRule] nvarchar(20) NULL,
        [StandaloneLot] nvarchar(100) NULL,
        [StandaloneWarehouse] nvarchar(50) NULL,
        [StandaloneCce0] nvarchar(50) NULL,
        CONSTRAINT [PK_StagingCreditNoteLines] PRIMARY KEY ([LineId])
    );
END;

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StagingCreditNoteRefunds')
BEGIN
    CREATE TABLE [StagingCreditNoteRefunds] (
        [RefundId] int IDENTITY(1,1) NOT NULL,
        [CreditNoteId] nvarchar(100) NOT NULL,
        [Method] nvarchar(50) NOT NULL,
        [Amount] float NOT NULL,
        [BankCode] nvarchar(50) NULL,
        [BankName] nvarchar(200) NULL,
        [ChequeNumber] nvarchar(100) NULL,
        [ChequeDate] nvarchar(50) NULL,
        CONSTRAINT [PK_StagingCreditNoteRefunds] PRIMARY KEY ([RefundId])
    );
END;

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StagingSalesInvoicePayments')
BEGIN
    CREATE TABLE [StagingSalesInvoicePayments] (
        [PaymentId] int IDENTITY(1,1) NOT NULL,
        [LocalPaymentId] int NULL,
        [DocumentType] nvarchar(50) NOT NULL DEFAULT 'INVOICE',
        [DocumentId] nvarchar(100) NOT NULL,
        [X3DocumentType] nvarchar(10) NOT NULL DEFAULT 'SINV',
        [X3EntryType] nvarchar(10) NOT NULL DEFAULT 'REC',
        [X3Sign] int NOT NULL DEFAULT 2,
        [X3InvoiceDocumentId] nvarchar(100) NULL,
        [X3PaymentId] nvarchar(100) NULL,
        [PaymentMethod] nvarchar(50) NOT NULL,
        [X3PaymentMode] nvarchar(10) NOT NULL DEFAULT 'CSH',
        [Amount] decimal(18,4) NOT NULL,
        [Currency] nvarchar(10) NOT NULL DEFAULT 'MUR',
        [SalesSite] nvarchar(50) NOT NULL DEFAULT 'IPL',
        [CustomerCode] nvarchar(100) NOT NULL,
        [CustomerName] nvarchar(255) NULL,
        [BankCode] nvarchar(50) NULL,
        [BankName] nvarchar(200) NULL,
        [ChequeNumber] nvarchar(100) NULL,
        [ChequeDate] nvarchar(50) NULL,
        [QrTransactionRef] nvarchar(255) NULL,
        [IsProcessedByX3] bit NOT NULL DEFAULT 0,
        [IsSynced] int NOT NULL DEFAULT 0,
        [SyncedAt] datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        [CreatedAt] nvarchar(50) NULL,
        [CreatedBy] nvarchar(200) NULL,
        [UserName] nvarchar(200) NULL,
        [DeviceId] nvarchar(255) NULL,
        [SoapRequestNumber] nvarchar(100) NULL,
        [SoapError] nvarchar(max) NULL,
        CONSTRAINT [PK_StagingSalesInvoicePayments] PRIMARY KEY ([PaymentId])
    );
END;

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_StagingSalesInvoicePayments_DocumentType_DocumentId' AND object_id = OBJECT_ID('StagingSalesInvoicePayments'))
    CREATE NONCLUSTERED INDEX [IX_StagingSalesInvoicePayments_DocumentType_DocumentId] ON [StagingSalesInvoicePayments] ([DocumentType], [DocumentId]);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_StagingSalesInvoicePayments_IsProcessedByX3' AND object_id = OBJECT_ID('StagingSalesInvoicePayments'))
    CREATE NONCLUSTERED INDEX [IX_StagingSalesInvoicePayments_IsProcessedByX3] ON [StagingSalesInvoicePayments] ([IsProcessedByX3]);
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DeviceLocations");

            migrationBuilder.DropTable(
                name: "StagingCreditNoteLines");

            migrationBuilder.DropTable(
                name: "StagingCreditNoteRefunds");

            migrationBuilder.DropTable(
                name: "StagingSalesInvoicePayments");

            migrationBuilder.DropTable(
                name: "StagingCreditNoteHeaders");

            migrationBuilder.DropColumn(
                name: "Site",
                table: "AuditLogs");
        }
    }
}
