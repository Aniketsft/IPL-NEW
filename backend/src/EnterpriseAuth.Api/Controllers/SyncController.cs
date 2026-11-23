using System;
using System.Globalization;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using Microsoft.AspNetCore.Authorization;
using System.Collections.Generic;
using System.Linq;
using EnterpriseAuth.Api.Infrastructure.Security;

namespace EnterpriseAuth.Api.Controllers
{
    [Authorize]
    [ValidateDeviceLicense]
    [ApiController]
    [Route("api/[controller]")]
    public class SyncController : ControllerBase
    {
        private readonly ISyncRepository _syncRepository;
        private readonly ISiteContextResolver _siteResolver;

        public SyncController(
            ISyncRepository syncRepository,
            ISiteContextResolver siteResolver)
        {
            _syncRepository = syncRepository;
            _siteResolver = siteResolver;
        }

        [HttpGet("refresh")]
        public async Task<ActionResult<SyncPackageDto>> GetRefreshPackage(
            [FromQuery] string site = "IPL",
            [FromHeader(Name = "X-Device-Id")] string? deviceId = null)
        {
            var (siteCtx, _) = await _siteResolver.ResolveSiteContextAsync(User, site, allowAll: true);
            var effectiveSite = (siteCtx != null && !string.IsNullOrWhiteSpace(siteCtx.ShippingSiteCode))
                ? siteCtx.ShippingSiteCode
                : (!string.IsNullOrWhiteSpace(site) ? site : "IPL");

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "system-sync";

            if (string.IsNullOrEmpty(deviceId))
            {
                deviceId = Request.Query["deviceId"].FirstOrDefault() 
                           ?? User.FindFirst("DeviceId")?.Value 
                           ?? performedBy;
            }

            var package = await _syncRepository.GetRefreshPackageAsync(effectiveSite, deviceId, performedBy);
            return Ok(package);
        }

        [HttpGet("sales-extras")]
        public async Task<ActionResult<SalesSyncExtrasDto>> GetSalesSyncExtras(
            [FromQuery] string site = "IPL",
            [FromHeader(Name = "X-Device-Id")] string? deviceId = null)
        {
            var (siteCtx, _) = await _siteResolver.ResolveSiteContextAsync(User, site, allowAll: true);
            var effectiveSite = (siteCtx != null && !string.IsNullOrWhiteSpace(siteCtx.ShippingSiteCode))
                ? siteCtx.ShippingSiteCode
                : (!string.IsNullOrWhiteSpace(site) ? site : "IPL");

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "system-sync";

            if (string.IsNullOrEmpty(deviceId))
            {
                deviceId = Request.Query["deviceId"].FirstOrDefault()
                           ?? User.FindFirst("DeviceId")?.Value
                           ?? performedBy;
            }

            var extras = await _syncRepository.GetSalesSyncExtrasAsync(effectiveSite, deviceId, performedBy);
            return Ok(extras);
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

            if (request.GlobalSettingsUpdates != null &&
                request.GlobalSettingsUpdates.Any(u => string.Equals(u.SettingKey, "MaxDiscountPercent", StringComparison.OrdinalIgnoreCase)))
            {
                if (!CanUpdateDiscountLimit())
                {
                    return Forbid();
                }

                foreach (var u in request.GlobalSettingsUpdates.Where(u => string.Equals(u.SettingKey, "MaxDiscountPercent", StringComparison.OrdinalIgnoreCase)))
                {
                    if (!decimal.TryParse(u.SettingValue, NumberStyles.Any, CultureInfo.InvariantCulture, out var pct) || pct < 0m || pct > 100m)
                    {
                        return BadRequest(new { error = "MaxDiscountPercent must be between 0 and 100." });
                    }
                }
            }

            int count = await _syncRepository.PushUpdatesAsync(request, performedBy);
            return Ok(count);
        }

        [HttpGet("global-settings")]
        public async Task<ActionResult<Dictionary<string, string>>> GetGlobalSettings()
        {
            var settings = await _syncRepository.GetGlobalSettingsAsync();
            return Ok(settings);
        }

        [HttpPut("global-settings/discount-limit")]
        public async Task<IActionResult> UpdateDiscountLimit(
            [FromBody] DiscountLimitUpdateDto request,
            [FromHeader(Name = "X-Device-Id")] string? deviceId = null)
        {
            if (!CanUpdateDiscountLimit())
            {
                return Forbid();
            }

            if (request == null || request.MaxDiscountPercent < 0m || request.MaxDiscountPercent > 100m)
            {
                return BadRequest(new { error = "MaxDiscountPercent must be between 0 and 100." });
            }

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value;
            string performedBy = usernameClaim ?? User.Identity?.Name ?? "supervisor";
            string devId = !string.IsNullOrWhiteSpace(deviceId)
                ? deviceId.Trim()
                : (User.FindFirst("DeviceId")?.Value ?? performedBy);

            var formattedValue = request.MaxDiscountPercent.ToString("0.##", CultureInfo.InvariantCulture);
            await _syncRepository.UpsertGlobalSettingAsync("MaxDiscountPercent", formattedValue, performedBy, devId);

            return Ok(new
            {
                success = true,
                settingKey = "MaxDiscountPercent",
                maxDiscountPercent = request.MaxDiscountPercent,
                settingValue = formattedValue,
                updatedBy = performedBy,
                updatedAt = DateTime.UtcNow
            });
        }

        private bool CanUpdateDiscountLimit()
        {
            return User.IsInRole("Admin") ||
                   User.IsInRole("SuperAdmin") ||
                   User.HasClaim("permission", "logistics.sales.discount_limit.update") ||
                   User.HasClaim("permission", "logistics.sales.discount_limit.create") ||
                   User.HasClaim("permission", "admin") ||
                   User.HasClaim("permission", "*");
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

    public class DiscountLimitUpdateDto
    {
        public decimal MaxDiscountPercent { get; set; }
    }
}
