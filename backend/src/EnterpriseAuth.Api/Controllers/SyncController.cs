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
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
            {
                site = userSiteCode;
            }
            else if (string.IsNullOrEmpty(site))
            {
                site = userSiteCode ?? "IPL";
            }

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "system-sync";

            if (string.IsNullOrEmpty(deviceId))
            {
                deviceId = Request.Query["deviceId"].FirstOrDefault() 
                           ?? User.FindFirst("DeviceId")?.Value 
                           ?? performedBy;
            }

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

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            // Always lock to user's claimed site
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
            {
                request.Site = userSiteCode;
            }
            else if (string.IsNullOrEmpty(request.Site) && !string.IsNullOrEmpty(userSiteCode))
            {
                request.Site = userSiteCode;
            }

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "system-sync";

            if (string.IsNullOrEmpty(request.DeviceId))
            {
                request.DeviceId = Request.Headers["X-Device-Id"].FirstOrDefault() 
                                   ?? User.FindFirst("DeviceId")?.Value 
                                   ?? performedBy;
            }

            int count = await _syncRepository.PushUpdatesAsync(request, performedBy);
            return Ok(count);
        }

        [HttpGet("devices/latest")]
        public async Task<ActionResult<IEnumerable<DeviceSyncLogDto>>> GetLatestDeviceSyncs([FromQuery] string? site = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            // Strict enforcement: Non-ALL users are locked exclusively to their claimed site.
            string? targetSite = (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
                ? userSiteCode
                : (!string.IsNullOrEmpty(site) && site != "ALL" ? site : null);

            var logs = await _syncRepository.GetLatestDeviceSyncsAsync(targetSite);
            return Ok(logs);
        }

        [HttpPost("log-event")]
        public async Task<ActionResult> LogSyncEvent([FromBody] DeviceSyncEventDto evt)
        {
            if (evt == null)
            {
                return BadRequest("Invalid event payload");
            }

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var effectiveSite = (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
                ? userSiteCode
                : (!string.IsNullOrEmpty(evt.Site) ? evt.Site : "IPL");

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? evt.PerformedBy ?? "system-sync";
            string devId = !string.IsNullOrEmpty(evt.DeviceId) ? evt.DeviceId : performedBy;

            await _syncRepository.LogDeviceSyncAsync(devId, evt.ActionType, effectiveSite, performedBy, evt.Payload);
            return Ok(new { success = true });
        }
    }
}
