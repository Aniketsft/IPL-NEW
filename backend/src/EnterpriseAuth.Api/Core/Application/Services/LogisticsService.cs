using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Core.Application.Services;

public class LogisticsService : ILogisticsService
{
    private readonly ILogisticsRepository _logisticsRepository;

    public LogisticsService(ILogisticsRepository logisticsRepository)
    {
        _logisticsRepository = logisticsRepository;
    }

    public async Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionTrackingAsync(string? siteCode)
    {
        try
        {
            var tracking = await _logisticsRepository.GetProductionTrackingAsync(siteCode);
            return Result<IEnumerable<ProductionTrackingDto>>.Success(tracking);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<ProductionTrackingDto>>.Failure($"Failed to fetch production tracking data: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<SalesOrderHeaderDto>>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1)
    {
        try
        {
            var headers = await _logisticsRepository.GetSalesOrderHeadersAsync(status, date, customerCode, rep0, rep1);
            return Result<IEnumerable<SalesOrderHeaderDto>>.Success(headers);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<SalesOrderHeaderDto>>.Failure($"Failed to fetch sales order headers: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<SalesOrderDetailDto>>> GetSalesOrderDetailsAsync(string soNumber)
    {
        try
        {
            var details = await _logisticsRepository.GetSalesOrderDetailsAsync(soNumber);
            return Result<IEnumerable<SalesOrderDetailDto>>.Success(details);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<SalesOrderDetailDto>>.Failure($"Failed to fetch sales order details: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<CustomerLookupDto>>> GetCustomerLookupAsync()
    {
        try
        {
            var customers = await _logisticsRepository.GetCustomerLookupAsync();
            return Result<IEnumerable<CustomerLookupDto>>.Success(customers);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<CustomerLookupDto>>.Failure($"Failed to fetch customers: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<SalesRepLookupDto>>> GetSalesRepLookupAsync()
    {
        try
        {
            var salesreps = await _logisticsRepository.GetSalesRepLookupAsync();
            return Result<IEnumerable<SalesRepLookupDto>>.Success(salesreps);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<SalesRepLookupDto>>.Failure($"Failed to fetch sales representatives: {ex.Message}");
        }
    }

    public async Task<Result<int>> SyncScansAsync(IEnumerable<ScanDto> scans)
    {
        try
        {
            var count = await _logisticsRepository.SyncScansAsync(scans);
            return Result<int>.Success(count);
        }
        catch (Exception ex)
        {
            return Result<int>.Failure($"Failed to sync scans: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<LocationLookupDto>>> GetLocationLookupsAsync(string site)
    {
        try
        {
            var locations = await _logisticsRepository.GetLocationLookupsAsync(site);
            return Result<IEnumerable<LocationLookupDto>>.Success(locations);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<LocationLookupDto>>.Failure($"Failed to fetch locations: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<BarcodeMappingDto>>> GetBarcodeMappingsAsync(string siteCode)
    {
        try
        {
            var mappings = await _logisticsRepository.GetBarcodeMappingsAsync(siteCode);
            return Result<IEnumerable<BarcodeMappingDto>>.Success(mappings);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<BarcodeMappingDto>>.Failure($"Failed to fetch barcode mappings: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<LocationLookupDto>>> GetTargetLocationsAsync(string site, string itemCode)
    {
        try
        {
            var locations = await _logisticsRepository.GetTargetLocationsAsync(site, itemCode);
            return Result<IEnumerable<LocationLookupDto>>.Success(locations);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<LocationLookupDto>>.Failure($"Failed to fetch target locations: {ex.Message}");
        }
    }

    public async Task<Result<bool>> CloseOrderAsync(string soNumber, string closedBy)
    {
        try
        {
            var result = await _logisticsRepository.CloseOrderAsync(soNumber, closedBy);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to close order: {ex.Message}");
        }
    }
    public async Task<Result<string>> SaveCutBulkAsync(CutBulkEntryDto dto)
    {
        try
        {
            var result = await _logisticsRepository.SaveCutBulkEntryAsync(dto);
            return Result<string>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<string>.Failure($"Failed to save cut/bulk entry: {ex.Message}");
        }
    }

    public async Task<Result<ProductionScanDto>> SaveProductionScanAsync(ProductionScanDto scanDto)
    {
        try
        {
            var result = await _logisticsRepository.SaveProductionScanAsync(scanDto);
            return Result<ProductionScanDto>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<ProductionScanDto>.Failure($"Failed to save production scan: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<string>>> GetProductionSitesAsync()
    {
        try
        {
            var sites = await _logisticsRepository.GetProductionSitesAsync();
            return Result<IEnumerable<string>>.Success(sites);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<string>>.Failure($"Failed to fetch production sites: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<string>>> GetLotsAsync(string itemCode, string siteCode)
    {
        try
        {
            var lots = await _logisticsRepository.GetLotsAsync(itemCode, siteCode);
            return Result<IEnumerable<string>>.Success(lots);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<string>>.Failure($"Failed to fetch lots: {ex.Message}");
        }
    }

    public async Task<Result<bool>> UpdateItemPreparationStatusAsync(string soNumber, string itemCode, bool isPrepared)
    {
        try
        {
            var result = await _logisticsRepository.UpdateItemPreparationStatusAsync(soNumber, itemCode, isPrepared);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to update item preparation status: {ex.Message}");
        }
    }

    public async Task<Result<bool>> UpdateItemValidationStatusAsync(string soNumber, string itemCode, bool isValidated)
    {
        try
        {
            var result = await _logisticsRepository.UpdateItemValidationStatusAsync(soNumber, itemCode, isValidated);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to update item validation status: {ex.Message}");
        }
    }

    public async Task<Result<bool>> BulkUpdateItemStatusAsync(BulkStatusUpdateDto dto)
    {
        try
        {
            var result = await _logisticsRepository.BulkUpdateItemStatusAsync(dto.SoNumber, dto.ItemCodes, dto.Status, dto.IsValidation);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to bulk update item statuses: {ex.Message}");
        }
    }
}
