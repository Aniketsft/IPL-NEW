using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSalesmanSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
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
        }
    }
}
