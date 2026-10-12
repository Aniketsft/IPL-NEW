using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using System.Threading.Tasks;
using System;
using System.Collections.Generic;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Common;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;

namespace EnterpriseAuth.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class LogisticsController : ControllerBase
{
    private readonly ILogisticsService _logisticsService;
    private readonly ISageX3SoapService _x3SoapService;
    private readonly ILogger<LogisticsController> _logger;

    public LogisticsController(
        ILogisticsService logisticsService, 
        ISageX3SoapService x3SoapService,
        ILogger<LogisticsController> logger)
    {
        _logisticsService = logisticsService;
        _x3SoapService = x3SoapService;
        _logger = logger;
    }

    [HttpGet("production-tracking")]
    public async Task<IActionResult> GetProductionTracking([FromQuery] string? siteCode)
    {
        var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(siteCode);
        if (error != null) return error;
        var result = await _logisticsService.GetProductionTrackingAsync(effectiveSiteCode);
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
    public async Task<IActionResult> GetLocations([FromQuery] string? site = null)
    {
        var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(site);
        if (error != null) return error;
        var result = await _logisticsService.GetLocationLookupsAsync(effectiveSiteCode!);
        return ToActionResult(result);
    }

    [HttpGet("target-locations")]
    public async Task<IActionResult> GetTargetLocations([FromQuery] string? site, [FromQuery] string itemCode)
    {
        var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(site);
        if (error != null) return error;
        var result = await _logisticsService.GetTargetLocationsAsync(effectiveSiteCode!, itemCode);
        return ToActionResult(result);
    }

    [HttpGet("barcode-mappings")]
    public async Task<IActionResult> GetBarcodeMappings([FromQuery] string? siteCode = null)
    {
        var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(siteCode);
        if (error != null) return error;
        var result = await _logisticsService.GetBarcodeMappingsAsync(effectiveSiteCode!);
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
    public async Task<IActionResult> GetLots([FromQuery] string itemCode, [FromQuery] string? siteCode = null)
    {
        if (string.IsNullOrEmpty(itemCode))
        {
            return BadRequest("ItemCode is required.");
        }
        var (effectiveSiteCode, error) = ResolveEffectiveSiteCode(siteCode);
        if (error != null) return error;
        var result = await _logisticsService.GetLotsAsync(itemCode, effectiveSiteCode!);
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

    [HttpGet("work-orders")]
    public async Task<IActionResult> GetWorkOrders([FromQuery] string? query)
    {
        var result = await _logisticsService.GetWorkOrdersAsync(query);
        return ToActionResult(result);
    }

    private (string? EffectiveSiteCode, IActionResult? Error) ResolveEffectiveSiteCode(string? requestedSiteCode)
    {
        var userSiteCode = User.FindFirst("SiteCode")?.Value;
        bool isMultiSiteAdmin = string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase) 
                                || User.IsInRole("Admin") 
                                || User.IsInRole("SuperAdmin");

        // Case 1: Standard user bound to a specific site
        if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
        {
            if (!string.IsNullOrWhiteSpace(requestedSiteCode) && 
                !string.Equals(requestedSiteCode, userSiteCode, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogWarning("Security: User {User} assigned to {UserSite} attempted to query unauthorized site {RequestedSite}.",
                    User.Identity?.Name, userSiteCode, requestedSiteCode);
            }

            return (userSiteCode, null);
        }

        // Case 2: Multi-site administrator
        if (isMultiSiteAdmin)
        {
            var targetSite = !string.IsNullOrWhiteSpace(requestedSiteCode) ? requestedSiteCode : "IPL";
            return (targetSite, null);
        }

        // Case 3: Unassigned / unauthorized user
        _logger.LogWarning("Security: Unassigned user {User} attempted to access site-scoped logistics resource.", User.Identity?.Name);
        return (null, StatusCode(StatusCodes.Status403Forbidden, new { error = "User account is not assigned to a valid site." }));
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
