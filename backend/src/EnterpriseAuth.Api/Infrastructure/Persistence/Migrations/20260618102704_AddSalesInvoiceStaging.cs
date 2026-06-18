using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Migrations.ScanProductionDb
{
    /// <inheritdoc />
    public partial class AddSalesInvoiceStaging : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SalesInvoiceSoapAudits");

            migrationBuilder.DropPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropIndex(
                name: "IX_StagingSalesInvoiceHeaders_IsProcessedByX3",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "CreatedByUserId",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "CustomerName",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "GrandTotal",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "TotalDiscount",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "TotalVat",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.RenameColumn(
                name: "Id",
                table: "StagingSalesInvoiceLines",
                newName: "LineNo");

            migrationBuilder.RenameColumn(
                name: "TransactionType",
                table: "StagingSalesInvoiceHeaders",
                newName: "SalesSite");

            migrationBuilder.RenameColumn(
                name: "CreatedByUserName",
                table: "StagingSalesInvoiceHeaders",
                newName: "SalesRep");

            migrationBuilder.RenameColumn(
                name: "AppVersion",
                table: "StagingSalesInvoiceHeaders",
                newName: "PricingRule");

            migrationBuilder.AlterColumn<double>(
                name: "VatAmount",
                table: "StagingSalesInvoiceLines",
                type: "float",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,5)",
                oldPrecision: 18,
                oldScale: 5);

            migrationBuilder.AlterColumn<double>(
                name: "Total",
                table: "StagingSalesInvoiceLines",
                type: "float",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,5)",
                oldPrecision: 18,
                oldScale: 5);

            migrationBuilder.AlterColumn<double>(
                name: "Quantity",
                table: "StagingSalesInvoiceLines",
                type: "float",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,5)",
                oldPrecision: 18,
                oldScale: 5);

            migrationBuilder.AlterColumn<string>(
                name: "Name",
                table: "StagingSalesInvoiceLines",
                type: "nvarchar(500)",
                maxLength: 500,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(255)",
                oldMaxLength: 255,
                oldNullable: true);

            migrationBuilder.DropColumn(
                name: "LineNo",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.AddColumn<int>(
                name: "LineNo",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.DropColumn(
                name: "LineId",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.AddColumn<int>(
                name: "LineId",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                defaultValue: 0)
                .Annotation("SqlServer:Identity", "1, 1");

            migrationBuilder.AlterColumn<double>(
                name: "DiscountAmount",
                table: "StagingSalesInvoiceLines",
                type: "float",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,5)",
                oldPrecision: 18,
                oldScale: 5);

            migrationBuilder.AlterColumn<double>(
                name: "BasePrice",
                table: "StagingSalesInvoiceLines",
                type: "float",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,5)",
                oldPrecision: 18,
                oldScale: 5);



            migrationBuilder.AlterColumn<string>(
                name: "DeviceId",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(255)",
                maxLength: 255,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(100)",
                oldMaxLength: 100,
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "CustomerCode",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(50)",
                oldMaxLength: 50,
                oldNullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CreatedBy",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DueDate",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "UserName",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines",
                column: "LineId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "CreatedBy",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "DueDate",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "UserName",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.RenameColumn(
                name: "LineNo",
                table: "StagingSalesInvoiceLines",
                newName: "Id");

            migrationBuilder.RenameColumn(
                name: "SalesSite",
                table: "StagingSalesInvoiceHeaders",
                newName: "TransactionType");

            migrationBuilder.RenameColumn(
                name: "SalesRep",
                table: "StagingSalesInvoiceHeaders",
                newName: "CreatedByUserName");

            migrationBuilder.RenameColumn(
                name: "PricingRule",
                table: "StagingSalesInvoiceHeaders",
                newName: "AppVersion");

            migrationBuilder.AlterColumn<decimal>(
                name: "VatAmount",
                table: "StagingSalesInvoiceLines",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                oldClrType: typeof(double),
                oldType: "float");

            migrationBuilder.AlterColumn<decimal>(
                name: "Total",
                table: "StagingSalesInvoiceLines",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                oldClrType: typeof(double),
                oldType: "float");

            migrationBuilder.AlterColumn<decimal>(
                name: "Quantity",
                table: "StagingSalesInvoiceLines",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                oldClrType: typeof(double),
                oldType: "float");

            migrationBuilder.AlterColumn<string>(
                name: "Name",
                table: "StagingSalesInvoiceLines",
                type: "nvarchar(255)",
                maxLength: 255,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(500)",
                oldMaxLength: 500,
                oldNullable: true);

            migrationBuilder.AlterColumn<decimal>(
                name: "DiscountAmount",
                table: "StagingSalesInvoiceLines",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                oldClrType: typeof(double),
                oldType: "float");

            migrationBuilder.AlterColumn<decimal>(
                name: "BasePrice",
                table: "StagingSalesInvoiceLines",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                oldClrType: typeof(double),
                oldType: "float");

            migrationBuilder.AlterColumn<int>(
                name: "LineId",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                oldClrType: typeof(int),
                oldType: "int")
                .OldAnnotation("SqlServer:Identity", "1, 1");

            migrationBuilder.AlterColumn<int>(
                name: "Id",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                oldClrType: typeof(int),
                oldType: "int")
                .Annotation("SqlServer:Identity", "1, 1");

            migrationBuilder.AlterColumn<string>(
                name: "DeviceId",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(255)",
                oldMaxLength: 255,
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "CustomerCode",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(100)",
                oldMaxLength: 100,
                oldNullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CreatedByUserId",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CustomerName",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(150)",
                maxLength: 150,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "GrandTotal",
                table: "StagingSalesInvoiceHeaders",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<int>(
                name: "Status",
                table: "StagingSalesInvoiceHeaders",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "TotalDiscount",
                table: "StagingSalesInvoiceHeaders",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "TotalVat",
                table: "StagingSalesInvoiceHeaders",
                type: "decimal(18,5)",
                precision: 18,
                scale: 5,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines",
                column: "Id");

            migrationBuilder.CreateTable(
                name: "SalesInvoiceSoapAudits",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CustomerCode = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    DeviceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    ErrorMessage = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    InvoiceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    IsSuccess = table.Column<bool>(type: "bit", nullable: false),
                    RequestPayload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    ResponsePayload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    TriggeredByUserName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SalesInvoiceSoapAudits", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_StagingSalesInvoiceHeaders_IsProcessedByX3",
                table: "StagingSalesInvoiceHeaders",
                column: "IsProcessedByX3");
        }
    }
}
