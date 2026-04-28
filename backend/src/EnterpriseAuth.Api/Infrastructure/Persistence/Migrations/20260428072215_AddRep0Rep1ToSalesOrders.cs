using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddRep0Rep1ToSalesOrders : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Rep0",
                table: "SalesOrders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Rep1",
                table: "SalesOrders",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Rep0",
                table: "SalesOrders");

            migrationBuilder.DropColumn(
                name: "Rep1",
                table: "SalesOrders");
        }
    }
}
