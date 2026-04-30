using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddEodProcessingIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DeliveryRepCode",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "DeliverySalesman",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "OriginalSoNumber",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "OriginalSoSalesman",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "SoSalesman",
                table: "SalesOrders");

            migrationBuilder.CreateIndex(
                name: "IX_StagingEod_IsProcessed_WorkOrder",
                table: "StagingEod",
                columns: new[] { "IsProcessed", "WorkOrderNumber" });

            migrationBuilder.CreateIndex(
                name: "IX_Staging_IsProcessed_SONum",
                table: "Staging",
                columns: new[] { "IsProcessed", "ZSOHNUM_0" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_StagingEod_IsProcessed_WorkOrder",
                table: "StagingEod");

            migrationBuilder.DropIndex(
                name: "IX_Staging_IsProcessed_SONum",
                table: "Staging");

            migrationBuilder.AddColumn<string>(
                name: "DeliveryRepCode",
                table: "SalesOrders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DeliverySalesman",
                table: "SalesOrders",
                type: "nvarchar(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OriginalSoNumber",
                table: "SalesOrders",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OriginalSoSalesman",
                table: "SalesOrders",
                type: "nvarchar(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SoSalesman",
                table: "SalesOrders",
                type: "nvarchar(200)",
                maxLength: 200,
                nullable: true);
        }
    }
}
