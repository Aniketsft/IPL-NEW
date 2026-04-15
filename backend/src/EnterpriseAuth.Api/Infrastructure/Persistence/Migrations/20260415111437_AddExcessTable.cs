using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EnterpriseAuth.Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddExcessTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AuditLogs",
                columns: table => new
                {
                    AuditId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    EntityName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    EntityId = table.Column<int>(type: "int", nullable: false),
                    ActionType = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    Payload = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    PerformedBy = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    PerformedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AuditLogs", x => x.AuditId);
                });

            migrationBuilder.CreateTable(
                name: "Excesses",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SourceBulkSoNumber = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    ItemCode = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    DeliveryDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    TotalManufacturedQuantity = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    AllocatedQuantity = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    RemainingExcess = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CreatedBy = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<string>(type: "nvarchar(max)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Excesses", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "OrderShipmentStatus",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    SoNumber = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    IsPreparedForShipment = table.Column<bool>(type: "bit", nullable: false),
                    IsValidated = table.Column<bool>(type: "bit", nullable: false),
                    UpdatedBy = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OrderShipmentStatus", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "OrderStatusHistory",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    SoNumber = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    Status = table.Column<int>(type: "int", nullable: false),
                    ChangedBy = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    ChangedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OrderStatusHistory", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "SalesOrders",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SourceOrderId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    SourceSystem = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    PoNumber = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    OrderDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    DeliveryDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    Salesman = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                    CustomerCode = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    CustomerName = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    Site = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    Status = table.Column<int>(type: "int", nullable: false),
                    IsArchived = table.Column<bool>(type: "bit", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SalesOrders", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "SalesOrderLines",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SalesOrderId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ItemCode = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    OrderedQuantity = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    Unit = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    Location = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    Lot = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    LineNumber = table.Column<int>(type: "int", nullable: false),
                    LineStatus = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SalesOrderLines", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SalesOrderLines_SalesOrders_SalesOrderId",
                        column: x => x.SalesOrderId,
                        principalTable: "SalesOrders",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ProductionLineStates",
                columns: table => new
                {
                    SalesOrderLineId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    TotalManufacturedQty = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    TotalPreparedQty = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    TotalValidatedQty = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    IsLineCompleted = table.Column<bool>(type: "bit", nullable: false),
                    IsPrepared = table.Column<bool>(type: "bit", nullable: false),
                    LastScanId = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ProductionLineStates", x => x.SalesOrderLineId);
                    table.ForeignKey(
                        name: "FK_ProductionLineStates_SalesOrderLines_SalesOrderLineId",
                        column: x => x.SalesOrderLineId,
                        principalTable: "SalesOrderLines",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ProductionScanTransactions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SalesOrderLineId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ScanAmountKg = table.Column<decimal>(type: "decimal(18,5)", precision: 18, scale: 5, nullable: false),
                    Barcode = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    LotNumber = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    Location = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    SyncId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    ItemStatus = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    DeviceId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    CreatedBy = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    IsArchived = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ProductionScanTransactions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ProductionScanTransactions_SalesOrderLines_SalesOrderLineId",
                        column: x => x.SalesOrderLineId,
                        principalTable: "SalesOrderLines",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_EntityLookup",
                table: "AuditLogs",
                columns: new[] { "EntityName", "EntityId" });

            migrationBuilder.CreateIndex(
                name: "IX_Excesses_ItemCode_DeliveryDate",
                table: "Excesses",
                columns: new[] { "ItemCode", "DeliveryDate" });

            migrationBuilder.CreateIndex(
                name: "IX_Excesses_SourceBulkSoNumber",
                table: "Excesses",
                column: "SourceBulkSoNumber");

            migrationBuilder.CreateIndex(
                name: "UQ_OrderShipmentStatus_SoNumber",
                table: "OrderShipmentStatus",
                column: "SoNumber",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_OrderStatusHistory_SoNumber",
                table: "OrderStatusHistory",
                column: "SoNumber");

            migrationBuilder.CreateIndex(
                name: "IX_ProductionScanTransactions_SalesOrderLineId_IsDeleted_IsArchived",
                table: "ProductionScanTransactions",
                columns: new[] { "SalesOrderLineId", "IsDeleted", "IsArchived" });

            migrationBuilder.CreateIndex(
                name: "IX_ProductionScanTransactions_SyncId",
                table: "ProductionScanTransactions",
                column: "SyncId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SalesOrderLines_SalesOrderId_ItemCode",
                table: "SalesOrderLines",
                columns: new[] { "SalesOrderId", "ItemCode" });

            migrationBuilder.CreateIndex(
                name: "IX_SalesOrders_SourceOrderId",
                table: "SalesOrders",
                column: "SourceOrderId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SalesOrders_SourceSystem_Status_IsArchived",
                table: "SalesOrders",
                columns: new[] { "SourceSystem", "Status", "IsArchived" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AuditLogs");

            migrationBuilder.DropTable(
                name: "Excesses");

            migrationBuilder.DropTable(
                name: "OrderShipmentStatus");

            migrationBuilder.DropTable(
                name: "OrderStatusHistory");

            migrationBuilder.DropTable(
                name: "ProductionLineStates");

            migrationBuilder.DropTable(
                name: "ProductionScanTransactions");

            migrationBuilder.DropTable(
                name: "SalesOrderLines");

            migrationBuilder.DropTable(
                name: "SalesOrders");
        }
    }
}
