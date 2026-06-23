using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Migrations.ScanProductionDb
{
    /// <inheritdoc />
    public partial class AddStagingSalesInvoiceLotLocation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Cce0",
                table: "StagingSalesInvoiceLines",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "LotNumber",
                table: "StagingSalesInvoiceLines",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SalesUnit",
                table: "StagingSalesInvoiceLines",
                type: "nvarchar(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Warehouse",
                table: "StagingSalesInvoiceLines",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "InvoiceType",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "Reference",
                table: "StagingSalesInvoiceHeaders",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Cce0",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "LotNumber",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "SalesUnit",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "Warehouse",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "InvoiceType",
                table: "StagingSalesInvoiceHeaders");

            migrationBuilder.DropColumn(
                name: "Reference",
                table: "StagingSalesInvoiceHeaders");
        }
    }
}
