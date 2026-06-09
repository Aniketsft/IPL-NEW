using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddOptimizedEodIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameIndex(
                name: "IX_Staging_IsProcessed_SONum",
                table: "Staging",
                newName: "IX_Staging_EOD_Processing");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameIndex(
                name: "IX_Staging_EOD_Processing",
                table: "Staging",
                newName: "IX_Staging_IsProcessed_SONum");
        }
    }
}
