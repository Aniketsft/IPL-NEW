using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddEodFlags : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EodStatuses");

            migrationBuilder.AddColumn<bool>(
                name: "IsCompleted",
                table: "StagingEod",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "IsProcessed",
                table: "StagingEod",
                type: "bit",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IsCompleted",
                table: "StagingEod");

            migrationBuilder.DropColumn(
                name: "IsProcessed",
                table: "StagingEod");

            migrationBuilder.CreateTable(
                name: "EodStatuses",
                columns: table => new
                {
                    ProductionDate = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    CompletedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    CompletedBy = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    LastUpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    Status = table.Column<int>(type: "int", nullable: false),
                    WorkOrder = table.Column<string>(type: "nvarchar(450)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EodStatuses", x => x.ProductionDate);
                });

            migrationBuilder.CreateIndex(
                name: "IX_EodStatuses_WorkOrder",
                table: "EodStatuses",
                column: "WorkOrder");
        }
    }
}
