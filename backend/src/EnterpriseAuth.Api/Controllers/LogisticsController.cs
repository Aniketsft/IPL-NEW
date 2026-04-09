using Microsoft.AspNetCore.Mvc;
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

    public LogisticsController(ILogisticsService logisticsService)
    {
        _logisticsService = logisticsService;
    }

    [HttpGet("production-tracking")]
    public async Task<IActionResult> GetProductionTracking([FromQuery] string? siteCode)
    {
        var result = await _logisticsService.GetProductionTrackingAsync(siteCode);
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
    public async Task<IActionResult> UpdatePreparationStatus(string soNumber, string itemCode, [FromQuery] bool isPrepared)
    {
        var result = await _logisticsService.UpdateItemPreparationStatusAsync(soNumber, itemCode, isPrepared);
        return ToActionResult(result);
    }

    private IActionResult ToActionResult<T>(Result<T> result)
    {
        return result.IsSuccess
            ? Ok(result.Value)
            : StatusCode(500, new { error = result.Error, code = result.ErrorCode });
    }
}
