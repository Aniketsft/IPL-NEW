using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using System.Threading.Tasks;
using System;
using System.Collections.Generic;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Common;

namespace EnterpriseAuth.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class LogisticsController : ControllerBase
{
    private readonly ILogisticsService _logisticsService;
    private readonly ISageX3SoapService _x3SoapService;
    private readonly IStagingService _stagingService;

    public LogisticsController(ILogisticsService logisticsService, ISageX3SoapService x3SoapService, IStagingService stagingService)
    {
        _logisticsService = logisticsService;
        _x3SoapService = x3SoapService;
        _stagingService = stagingService;
    }

    [HttpGet("staging-report")]
    public async Task<IActionResult> GetStagingReport([FromQuery] DateTime date)
    {
        var result = await _stagingService.GetStagingReportByDateAsync(date);
        return Ok(result);
    }

    [HttpGet("production-tracking")]
    public async Task<IActionResult> GetProductionTracking([FromQuery] string? siteCode)
    {
        var result = await _logisticsService.GetProductionTrackingAsync(siteCode);
        return ToActionResult(result);
    }

    [HttpGet("production-summary")]
    public async Task<IActionResult> GetProductionSummary([FromQuery] DateTime date)
    {
        var result = await _logisticsService.GetProductionSummaryAsync(date);
        return ToActionResult(result);
    }

    [HttpGet("production-summary/work-order/{workOrder}")]
    public async Task<IActionResult> GetProductionSummaryByWorkOrder(string workOrder)
    {
        var result = await _logisticsService.GetProductionSummaryByWorkOrderAsync(workOrder);
        return ToActionResult(result);
    }

    [HttpPost("complete-eod")]
    public async Task<IActionResult> CompleteEndOfDay([FromBody] CompleteEodRequest request)
    {
        var result = await _logisticsService.CompleteEndOfDayAsync(request.WorkOrder, request.Items);
        return ToActionResult(result);
    }

    [HttpGet("sales-order-headers")]
    public async Task<IActionResult> GetSalesOrderHeaders(
        [FromQuery] int? status, 
        [FromQuery] DateTime? date, 
        [FromQuery] string? customerCode,
        [FromQuery] string? rep0,
        [FromQuery] string? rep1)
    {
        var result = await _logisticsService.GetSalesOrderHeadersAsync(status, date, customerCode, rep0, rep1);
        return ToActionResult(result);
    }

    [HttpGet("sales-order-details/{soNumber}")]
    public async Task<IActionResult> GetSalesOrderDetails(string soNumber)
    {
        var result = await _logisticsService.GetSalesOrderDetailsAsync(soNumber);
        return ToActionResult(result);
    }

    [HttpGet("customers")]
    public async Task<IActionResult> GetCustomers()
    {
        var result = await _logisticsService.GetCustomerLookupAsync();
        return ToActionResult(result);
    }

    [HttpGet("sales-reps")]
    public async Task<IActionResult> GetSalesReps()
    {
        var result = await _logisticsService.GetSalesRepLookupAsync();
        return ToActionResult(result);
    }

    [HttpGet("locations")]
    public async Task<IActionResult> GetLocations([FromQuery] string site = "IPL")
    {
        var result = await _logisticsService.GetLocationLookupsAsync(site);
        return ToActionResult(result);
    }

    [HttpGet("target-locations")]
    public async Task<IActionResult> GetTargetLocations([FromQuery] string site, [FromQuery] string itemCode)
    {
        var result = await _logisticsService.GetTargetLocationsAsync(site, itemCode);
        return ToActionResult(result);
    }

    [HttpGet("barcode-mappings")]
    public async Task<IActionResult> GetBarcodeMappings([FromQuery] string siteCode = "IPL")
    {
        var result = await _logisticsService.GetBarcodeMappingsAsync(siteCode);
        return ToActionResult(result);
    }

    [HttpPost("sync-scans")]
    public async Task<IActionResult> SyncScans([FromBody] List<ScanDto> scans)
    {
        if (scans == null || scans.Count == 0)
        {
            return BadRequest("No scans provided.");
        }

        var result = await _logisticsService.SyncScansAsync(scans);
        return ToActionResult(result);
    }



    [HttpPost("cut-bulk")]
    public async Task<IActionResult> SaveCutBulk([FromBody] CutBulkEntryDto entry)
    {
        if (entry == null) return BadRequest("Entry data is required.");
        var result = await _logisticsService.SaveCutBulkAsync(entry);
        return ToActionResult(result);
    }

    [HttpPost("production-scan")]
    public async Task<IActionResult> SaveProductionScan([FromBody] ProductionScanDto scan)
    {
        var result = await _logisticsService.SaveProductionScanAsync(scan);
        return ToActionResult(result);
    }

    [HttpGet("production-scans/{soNumber}/{itemCode}")]
    public async Task<IActionResult> GetProductionScans(string soNumber, string itemCode)
    {
        var result = await _logisticsService.GetProductionScansAsync(soNumber, itemCode);
        return ToActionResult(result);
    }

    [HttpPost("production-scans/batch")]
    public async Task<IActionResult> SaveProductionScansBatch([FromBody] List<ProductionScanDto> scans)
    {
        var result = await _logisticsService.SaveProductionScansBatchAsync(scans);
        return ToActionResult(result);
    }

    [HttpGet("production-sites")]
    public async Task<IActionResult> GetProductionSites()
    {
        var result = await _logisticsService.GetProductionSitesAsync();
        return ToActionResult(result);
    }

    [HttpGet("lots")]
    public async Task<IActionResult> GetLots([FromQuery] string itemCode, [FromQuery] string siteCode)
    {
        if (string.IsNullOrEmpty(itemCode) || string.IsNullOrEmpty(siteCode))
        {
            return BadRequest("ItemCode and SiteCode are required.");
        }
        var result = await _logisticsService.GetLotsAsync(itemCode, siteCode);
        return ToActionResult(result);
    }

    [HttpPost("close-order/{soNumber}")]
    public async Task<IActionResult> CloseOrder(string soNumber, [FromQuery] string closedBy = "system")
    {
        var result = await _logisticsService.CloseOrderAsync(soNumber, closedBy);
        return ToActionResult(result);
    }

    [HttpPost("update-preparation-status/{soNumber}/{itemCode}")]
    public async Task<IActionResult> UpdatePreparationStatus(string soNumber, string itemCode, [FromQuery] bool isPrepared, [FromQuery] string performedBy = "system")
    {
        var result = await _logisticsService.UpdateItemPreparationStatusAsync(soNumber, itemCode, isPrepared, performedBy: performedBy);
        return ToActionResult(result);
    }

    [HttpPost("update-validation-status/{soNumber}/{itemCode}")]
    public async Task<IActionResult> UpdateValidationStatus(string soNumber, string itemCode, [FromQuery] bool isValidated, [FromQuery] string performedBy = "system")
    {
        var result = await _logisticsService.UpdateItemValidationStatusAsync(soNumber, itemCode, isValidated, performedBy: performedBy);
        return ToActionResult(result);
    }

    [HttpPost("bulk-update-status")]
    public async Task<IActionResult> BulkUpdateStatus([FromBody] BulkStatusUpdateDto dto)
    {
        var result = await _logisticsService.BulkUpdateItemStatusAsync(dto);
        return ToActionResult(result);
    }

    [HttpGet("excess/{deliveryDate}/{itemCode}")]
    public async Task<IActionResult> GetExcess(DateTime deliveryDate, string itemCode)
    {
        var result = await _logisticsService.GetExcessByDateAndItemAsync(deliveryDate, itemCode);
        return ToActionResult(result);
    }

    [HttpPost("allocate-excess")]
    public async Task<IActionResult> AllocateExcess([FromBody] AllocateExcessDto dto)
    {
        var result = await _logisticsService.AllocateExcessAsync(dto);
        return ToActionResult(result);
    }

    [HttpPost("labels/audit")]
    public async Task<IActionResult> LogLabelAudit([FromBody] LabelAuditDto audit)
    {
        var result = await _logisticsService.LogLabelAuditAsync(audit);
        return ToActionResult(result);
    }

    [Authorize]
    [HttpPost("end-of-day")]
    public async Task<IActionResult> ProcessEndOfDay()
    {
        var result = await _x3SoapService.ProcessEndOfDayAsync();
        return Ok(result);
    }

    [Authorize]
    [HttpPost("production-eod")]
    public async Task<IActionResult> ProcessProductionEndOfDay()
    {
        var result = await _x3SoapService.ProcessProductionEodAsync();
        return Ok(result);
    }

    [HttpGet("pending-eod-count")]
    public async Task<IActionResult> GetPendingEodCount()
    {
        var count = await _logisticsService.GetPendingStagingEodCountAsync();
        return Ok(new { pendingCount = count });
    }

    [HttpGet("work-orders")]
    public async Task<IActionResult> GetWorkOrders([FromQuery] string? query)
    {
        var result = await _logisticsService.GetWorkOrdersAsync(query);
        return ToActionResult(result);
    }

    [HttpPost("rollover-order")]
    public async Task<IActionResult> RolloverOrder([FromBody] OrderRolloverDto dto)
    {
        if (dto == null || string.IsNullOrEmpty(dto.SoNumber))
            return BadRequest("Order details are required.");

        var result = await _logisticsService.RolloverOrderAsync(dto, "system");
        return ToActionResult(result);
    }

    [HttpPost("update-eod-exclusion")]
    public async Task<IActionResult> UpdateEodExclusion([FromBody] UpdateEodExclusionRequest request)
    {
        var result = await _logisticsService.UpdateEodExclusionAsync(request);
        return ToActionResult(result);
    }

    [HttpGet("lorries")]
    public async Task<IActionResult> GetLorries()
    {
        var result = await _logisticsService.GetLorriesAsync();
        return ToActionResult(result);
    }

    [HttpPatch("update-target-lorry/{soNumber}")]
    public async Task<IActionResult> UpdateTargetLorry(string soNumber, [FromBody] string lorryValue)
    {
        var result = await _logisticsService.UpdateTargetLorryAsync(soNumber, lorryValue);
        return ToActionResult(result);
    }

    private IActionResult ToActionResult<T>(Result<T> result)
    {
        return result.IsSuccess
            ? Ok(result.Value)
            : StatusCode(500, new { error = result.Error, code = result.ErrorCode });
    }
}

public class CompleteEodRequest
{
    public string WorkOrder { get; set; } = string.Empty;
    public List<ProductionTrackingDto> Items { get; set; } = new();
}
