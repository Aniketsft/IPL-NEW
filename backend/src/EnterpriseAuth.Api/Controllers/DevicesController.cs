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
            if (string.IsNullOrWhiteSpace(request.DeviceName))
            {
                return BadRequest(new { message = "DeviceName is required." });
            }

            if (string.IsNullOrWhiteSpace(request.LocationCode))
            {
                return BadRequest(new { message = "Lorry / LocationCode is required." });
            }

            var cleanName = request.DeviceName.Trim();
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
                SiteCode = effectiveSite,
                WarehouseCode = request.WarehouseCode,
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
        /// Heartbeat called during login or sync. Reconciles licensing and assigned lorry location.
        /// </summary>
        [HttpPost("heartbeat")]
        public async Task<ActionResult<DeviceLocationDto>> Heartbeat(
            [FromBody] DeviceHeartbeatRequestDto request,
            [FromHeader(Name = "X-Device-Id")] string? headerDeviceId = null)
        {
            var targetId = !string.IsNullOrEmpty(request.DeviceId) ? request.DeviceId : headerDeviceId;

            if (string.IsNullOrWhiteSpace(targetId))
            {
                return BadRequest("DeviceId (UUID) is required.");
            }

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            DeviceLocation? device = null;
            if (!string.IsNullOrWhiteSpace(targetId) && Guid.TryParse(targetId, out _))
            {
                device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceId == targetId && d.IsActive);
            }

            // Fallback match by hardware model or device name if client sent unprovisioned/legacy string
            if (device == null && (!string.IsNullOrWhiteSpace(request.HardwareModel) || !string.IsNullOrWhiteSpace(targetId)))
            {
                var queryStr = !string.IsNullOrWhiteSpace(request.HardwareModel) ? request.HardwareModel : targetId!;
                device = await _context.DeviceLocations.FirstOrDefaultAsync(d => 
                    (d.HardwareModel == queryStr || d.DeviceName == queryStr || d.DeviceId == targetId) && d.IsActive);
            }

            if (device == null)
            {
                // Auto-provision tablet with a genuine UUID
                var newUuid = Guid.NewGuid().ToString().ToLowerInvariant();
                var modelName = !string.IsNullOrWhiteSpace(request.HardwareModel) ? request.HardwareModel : (!string.IsNullOrWhiteSpace(targetId) ? targetId : "Tablet-" + newUuid.Substring(0, 8));
                device = new DeviceLocation
                {
                    DeviceId = newUuid,
                    DeviceName = modelName,
                    HardwareModel = request.HardwareModel ?? modelName,
                    SiteCode = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD",
                    LocationCode = "1000",
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
                // Auto-heal legacy non-GUID DeviceId in database
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
            }

            // Auto-heal legacy site code if device was previously set to IPL
            if (device.SiteCode == "IPL" || string.IsNullOrEmpty(device.SiteCode))
            {
                device.SiteCode = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" ? userSiteCode : "POD";
            }

            // Site Isolation Check (non-admin field operators only)
            var isAdminHeartbeat = IsAdminUser(usernameClaim);
            if (!isAdminHeartbeat && !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" && device.SiteCode != userSiteCode)
            {
                return Forbid();
            }

            // Update heartbeat metadata
            if (!string.IsNullOrEmpty(request.HardwareModel) && string.IsNullOrEmpty(device.HardwareModel))
            {
                device.HardwareModel = request.HardwareModel;
            }

            device.AssignedUserName = usernameClaim;
            device.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
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

            device.LocationCode = dto.LocationCode.Trim();
            if (!string.IsNullOrEmpty(dto.WarehouseCode))
            {
                device.WarehouseCode = dto.WarehouseCode.Trim();
            }
            device.UpdatedAt = DateTime.UtcNow;
            device.UpdatedBy = usernameClaim;

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                DeviceName = device.DeviceName,
                HardwareModel = device.HardwareModel,
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
            var effectiveSite = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" 
                ? userSiteCode 
                : (!string.IsNullOrEmpty(site) ? site : "POD");

            try
            {
                var pkg = await _syncRepository.GetRefreshPackageAsync(effectiveSite);
                var locations = pkg.Locations ?? new List<LocationLookupDto>();

                var nonVehicleKeywords = new[] { "DAM", "SCRAP", "RETURN", "REJ", "QUAR", "WASTE" };

                // 1. Filter out known storage / return / damage bays
                var candidateLocations = locations
                    .Where(l => !string.IsNullOrWhiteSpace(l.Location))
                    .Where(l => !nonVehicleKeywords.Any(k => l.Location!.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0))
                    .ToList();

                var lorries = candidateLocations
                    .Select(l =>
                    {
                        var plate = !string.IsNullOrWhiteSpace(l.LocationTypeName) && !nonVehicleKeywords.Any(k => l.LocationTypeName.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0)
                            ? l.LocationTypeName.Trim()
                            : (!string.IsNullOrWhiteSpace(l.WarehouseName) && !nonVehicleKeywords.Any(k => l.WarehouseName.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0) && l.WarehouseName != l.Warehouse && l.WarehouseName != l.Location
                                ? l.WarehouseName.Trim()
                                : null);

                        var desc = !string.IsNullOrWhiteSpace(plate)
                            ? $"{l.Location} • {plate}"
                            : $"{l.Location} ({l.WarehouseName ?? l.Warehouse ?? effectiveSite})";

                        return new LorryLookupDto
                        {
                            Location = l.Location!,
                            PlateNumber = plate,
                            LocationType = l.LocationType,
                            Warehouse = l.Warehouse,
                            WarehouseName = l.WarehouseName,
                            Description = desc
                        };
                    })
                    .OrderBy(l => l.Location)
                    .ToList();

                // Fallback: If no candidate locations found, return unfiltered list
                if (!lorries.Any())
                {
                    lorries = locations
                        .Where(l => !string.IsNullOrWhiteSpace(l.Location))
                        .Select(l => new LorryLookupDto
                        {
                            Location = l.Location!,
                            PlateNumber = l.LocationTypeName,
                            LocationType = l.LocationType,
                            Warehouse = l.Warehouse,
                            WarehouseName = l.WarehouseName,
                            Description = $"{l.Location} ({l.WarehouseName ?? l.Warehouse ?? effectiveSite})"
                        })
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
