using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class FixGlobalSettingsPK : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_GlobalSettings",
                table: "GlobalSettings");

            migrationBuilder.AddPrimaryKey(
                name: "PK_GlobalSettings",
                table: "GlobalSettings",
                column: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_GlobalSettings",
                table: "GlobalSettings");

            migrationBuilder.AddPrimaryKey(
                name: "PK_GlobalSettings",
                table: "GlobalSettings",
                column: "SettingKey");
        }
    }
}
