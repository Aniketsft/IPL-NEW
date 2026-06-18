using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStagingSalesInvoices : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "StagingSalesInvoiceHeaders",
                columns: table => new
                {
                    InvoiceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    SalesSite = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    CustomerCode = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    SalesRep = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    PricingRule = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    DueDate = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    UserName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    IsSynced = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    CreatedBy = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    DeviceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    IsProcessedByX3 = table.Column<bool>(type: "bit", nullable: false),
                    SyncedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StagingSalesInvoiceHeaders", x => x.InvoiceId);
                });

            migrationBuilder.CreateTable(
                name: "StagingSalesInvoiceLines",
                columns: table => new
                {
                    LineId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    InvoiceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    Sku = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    Name = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    Quantity = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    BasePrice = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    DiscountAmount = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    VatAmount = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    Total = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StagingSalesInvoiceLines", x => x.LineId);
                    table.ForeignKey(
                        name: "FK_StagingSalesInvoiceLines_StagingSalesInvoiceHeaders_InvoiceId",
                        column: x => x.InvoiceId,
                        principalTable: "StagingSalesInvoiceHeaders",
                        principalColumn: "InvoiceId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_StagingSalesInvoiceHeaders_IsProcessedByX3",
                table: "StagingSalesInvoiceHeaders",
                column: "IsProcessedByX3");

            migrationBuilder.CreateIndex(
                name: "IX_StagingSalesInvoiceLines_InvoiceId",
                table: "StagingSalesInvoiceLines",
                column: "InvoiceId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "StagingSalesInvoiceLines");

            migrationBuilder.DropTable(
                name: "StagingSalesInvoiceHeaders");
        }
    }
}
