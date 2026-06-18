using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSalesInvoiceSoapAudit : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DueDate",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "PricingRule",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.RenameColumn(
                name: "UserName",
                table: "StagingSalesInvoiceHeaders",
                newName: "CreatedByUserName");

            migrationBuilder.RenameColumn(
                name: "SalesSite",
                table: "StagingSalesInvoiceHeaders",
                newName: "TransactionType");

            migrationBuilder.RenameColumn(
                name: "SalesRep",
                table: "StagingSalesInvoiceHeaders",
                newName: "AppVersion");

            migrationBuilder.RenameColumn(
                name: "CreatedBy",
                table: "StagingSalesInvoiceHeaders",
                newName: "CreatedByUserId");

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

            migrationBuilder.CreateTable(
                name: "SalesInvoiceSoapAudits",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    InvoiceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    CustomerCode = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    RequestPayload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    ResponsePayload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    IsSuccess = table.Column<bool>(type: "bit", nullable: false),
                    ErrorMessage = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    TriggeredByUserName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    DeviceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SalesInvoiceSoapAudits", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SalesInvoiceSoapAudits");

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
                name: "TransactionType",
                table: "StagingSalesInvoiceHeaders",
                newName: "SalesSite");

            migrationBuilder.RenameColumn(
                name: "CreatedByUserName",
                table: "StagingSalesInvoiceHeaders",
                newName: "UserName");

            migrationBuilder.RenameColumn(
                name: "CreatedByUserId",
                table: "StagingSalesInvoiceHeaders",
                newName: "CreatedBy");

            migrationBuilder.RenameColumn(
                name: "AppVersion",
                table: "StagingSalesInvoiceHeaders",
                newName: "SalesRep");

            migrationBuilder.AddColumn<string>(
                name: "DueDate",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PricingRule",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);
        }
    }
}
