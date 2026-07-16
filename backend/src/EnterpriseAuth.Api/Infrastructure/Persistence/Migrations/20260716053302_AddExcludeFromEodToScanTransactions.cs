using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddExcludeFromEodToScanTransactions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "ExcludeFromEod",
                table: "SalesOrders",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "ExcludeFromEod",
                table: "ProductionScanTransactions",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "ExcludeFromEod",
                table: "Excesses",
                type: "bit",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ExcludeFromEod",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "ExcludeFromEod",
                table: "ProductionScanTransactions");

            migrationBuilder.DropColumn(
                name: "ExcludeFromEod",
                table: "Excesses");
        }
    }
}
