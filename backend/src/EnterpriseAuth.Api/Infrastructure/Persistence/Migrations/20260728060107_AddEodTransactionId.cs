using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Migrations.ScanProductionDb
{
    /// <inheritdoc />
    public partial class AddEodTransactionId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "EodTransactionId",
                table: "StagingEod",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "EodTransactionId",
                table: "ProductionScanTransactions",
                type: "uniqueidentifier",
                nullable: true);

            // migrationBuilder.AddColumn<bool>(
            //     name: "IsEodProcessed",
            //     table: "ProductionScanTransactions",
            //     type: "bit",
            //     nullable: false,
            //     defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EodTransactionId",
                table: "StagingEod");

            migrationBuilder.DropColumn(
                name: "EodTransactionId",
                table: "ProductionScanTransactions");

            migrationBuilder.DropColumn(
                name: "IsEodProcessed",
                table: "ProductionScanTransactions");
        }
    }
}
