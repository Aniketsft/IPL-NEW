using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using Microsoft.AspNetCore.Authorization;
using System.Collections.Generic;
using System.Linq;

namespace EnterpriseAuth.Api.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/[controller]")]
    public class SyncController : ControllerBase
    {
        private readonly ISyncRepository _syncRepository;

        public SyncController(ISyncRepository syncRepository)
        {
            _syncRepository = syncRepository;
        }

        [HttpGet("refresh")]
        public async Task<ActionResult<SyncPackageDto>> GetRefreshPackage(
            [FromQuery] string site = "IPL",
            [FromHeader(Name = "X-Device-Id")] string? deviceId = null)
        {
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "system-sync";
            var package = await _syncRepository.GetRefreshPackageAsync(site, deviceId, performedBy);
            return Ok(package);
        }

        [HttpPost("push")]
        public async Task<ActionResult<int>> PushScans([FromBody] SyncPushRequestDto request)
        {
            if (request == null)
            {
                return BadRequest("Invalid sync request");
            }

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "system-sync";
            int count = await _syncRepository.PushUpdatesAsync(request, performedBy);
            return Ok(count);
        }
        [HttpGet("devices/latest")]
        public async Task<ActionResult<IEnumerable<DeviceSyncLogDto>>> GetLatestDeviceSyncs()
        {
            var logs = await _syncRepository.GetLatestDeviceSyncsAsync();
            return Ok(logs);
        }
    }
}
