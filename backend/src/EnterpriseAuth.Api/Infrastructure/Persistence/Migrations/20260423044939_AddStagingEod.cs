using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStagingEod : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // migrationBuilder.AddColumn<bool>(
            //    name: "IsProcessed",
            //    table: "Staging",
            //    ... already exists

            // migrationBuilder.CreateTable(
            //    name: "StagingEod",
            //    ... already exists
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "StagingEod");

            migrationBuilder.DropColumn(
                name: "IsProcessed",
                table: "Staging");

            migrationBuilder.DropColumn(
                name: "ZVACITM_0",
                table: "Staging");

            migrationBuilder.DropColumn(
                name: "IsProcessed",
                table: "SalesOrders");
        }
    }
}
