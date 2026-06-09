using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddEaQuantityToStagingEod : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'StagingEod' AND COLUMN_NAME = 'EaQuantity')
                BEGIN
                    ALTER TABLE StagingEod ADD EaQuantity decimal(18,5) NOT NULL DEFAULT 0;
                END

                IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionScanTransactions' AND COLUMN_NAME = 'EaQuantity')
                BEGIN
                    ALTER TABLE ProductionScanTransactions ADD EaQuantity decimal(18,5) NULL;
                END

                IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductionLineStates' AND COLUMN_NAME = 'TotalEaQty')
                BEGIN
                    ALTER TABLE ProductionLineStates ADD TotalEaQty decimal(18,5) NOT NULL DEFAULT 0;
                END
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EaQuantity",
                table: "StagingEod");

            migrationBuilder.DropColumn(
                name: "EaQuantity",
                table: "ProductionScanTransactions");

            migrationBuilder.DropColumn(
                name: "TotalEaQty",
                table: "ProductionLineStates");
        }
    }
}
