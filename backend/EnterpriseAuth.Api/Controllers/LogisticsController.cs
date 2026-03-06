using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using System.Threading.Tasks;
using System;
using System.Collections.Generic;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Common;

namespace EnterpriseAuth.Api.Controllers
{
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
        public async Task<IActionResult> GetProductionTracking()
        {
            var result = await _logisticsService.GetProductionTrackingAsync();
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

        private IActionResult ToActionResult<T>(Result<T> result)
        {
            return result.IsSuccess
                ? Ok(result.Value)
                : StatusCode(500, new { error = result.Error, code = result.ErrorCode });
        }
    }
}
