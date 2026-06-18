using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class FixSalesInvoiceLinePK : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "LineId",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.AddColumn<int>(
                name: "LineId",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "Id",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                defaultValue: 0)
                .Annotation("SqlServer:Identity", "1, 1");

            migrationBuilder.AddPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines",
                column: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.DropColumn(
                name: "Id",
                table: "StagingSalesInvoiceLines");

            migrationBuilder.AlterColumn<int>(
                name: "LineId",
                table: "StagingSalesInvoiceLines",
                type: "int",
                nullable: false,
                oldClrType: typeof(int),
                oldType: "int")
                .Annotation("SqlServer:Identity", "1, 1");

            migrationBuilder.AddPrimaryKey(
                name: "PK_StagingSalesInvoiceLines",
                table: "StagingSalesInvoiceLines",
                column: "LineId");
        }
    }
}
