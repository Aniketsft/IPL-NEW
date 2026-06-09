using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddLabelAuditsTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Excesses_ItemCode_DeliveryDate",
                table: "Excesses");

            migrationBuilder.DropIndex(
                name: "IX_Excesses_SourceBulkSoNumber",
                table: "Excesses");

            migrationBuilder.CreateTable(
                name: "LabelAudits",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    LabelId = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    ReferenceNumber = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    LabelType = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    CustomerName = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    ProductCode = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    TotalWeight = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    ManifestJson = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    PrintedBy = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LabelAudits", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Excess_Date_Item",
                table: "Excesses",
                columns: new[] { "DeliveryDate", "ItemCode" });

            migrationBuilder.CreateIndex(
                name: "UQ_Excess_BulkSO_Item",
                table: "Excesses",
                columns: new[] { "SourceBulkSoNumber", "ItemCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_LabelAudits_LabelId",
                table: "LabelAudits",
                column: "LabelId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_LabelAudits_LabelType_CreatedAt",
                table: "LabelAudits",
                columns: new[] { "LabelType", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_LabelAudits_ReferenceNumber",
                table: "LabelAudits",
                column: "ReferenceNumber");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "LabelAudits");

            migrationBuilder.DropIndex(
                name: "IX_Excess_Date_Item",
                table: "Excesses");

            migrationBuilder.DropIndex(
                name: "UQ_Excess_BulkSO_Item",
                table: "Excesses");

            migrationBuilder.CreateIndex(
                name: "IX_Excesses_ItemCode_DeliveryDate",
                table: "Excesses",
                columns: new[] { "ItemCode", "DeliveryDate" });

            migrationBuilder.CreateIndex(
                name: "IX_Excesses_SourceBulkSoNumber",
                table: "Excesses",
                column: "SourceBulkSoNumber");
        }
    }
}
