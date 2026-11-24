using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;

namespace EnterpriseAuth.Api.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/[controller]")]
    public class DevicesController : ControllerBase
    {
        private readonly ScanProductionDbContext _context;
        private readonly ISyncRepository _syncRepository;

        public DevicesController(ScanProductionDbContext context, ISyncRepository syncRepository)
        {
            _context = context;
            _syncRepository = syncRepository;
        }

        private bool IsAdminUser(string username)
        {
            return username.Equals("admin", StringComparison.OrdinalIgnoreCase) ||
                   User.HasClaim("permission", "administration.devices.write") ||
                   User.HasClaim(ClaimTypes.Role, "Admin") ||
                   User.HasClaim(ClaimTypes.Role, "SuperAdmin");
        }

        private string MaskApiKey(string? apiKey)
        {
            if (string.IsNullOrEmpty(apiKey)) return string.Empty;
            if (apiKey.Length <= 4) return new string('•', apiKey.Length);
            return new string('•', Math.Min(12, apiKey.Length - 4)) + apiKey.Substring(apiKey.Length - 4);
        }

        private async Task<string> GenerateNextDeviceNameAsync()
        {
            var existingNames = await _context.DeviceLocations
                .Where(d => d.DeviceName.StartsWith("HM"))
                .Select(d => d.DeviceName)
                .ToListAsync();

            int maxIndex = 0;
            foreach (var name in existingNames)
            {
                if (name.Length > 2 && int.TryParse(name.Substring(2), out var idx))
                {
                    if (idx > maxIndex) maxIndex = idx;
                }
            }

            return $"HM{maxIndex + 1}";
        }

        private static bool IsConcreteLorryLocation(string? locationCode, string? siteCode)
        {
            if (string.IsNullOrWhiteSpace(locationCode)) return false;
            var cleanLoc = locationCode.Trim();
            if (!string.IsNullOrWhiteSpace(siteCode) &&
                string.Equals(cleanLoc, siteCode.Trim(), StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
            // Any lorry identifier containing at least one digit (e.g. "57", "L57", "N8") is a concrete vehicle slot
            return cleanLoc.Any(char.IsDigit);
        }

        private async Task<DeviceLocation?> FindConflictingLorryDeviceAsync(string currentDeviceId, string siteCode, string locationCode)
        {
            var cleanLoc = locationCode.Trim().ToLowerInvariant();
            var cleanSite = (siteCode ?? string.Empty).Trim().ToLowerInvariant();
            return await _context.DeviceLocations
                .FirstOrDefaultAsync(d =>
                    d.IsActive &&
                    d.DeviceId != currentDeviceId &&
                    d.SiteCode.ToLower() == cleanSite &&
                    d.LocationCode.ToLower() == cleanLoc);
        }

        /// <summary>
        /// Get next auto-incremented standardized device name (e.g. HM1, HM2).
        /// </summary>
        [HttpGet("next-name")]
        public async Task<ActionResult<object>> GetNextDeviceName()
        {
            var nextName = await GenerateNextDeviceNameAsync();
            return Ok(new { nextDeviceName = nextName });
        }

        /// <summary>
        /// Get all devices. Strictly filtered by caller's SiteCode unless user is SuperAdmin (site == ALL).
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<DeviceLocationDto>>> GetAll([FromQuery] string? site = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var username = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                           ?? User.Identity?.Name 
                           ?? "SYSTEM";
            var isAdmin = IsAdminUser(username);

            var query = _context.DeviceLocations.AsNoTracking().Where(d => d.IsActive);

            // Strict Site-Level Isolation Guardrail:
            // Non-ALL users are hard-locked to their own site.
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
            {
                query = query.Where(d => d.SiteCode == userSiteCode);
            }
            else if (!string.IsNullOrEmpty(site) && site != "ALL")
            {
                query = query.Where(d => d.SiteCode == site);
            }

            var devices = await query
                .OrderByDescending(d => d.UpdatedAt)
                .Select(d => new DeviceLocationDto
                {
                    DeviceId = d.DeviceId,
                    DeviceName = d.DeviceName,
                    HardwareModel = d.HardwareModel,
                    HardwareIdentifier = d.HardwareIdentifier,
                    SiteCode = d.SiteCode,
                    WarehouseCode = d.WarehouseCode,
                    LocationCode = d.LocationCode,
                    HepProfileId = d.HepProfileId,
                    HepApiKey = isAdmin ? d.HepApiKey : (d.HepApiKey != null ? "••••••••" : null),
                    IsLocked = d.IsLocked,
                    IsLicensed = d.IsLicensed,
                    LicenseStatus = d.LicenseStatus,
                    LicenseUpdatedAt = d.LicenseUpdatedAt,
                    LicenseUpdatedBy = d.LicenseUpdatedBy,
                    AssignedUserId = d.AssignedUserId,
                    AssignedUserName = d.AssignedUserName,
                    IsActive = d.IsActive,
                    UpdatedAt = d.UpdatedAt,
                    UpdatedBy = d.UpdatedBy
                })
                .ToListAsync();

            return Ok(devices);
        }

        /// <summary>
        /// Get assigned location for the calling device.
        /// Reads device UUID from X-Device-Id header or query parameter.
        /// </summary>
        [HttpGet("my-device")]
        public async Task<ActionResult<DeviceLocationDto>> GetMyDevice(
            [FromHeader(Name = "X-Device-Id")] string? headerDeviceId = null,
            [FromQuery] string? deviceId = null)
        {
            var targetId = !string.IsNullOrEmpty(deviceId) ? deviceId : headerDeviceId;

            if (string.IsNullOrEmpty(targetId))
            {
                return BadRequest("DeviceId (UUID) is required in header or query parameter.");
            }

            DeviceLocation? device = null;
            if (Guid.TryParse(targetId, out _))
            {
                device = await _context.DeviceLocations
                    .FirstOrDefaultAsync(d => d.DeviceId == targetId && d.IsActive);
            }

            if (device == null)
            {
                device = await _context.DeviceLocations
                    .FirstOrDefaultAsync(d => (d.DeviceId == targetId || d.DeviceName == targetId || d.HardwareModel == targetId) && d.IsActive);
            }

            if (device == null)
            {
                return NotFound(new { message = "Device is not yet registered or assigned to a location." });
            }

            // Auto-heal legacy non-GUID DeviceId
            if (!Guid.TryParse(device.DeviceId, out _))
            {
                var newUuid = Guid.NewGuid().ToString().ToLowerInvariant();
                var oldId = device.DeviceId;
                var model = !string.IsNullOrEmpty(device.HardwareModel) ? device.HardwareModel : device.DeviceName;
                await _context.Database.ExecuteSqlRawAsync(
                    "UPDATE [dbo].[DeviceLocations] SET [DeviceId] = {0}, [HardwareModel] = {1} WHERE [DeviceId] = {2}",
                    newUuid, model, oldId);
                device.DeviceId = newUuid;
                device.HardwareModel = model;
            }

            // Auto-heal legacy device names (e.g. manufacturer models like Infinix) to standardized HM numbering
            if (string.IsNullOrWhiteSpace(device.DeviceName) ||
                device.DeviceName.Contains("Infinix", StringComparison.OrdinalIgnoreCase) ||
                device.DeviceName.Contains("Android", StringComparison.OrdinalIgnoreCase) ||
                device.DeviceName.Contains("Samsung", StringComparison.OrdinalIgnoreCase) ||
                device.DeviceName.Contains("Unknown", StringComparison.OrdinalIgnoreCase) ||
                !device.DeviceName.StartsWith("HM", StringComparison.OrdinalIgnoreCase))
            {
                var standardName = await GenerateNextDeviceNameAsync();
                device.DeviceName = standardName;
                await _context.SaveChangesAsync();
            }

            var username = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                           ?? User.Identity?.Name 
                           ?? "SYSTEM";
            var isAdmin = IsAdminUser(username);

            // Site Isolation Check (Auto-heal legacy IPL to caller's site or allow admin)
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (device.SiteCode == "IPL" && !string.IsNullOrEmpty(userSiteCode))
            {
                device.SiteCode = userSiteCode;
                await _context.SaveChangesAsync();
            }
            else if (!isAdmin && !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" && device.SiteCode != userSiteCode)
            {
                return Forbid();
            }

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
                HardwareIdentifier = device.HardwareIdentifier,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                HepProfileId = device.HepProfileId,
                HepApiKey = isAdmin ? device.HepApiKey : MaskApiKey(device.HepApiKey),
                IsLocked = device.IsLocked,
                IsLicensed = device.IsLicensed,
                LicenseStatus = device.LicenseStatus,
                LicenseUpdatedAt = device.LicenseUpdatedAt,
                LicenseUpdatedBy = device.LicenseUpdatedBy,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Provision a new device: assigns a backend-generated UUID, verifies uniqueness of DeviceName,
        /// and records the tablet in the MSSQL table.
        /// </summary>
        [HttpPost("provision")]
        public async Task<ActionResult<DeviceLocationDto>> Provision([FromBody] DeviceProvisionRequestDto request)
        {
            if (string.IsNullOrWhiteSpace(request.LocationCode))
            {
                return BadRequest(new { message = "Lorry / LocationCode is required." });
            }

            var isHardwareName = string.IsNullOrWhiteSpace(request.DeviceName) ||
                                 request.DeviceName.Trim().Equals("AUTO", StringComparison.OrdinalIgnoreCase) ||
                                 request.DeviceName.Contains("Infinix", StringComparison.OrdinalIgnoreCase) ||
                                 request.DeviceName.Contains("Android", StringComparison.OrdinalIgnoreCase) ||
                                 request.DeviceName.Contains("Samsung", StringComparison.OrdinalIgnoreCase) ||
                                 request.DeviceName.Contains("Unknown", StringComparison.OrdinalIgnoreCase) ||
                                 request.DeviceName.StartsWith("Platform:", StringComparison.OrdinalIgnoreCase);

            var cleanName = isHardwareName
                ? await GenerateNextDeviceNameAsync()
                : request.DeviceName.Trim();
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var username = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                           ?? User.Identity?.Name 
                           ?? "SYSTEM";

            // Guardrail 1: Enforce Site Tenancy Isolation
            var effectiveSite = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" 
                ? userSiteCode 
                : (!string.IsNullOrEmpty(request.SiteCode) ? request.SiteCode : "POD");

            // Guardrail 2: Enforce Global Device Name Uniqueness (Case-Insensitive)
            var nameExists = await _context.DeviceLocations.AnyAsync(d => 
                d.DeviceName.ToLower() == cleanName.ToLower() && d.IsActive);

            if (nameExists)
            {
                return Conflict(new { message = $"Device name '{cleanName}' is already assigned to another tablet. Please enter a unique name." });
            }

            // Guardrail 3 (Option A): Enforce 1 active device per concrete lorry location
            var cleanLoc = request.LocationCode.Trim();
            if (IsConcreteLorryLocation(cleanLoc, effectiveSite))
            {
                var lorryConflict = await FindConflictingLorryDeviceAsync(string.Empty, effectiveSite, cleanLoc);
                if (lorryConflict != null)
                {
                    return Conflict(new { message = $"Lorry '{cleanLoc}' is already assigned to active device '{lorryConflict.DeviceName}'. Release or reassign '{lorryConflict.DeviceName}' first to prevent duplicate document numbers." });
                }
            }

            // Generate Backend UUID
            var newUuid = Guid.NewGuid().ToString();

            Guid? assignedUserId = null;
            var subClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? User.FindFirst("sub")?.Value;
            if (Guid.TryParse(subClaim, out var parsedId))
            {
                assignedUserId = parsedId;
            }

            var device = new DeviceLocation
            {
                DeviceId = newUuid,
                DeviceName = cleanName,
                HardwareModel = request.HardwareModel,
                HardwareIdentifier = request.HardwareIdentifier,
                SiteCode = effectiveSite,
                WarehouseCode = !string.IsNullOrEmpty(request.WarehouseCode) ? request.WarehouseCode : request.LocationCode,
                LocationCode = request.LocationCode,
                HepProfileId = request.HepProfileId,
                HepApiKey = request.HepApiKey,
                IsLocked = true,
                IsLicensed = true,
                LicenseStatus = "VALID",
                LicenseUpdatedAt = DateTime.UtcNow,
                LicenseUpdatedBy = username,
                AssignedUserId = assignedUserId,
                AssignedUserName = username,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
                UpdatedBy = username
            };

            _context.DeviceLocations.Add(device);
            await _context.SaveChangesAsync();

            return CreatedAtAction(nameof(GetMyDevice), new { deviceId = device.DeviceId }, new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
                HardwareIdentifier = device.HardwareIdentifier,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                HepProfileId = device.HepProfileId,
                HepApiKey = MaskApiKey(device.HepApiKey),
                IsLocked = device.IsLocked,
                IsLicensed = device.IsLicensed,
                LicenseStatus = device.LicenseStatus,
                LicenseUpdatedAt = device.LicenseUpdatedAt,
                LicenseUpdatedBy = device.LicenseUpdatedBy,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Heartbeat called during login or sync. Reconciles licensing, assigned lorry location,
        /// dynamic site tenancy, and auto-provisions HM1, HM2, ... sequentially for new devices.
        /// </summary>
        [HttpPost("heartbeat")]
        public async Task<ActionResult<DeviceLocationDto>> Heartbeat(
            [FromBody] DeviceHeartbeatRequestDto request,
            [FromHeader(Name = "X-Device-Id")] string? headerDeviceId = null,
            [FromHeader(Name = "X-Device-Hardware-Id")] string? headerHardwareId = null)
        {
            var targetId = !string.IsNullOrEmpty(request.DeviceId) ? request.DeviceId.Trim() : headerDeviceId?.Trim();
            var incomingHwId = !string.IsNullOrWhiteSpace(request.HardwareIdentifier)
                ? request.HardwareIdentifier.Trim()
                : headerHardwareId?.Trim();

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            // Concrete explicit site from incoming request or user's login claim (null when 'ALL' / unspecified)
            string? requestedSite = !string.IsNullOrWhiteSpace(request.SiteCode) && !string.Equals(request.SiteCode.Trim(), "ALL", StringComparison.OrdinalIgnoreCase)
                ? request.SiteCode.Trim().ToUpperInvariant()
                : (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode.Trim(), "ALL", StringComparison.OrdinalIgnoreCase)
                    ? userSiteCode.Trim().ToUpperInvariant()
                    : null);
            var effectiveSite = requestedSite ?? "POD";

            DeviceLocation? device = null;

            // 1. Primary lookup by genuine UUID if client provided one
            if (!string.IsNullOrWhiteSpace(targetId) && Guid.TryParse(targetId, out _))
            {
                device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceId == targetId && d.IsActive);
            }

            // 2. Secondary lookup by unique physical HardwareIdentifier (e.g. ANDROID_ID) - survives app delete & reinstall
            if (device == null && !string.IsNullOrWhiteSpace(incomingHwId))
            {
                device = await _context.DeviceLocations
                    .Where(d => d.HardwareIdentifier == incomingHwId && d.IsActive)
                    .OrderByDescending(d => d.UpdatedAt)
                    .FirstOrDefaultAsync();
            }

            // 3. Tertiary fallback lookup by DeviceName if valid HM pattern
            if (device == null && !string.IsNullOrWhiteSpace(request.DeviceName) && 
                System.Text.RegularExpressions.Regex.IsMatch(request.DeviceName.Trim(), @"^HM\d+$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            {
                var cleanName = request.DeviceName.Trim();
                device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceName.ToLower() == cleanName.ToLower() && d.IsActive);
            }

            if (device == null)
            {
                // BRAND NEW PHYSICAL DEVICE:
                // Auto-provision tablet with a genuine UUID and next sequential standardized HM numbering (HM1, HM2, ...)
                var newUuid = Guid.NewGuid().ToString().ToLowerInvariant();
                var standardDeviceName = await GenerateNextDeviceNameAsync();
                var hwModel = !string.IsNullOrWhiteSpace(request.HardwareModel) ? request.HardwareModel.Trim() : standardDeviceName;

                device = new DeviceLocation
                {
                    DeviceId = newUuid,
                    DeviceName = standardDeviceName,
                    HardwareModel = hwModel,
                    HardwareIdentifier = !string.IsNullOrWhiteSpace(incomingHwId) ? incomingHwId : null,
                    SiteCode = effectiveSite,
                    WarehouseCode = effectiveSite,
                    LocationCode = effectiveSite,
                    IsLocked = true,
                    IsLicensed = true,
                    LicenseStatus = "VALID",
                    LicenseUpdatedAt = DateTime.UtcNow,
                    LicenseUpdatedBy = usernameClaim,
                    AssignedUserName = usernameClaim,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    UpdatedBy = usernameClaim
                };

                _context.DeviceLocations.Add(device);
                await _context.SaveChangesAsync();
            }
            else
            {
                // EXISTING DEVICE:
                // 1. Auto-heal legacy non-GUID DeviceId in database if present
                if (!Guid.TryParse(device.DeviceId, out _))
                {
                    var newUuid = Guid.NewGuid().ToString().ToLowerInvariant();
                    var oldId = device.DeviceId;
                    var model = !string.IsNullOrEmpty(device.HardwareModel) ? device.HardwareModel : device.DeviceName;
                    await _context.Database.ExecuteSqlRawAsync(
                        "UPDATE [dbo].[DeviceLocations] SET [DeviceId] = {0}, [HardwareModel] = {1} WHERE [DeviceId] = {2}",
                        newUuid, model, oldId);
                    device.DeviceId = newUuid;
                    device.HardwareModel = model;
                }

                // 2. Auto-heal legacy device names to standardized HM numbering
                if (string.IsNullOrWhiteSpace(device.DeviceName) ||
                    device.DeviceName.Contains("Infinix", StringComparison.OrdinalIgnoreCase) ||
                    device.DeviceName.Contains("Android", StringComparison.OrdinalIgnoreCase) ||
                    device.DeviceName.Contains("Samsung", StringComparison.OrdinalIgnoreCase) ||
                    device.DeviceName.Contains("Unknown", StringComparison.OrdinalIgnoreCase) ||
                    !device.DeviceName.StartsWith("HM", StringComparison.OrdinalIgnoreCase))
                {
                    var standardName = await GenerateNextDeviceNameAsync();
                    device.DeviceName = standardName;
                }

                // 3. Update HardwareIdentifier if missing on server
                if (!string.IsNullOrWhiteSpace(incomingHwId) && string.IsNullOrWhiteSpace(device.HardwareIdentifier))
                {
                    device.HardwareIdentifier = incomingHwId;
                }

                // 4. Update HardwareModel if incoming is detailed
                if (!string.IsNullOrWhiteSpace(request.HardwareModel))
                {
                    device.HardwareModel = request.HardwareModel.Trim();
                }

                // 5. Dynamic Site Code Synchronization on User Login (preserve existing site when admin/caller sends ALL or empty)
                if (!string.IsNullOrEmpty(requestedSite) && !string.Equals(device.SiteCode, requestedSite, StringComparison.OrdinalIgnoreCase))
                {
                    device.SiteCode = requestedSite;
                }
                else if (string.IsNullOrWhiteSpace(device.SiteCode) || string.Equals(device.SiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
                {
                    device.SiteCode = effectiveSite;
                }

                // 6. Ensure LocationCode and WarehouseCode are populated and aligned
                if (string.IsNullOrEmpty(device.WarehouseCode) && !string.IsNullOrEmpty(device.LocationCode))
                {
                    device.WarehouseCode = device.LocationCode;
                }

                device.AssignedUserName = usernameClaim;
                device.UpdatedAt = DateTime.UtcNow;
                await _context.SaveChangesAsync();
            }

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
                HardwareIdentifier = device.HardwareIdentifier,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                HepProfileId = device.HepProfileId,
                HepApiKey = MaskApiKey(device.HepApiKey),
                IsLocked = device.IsLocked,
                IsLicensed = device.IsLicensed,
                LicenseStatus = device.LicenseStatus,
                LicenseUpdatedAt = device.LicenseUpdatedAt,
                LicenseUpdatedBy = device.LicenseUpdatedBy,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Field Operator / Driver Lorry Switch:
        /// Standard authenticated users can change ONLY the LocationCode (Lorry) and WarehouseCode.
        /// </summary>
        [HttpPut("{deviceId}/location")]
        public async Task<ActionResult<DeviceLocationDto>> UpdateLocation(
            string deviceId, 
            [FromBody] DeviceLocationUpdateRequestDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.LocationCode))
            {
                return BadRequest("LocationCode (Lorry) is required.");
            }

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => 
                (d.DeviceId == deviceId || d.DeviceName == deviceId || d.HardwareModel == deviceId) && d.IsActive);
            if (device == null) return NotFound(new { message = "Device not found." });

            // Strict Site Isolation Guardrail:
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" && device.SiteCode != userSiteCode)
            {
                return Forbid();
            }

            var cleanLoc = dto.LocationCode.Trim();
            if (IsConcreteLorryLocation(cleanLoc, device.SiteCode))
            {
                var lorryConflict = await FindConflictingLorryDeviceAsync(device.DeviceId, device.SiteCode, cleanLoc);
                if (lorryConflict != null)
                {
                    if (dto.ForceReassign && IsAdminUser(usernameClaim))
                    {
                        lorryConflict.LocationCode = lorryConflict.SiteCode;
                        lorryConflict.WarehouseCode = lorryConflict.SiteCode;
                        lorryConflict.UpdatedAt = DateTime.UtcNow;
                        lorryConflict.UpdatedBy = usernameClaim;
                    }
                    else
                    {
                        return Conflict(new { message = $"Lorry '{cleanLoc}' is already assigned to active device '{lorryConflict.DeviceName}'. Release or reassign '{lorryConflict.DeviceName}' first to prevent duplicate document numbers." });
                    }
                }
            }

            device.LocationCode = cleanLoc;
            if (!string.IsNullOrEmpty(dto.WarehouseCode))
            {
                device.WarehouseCode = dto.WarehouseCode.Trim();
            }
            else
            {
                device.WarehouseCode = cleanLoc;
            }
            device.UpdatedAt = DateTime.UtcNow;
            device.UpdatedBy = usernameClaim;

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
                HardwareIdentifier = device.HardwareIdentifier,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                HepProfileId = device.HepProfileId,
                HepApiKey = MaskApiKey(device.HepApiKey),
                IsLocked = device.IsLocked,
                IsLicensed = device.IsLicensed,
                LicenseStatus = device.LicenseStatus,
                LicenseUpdatedAt = device.LicenseUpdatedAt,
                LicenseUpdatedBy = device.LicenseUpdatedBy,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Admin Configuration:
        /// Exclusively for Admin users. Allows updating DeviceName (with uniqueness verification),
        /// HEP Profile ID, HEP API Key, and lock state.
        /// </summary>
        [HttpPut("{deviceId}/admin-config")]
        public async Task<ActionResult<DeviceLocationDto>> UpdateAdminConfig(
            string deviceId, 
            [FromBody] DeviceAdminConfigRequestDto dto)
        {
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            if (!IsAdminUser(usernameClaim))
            {
                return Forbid();
            }

            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => 
                (d.DeviceId == deviceId || d.DeviceName == deviceId || d.HardwareModel == deviceId) && d.IsActive);
            if (device == null) return NotFound(new { message = "Device not found." });

            // Update SiteCode if provided or auto-heal legacy IPL to caller's site
            if (!string.IsNullOrWhiteSpace(dto.SiteCode))
            {
                device.SiteCode = dto.SiteCode.Trim();
            }
            else if (device.SiteCode == "IPL" || string.IsNullOrEmpty(device.SiteCode))
            {
                var callerSite = User.FindFirst("SiteCode")?.Value;
                device.SiteCode = !string.IsNullOrEmpty(callerSite) && callerSite != "ALL" ? callerSite : "POD";
            }

            // Check DeviceName uniqueness if changing
            if (!string.IsNullOrWhiteSpace(dto.DeviceName) && 
                !dto.DeviceName.Trim().Equals(device.DeviceName, StringComparison.OrdinalIgnoreCase))
            {
                var cleanName = dto.DeviceName.Trim();
                var exists = await _context.DeviceLocations.AnyAsync(d => 
                    d.DeviceId != deviceId && d.DeviceName.ToLower() == cleanName.ToLower() && d.IsActive);

                if (exists)
                {
                    return Conflict(new { message = $"Device name '{cleanName}' is already taken. Please choose another name." });
                }
                device.DeviceName = cleanName;
            }

            if (!string.IsNullOrWhiteSpace(dto.LocationCode))
            {
                var cleanLoc = dto.LocationCode.Trim();
                if (IsConcreteLorryLocation(cleanLoc, device.SiteCode))
                {
                    var lorryConflict = await FindConflictingLorryDeviceAsync(device.DeviceId, device.SiteCode, cleanLoc);
                    if (lorryConflict != null)
                    {
                        if (dto.ForceReassign)
                        {
                            lorryConflict.LocationCode = lorryConflict.SiteCode;
                            lorryConflict.WarehouseCode = lorryConflict.SiteCode;
                            lorryConflict.UpdatedAt = DateTime.UtcNow;
                            lorryConflict.UpdatedBy = usernameClaim;
                        }
                        else
                        {
                            return Conflict(new { message = $"Lorry '{cleanLoc}' is already assigned to active device '{lorryConflict.DeviceName}'. Release or reassign '{lorryConflict.DeviceName}' first to prevent duplicate document numbers." });
                        }
                    }
                }
                device.LocationCode = cleanLoc;
                device.WarehouseCode = !string.IsNullOrWhiteSpace(dto.WarehouseCode) ? dto.WarehouseCode.Trim() : cleanLoc;
            }
            else if (!string.IsNullOrWhiteSpace(dto.WarehouseCode))
            {
                device.WarehouseCode = dto.WarehouseCode.Trim();
            }

            if (dto.HepProfileId != null) device.HepProfileId = dto.HepProfileId.Trim();
            if (dto.HepApiKey != null) device.HepApiKey = dto.HepApiKey.Trim();
            if (dto.IsLocked.HasValue) device.IsLocked = dto.IsLocked.Value;

            device.UpdatedAt = DateTime.UtcNow;
            device.UpdatedBy = usernameClaim;

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
                HardwareIdentifier = device.HardwareIdentifier,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                HepProfileId = device.HepProfileId,
                HepApiKey = device.HepApiKey,
                IsLocked = device.IsLocked,
                IsLicensed = device.IsLicensed,
                LicenseStatus = device.LicenseStatus,
                LicenseUpdatedAt = device.LicenseUpdatedAt,
                LicenseUpdatedBy = device.LicenseUpdatedBy,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Admin License Validation Toggle:
        /// Allows administrator to toggle device license between VALID and UNVALIDATED.
        /// </summary>
        [HttpPost("{deviceId}/toggle-license")]
        public async Task<ActionResult<DeviceLocationDto>> ToggleLicense(
            string deviceId, 
            [FromBody] DeviceLicenseToggleDto dto)
        {
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            if (!IsAdminUser(usernameClaim))
            {
                return Forbid();
            }

            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => 
                (d.DeviceId == deviceId || d.DeviceName == deviceId || d.HardwareModel == deviceId) && d.IsActive);
            if (device == null) return NotFound(new { message = "Device not found." });

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" && device.SiteCode != userSiteCode)
            {
                return Forbid();
            }

            device.IsLicensed = dto.IsLicensed;
            device.LicenseStatus = dto.IsLicensed ? "VALID" : "UNVALIDATED";
            device.LicenseUpdatedAt = DateTime.UtcNow;
            device.LicenseUpdatedBy = usernameClaim;
            device.UpdatedAt = DateTime.UtcNow;
            device.UpdatedBy = usernameClaim;

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
                HardwareIdentifier = device.HardwareIdentifier,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                HepProfileId = device.HepProfileId,
                HepApiKey = MaskApiKey(device.HepApiKey),
                IsLocked = device.IsLocked,
                IsLicensed = device.IsLicensed,
                LicenseStatus = device.LicenseStatus,
                LicenseUpdatedAt = device.LicenseUpdatedAt,
                LicenseUpdatedBy = device.LicenseUpdatedBy,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Query Lorries/Vans strictly for the caller's Site.
        /// </summary>
        [HttpGet("site-lorries")]
        [AllowAnonymous]
        public async Task<ActionResult<IEnumerable<LorryLookupDto>>> GetSiteLorries([FromQuery] string? site = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var rawSite = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" 
                ? userSiteCode 
                : (!string.IsNullOrEmpty(site) ? site : "POD");
            var effectiveSite = rawSite.Trim().ToUpperInvariant();

            try
            {
                var locations = (await _syncRepository.GetSiteLocationsAsync(effectiveSite))?.ToList()
                                ?? new List<LocationLookupDto>();

                var nonVehicleKeywords = new[] { "DAM", "SCRAP", "RETURN", "REJ", "QUAR", "WASTE" };

                LorryLookupDto MapLorryDto(LocationLookupDto l, bool filterPlateKeywords)
                {
                    var cleanLoc = l.Location!.Trim();
                    var cleanTypeName = l.LocationTypeName?.Trim();
                    var cleanWrh = l.Warehouse?.Trim();
                    var cleanWrhName = l.WarehouseName?.Trim();

                    var plate = filterPlateKeywords
                        ? (!string.IsNullOrWhiteSpace(cleanTypeName) && !nonVehicleKeywords.Any(k => cleanTypeName.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0)
                            ? cleanTypeName
                            : (!string.IsNullOrWhiteSpace(cleanWrhName) && !nonVehicleKeywords.Any(k => cleanWrhName.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0) && cleanWrhName != cleanWrh && cleanWrhName != cleanLoc
                                ? cleanWrhName
                                : null))
                        : cleanTypeName;

                    var desc = filterPlateKeywords && !string.IsNullOrWhiteSpace(plate)
                        ? $"{cleanLoc} • {plate}"
                        : $"{cleanLoc} ({cleanWrhName ?? cleanWrh ?? effectiveSite})";

                    return new LorryLookupDto
                    {
                        Site = !string.IsNullOrWhiteSpace(l.Site) ? l.Site.Trim().ToUpperInvariant() : effectiveSite,
                        Location = cleanLoc,
                        PlateNumber = plate,
                        LocationType = l.LocationType?.Trim(),
                        Warehouse = cleanWrh,
                        WarehouseName = cleanWrhName,
                        Description = desc
                    };
                }

                // 1. Filter out known storage / return / damage bays (keeps operational locations such as WEB)
                var candidateLocations = locations
                    .Where(l => !string.IsNullOrWhiteSpace(l.Location))
                    .Where(l => !nonVehicleKeywords.Any(k => l.Location!.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0))
                    .ToList();

                var lorries = candidateLocations
                    .Select(l => MapLorryDto(l, filterPlateKeywords: true))
                    .OrderBy(l => l.Location)
                    .ToList();

                // Fallback: If no candidate locations found, return unfiltered list
                if (!lorries.Any())
                {
                    lorries = locations
                        .Where(l => !string.IsNullOrWhiteSpace(l.Location))
                        .Select(l => MapLorryDto(l, filterPlateKeywords: false))
                        .OrderBy(l => l.Location)
                        .ToList();
                }

                return Ok(lorries);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = $"Error querying site lorries: {ex.Message}" });
            }
        }

        /// <summary>
        /// Soft delete a device mapping. Admin only + site isolation check.
        /// </summary>
        [HttpDelete("{deviceId}")]
        public async Task<IActionResult> Delete(string deviceId)
        {
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            if (!IsAdminUser(usernameClaim))
            {
                return Forbid();
            }

            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceId == deviceId);
            if (device == null) return NotFound();

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" && device.SiteCode != userSiteCode)
            {
                return Forbid();
            }

            device.IsActive = false;
            device.UpdatedAt = DateTime.UtcNow;
            device.UpdatedBy = usernameClaim;
            await _context.SaveChangesAsync();

            return NoContent();
        }
    }
}
