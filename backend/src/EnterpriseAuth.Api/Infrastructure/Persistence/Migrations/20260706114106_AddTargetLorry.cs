using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Migrations.ScanProductionDb
{
    /// <inheritdoc />
    public partial class AddTargetLorry : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                "IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'StagingEod' AND COLUMN_NAME = 'DeviceId') " +
                "ALTER TABLE [StagingEod] ADD [DeviceId] nvarchar(255) NULL;");

            migrationBuilder.Sql(
                "IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'StagingEod' AND COLUMN_NAME = 'LotNumber') " +
                "ALTER TABLE [StagingEod] ADD [LotNumber] nvarchar(100) NULL;");

            migrationBuilder.Sql(
                "IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrders' AND COLUMN_NAME = 'TargetLorry') " +
                "ALTER TABLE [SalesOrders] ADD [TargetLorry] nvarchar(100) NULL;");

            migrationBuilder.Sql(
                "IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'LabelAudits' AND COLUMN_NAME = 'DeviceId') " +
                "ALTER TABLE [LabelAudits] ADD [DeviceId] nvarchar(100) NULL;");

            migrationBuilder.Sql(
                "IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'AuditLogs' AND COLUMN_NAME = 'DeviceId') " +
                "ALTER TABLE [AuditLogs] ADD [DeviceId] nvarchar(100) NULL;");

            /*
            migrationBuilder.CreateTable(
                name: "EodProcessAudits",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    EodDate = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    WorkOrderNumber = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    TriggeredBy = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    DeviceId = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    IsDeactivated = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EodProcessAudits", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "X3SoapAudits",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ActionName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    Identifier = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    RequestPayload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    ResponsePayload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    IsSuccess = table.Column<bool>(type: "bit", nullable: false),
                    ErrorMessage = table.Column<string>(type: "nvarchar(2000)", maxLength: 2000, nullable: true),
                    TriggeredBy = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                    DeviceId = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_X3SoapAudits", x => x.Id);
                });
            */
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EodProcessAudits");

            migrationBuilder.DropTable(
                name: "X3SoapAudits");

            migrationBuilder.DropColumn(
                name: "DeviceId",
                table: "StagingEod");

            migrationBuilder.DropColumn(
                name: "LotNumber",
                table: "StagingEod");

            migrationBuilder.DropColumn(
                name: "TargetLorry",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "DeviceId",
                table: "LabelAudits");

            migrationBuilder.DropColumn(
                name: "DeviceId",
                table: "AuditLogs");
        }
    }
}
