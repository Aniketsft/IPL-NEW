using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    public partial class LinkEodToScanTransactions : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "EodProcessAuditId",
                table: "ProductionScanTransactions",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_ProductionScanTransactions_EodProcessAuditId",
                table: "ProductionScanTransactions",
                column: "EodProcessAuditId");

            migrationBuilder.AddForeignKey(
                name: "FK_ProductionScanTransactions_EodProcessAudits_EodProcessAuditId",
                table: "ProductionScanTransactions",
                column: "EodProcessAuditId",
                principalTable: "EodProcessAudits",
                principalColumn: "Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ProductionScanTransactions_EodProcessAudits_EodProcessAuditId",
                table: "ProductionScanTransactions");

            migrationBuilder.DropIndex(
                name: "IX_ProductionScanTransactions_EodProcessAuditId",
                table: "ProductionScanTransactions");

            migrationBuilder.DropColumn(
                name: "EodProcessAuditId",
                table: "ProductionScanTransactions");
        }
    }
}
