using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStagingTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Staging",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    ZSDHTYP_0 = table.Column<string>(type: "nvarchar(5)", maxLength: 5, nullable: false),
                    ZSALFCY_0 = table.Column<string>(type: "nvarchar(5)", maxLength: 5, nullable: true),
                    ZSTOFCY_0 = table.Column<string>(type: "nvarchar(5)", maxLength: 5, nullable: false),
                    ZSDHNUM_0 = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: true),
                    ZBPCORD_0 = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: true),
                    ZSUR_0 = table.Column<string>(type: "nvarchar(5)", maxLength: 5, nullable: false),
                    ZSHIDAT_0 = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ZDLVDAT_0 = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ZCFMFLG_0 = table.Column<int>(type: "int", nullable: false),
                    ZLOCFCY_0 = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    ZLOC_0 = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    ZSOHNUM_0 = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    ZSOPLIN_0 = table.Column<int>(type: "int", nullable: false),
                    ZITMREF_0 = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    ZSAU_0 = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: true),
                    ZQTY_0 = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Staging", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Staging_ZSOHNUM_0",
                table: "Staging",
                column: "ZSOHNUM_0");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Staging");
        }
    }
}
