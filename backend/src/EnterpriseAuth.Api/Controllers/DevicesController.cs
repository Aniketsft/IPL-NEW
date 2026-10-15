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
using EnterpriseAuth.Api.Infrastructure.Persistence;

namespace EnterpriseAuth.Api.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/[controller]")]
    public class DevicesController : ControllerBase
    {
        private readonly ScanProductionDbContext _context;

        public DevicesController(ScanProductionDbContext context)
        {
            _context = context;
        }

        /// <summary>
        /// Get all devices. Filtered by caller's SiteCode unless site is ALL or SuperAdmin.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<DeviceLocationDto>>> GetAll([FromQuery] string? site = null)
        {
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var query = _context.DeviceLocations.AsNoTracking();

            var effectiveSite = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" 
                ? userSiteCode 
                : site;

            if (!string.IsNullOrEmpty(effectiveSite) && effectiveSite != "ALL")
            {
                query = query.Where(d => d.SiteCode == effectiveSite);
            }

            var devices = await query
                .OrderByDescending(d => d.UpdatedAt)
                .Select(d => new DeviceLocationDto
                {
                    DeviceId = d.DeviceId,
                    MacAddress = d.MacAddress,
                    DeviceName = d.DeviceName,
                    SiteCode = d.SiteCode,
                    WarehouseCode = d.WarehouseCode,
                    LocationCode = d.LocationCode,
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
        /// Reads device ID from X-Device-Id header or query parameter.
        /// </summary>
        [HttpGet("my-device")]
        public async Task<ActionResult<DeviceLocationDto>> GetMyDevice(
            [FromHeader(Name = "X-Device-Id")] string? headerDeviceId = null,
            [FromQuery] string? deviceId = null,
            [FromQuery] string? mac = null)
        {
            var targetId = !string.IsNullOrEmpty(deviceId) ? deviceId : headerDeviceId;

            DeviceLocation? device = null;

            if (!string.IsNullOrEmpty(targetId))
            {
                device = await _context.DeviceLocations
                    .AsNoTracking()
                    .FirstOrDefaultAsync(d => d.DeviceId == targetId);
            }

            if (device == null && !string.IsNullOrEmpty(mac))
            {
                device = await _context.DeviceLocations
                    .AsNoTracking()
                    .FirstOrDefaultAsync(d => d.MacAddress == mac);
            }

            if (device == null)
            {
                return NotFound(new { message = "Device is not yet registered or assigned to a location." });
            }

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                MacAddress = device.MacAddress,
                DeviceName = device.DeviceName,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Heartbeat called during login or sync. Auto-registers device if absent,
        /// returns assigned location to immediately map on the mobile client.
        /// </summary>
        [HttpPost("heartbeat")]
        public async Task<ActionResult<DeviceLocationDto>> Heartbeat([FromBody] DeviceHeartbeatRequestDto request)
        {
            if (string.IsNullOrWhiteSpace(request.DeviceId))
            {
                return BadRequest("DeviceId is required.");
            }

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            var site = !string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" 
                ? userSiteCode 
                : (!string.IsNullOrEmpty(request.SiteCode) ? request.SiteCode : "IPL");

            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceId == request.DeviceId);

            if (device == null)
            {
                // Auto-register device
                device = new DeviceLocation
                {
                    DeviceId = request.DeviceId,
                    MacAddress = request.MacAddress,
                    DeviceName = string.IsNullOrWhiteSpace(request.DeviceName) ? request.DeviceId : request.DeviceName,
                    SiteCode = site,
                    WarehouseCode = null,
                    LocationCode = string.Empty, // Pending assignment
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    UpdatedBy = usernameClaim
                };
                _context.DeviceLocations.Add(device);
            }
            else
            {
                // Update heartbeat metadata
                if (!string.IsNullOrEmpty(request.MacAddress) && string.IsNullOrEmpty(device.MacAddress))
                {
                    device.MacAddress = request.MacAddress;
                }
                if (!string.IsNullOrEmpty(request.DeviceName) && device.DeviceName != request.DeviceName)
                {
                    device.DeviceName = request.DeviceName;
                }
                device.UpdatedAt = DateTime.UtcNow;
            }

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                MacAddress = device.MacAddress,
                DeviceName = device.DeviceName,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Assign or update device location, MAC address, and metadata.
        /// </summary>
        [HttpPost("assign")]
        public async Task<ActionResult<DeviceLocationDto>> AssignLocation([FromBody] DeviceLocationDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.DeviceId))
            {
                return BadRequest("DeviceId is required.");
            }

            var usernameClaim = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value 
                               ?? User.Identity?.Name 
                               ?? "SYSTEM";

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL")
            {
                dto.SiteCode = userSiteCode;
            }

            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceId == dto.DeviceId);

            if (device == null)
            {
                device = new DeviceLocation
                {
                    DeviceId = dto.DeviceId,
                    MacAddress = dto.MacAddress,
                    DeviceName = string.IsNullOrWhiteSpace(dto.DeviceName) ? dto.DeviceId : dto.DeviceName,
                    SiteCode = dto.SiteCode,
                    WarehouseCode = dto.WarehouseCode,
                    LocationCode = dto.LocationCode ?? string.Empty,
                    AssignedUserId = dto.AssignedUserId,
                    AssignedUserName = dto.AssignedUserName,
                    IsActive = dto.IsActive,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    UpdatedBy = usernameClaim
                };
                _context.DeviceLocations.Add(device);
            }
            else
            {
                device.MacAddress = dto.MacAddress;
                if (!string.IsNullOrWhiteSpace(dto.DeviceName)) device.DeviceName = dto.DeviceName;
                if (!string.IsNullOrWhiteSpace(dto.SiteCode)) device.SiteCode = dto.SiteCode;
                device.WarehouseCode = dto.WarehouseCode;
                device.LocationCode = dto.LocationCode ?? string.Empty;
                device.AssignedUserId = dto.AssignedUserId;
                device.AssignedUserName = dto.AssignedUserName;
                device.IsActive = dto.IsActive;
                device.UpdatedAt = DateTime.UtcNow;
                device.UpdatedBy = usernameClaim;
            }

            await _context.SaveChangesAsync();

            return Ok(new DeviceLocationDto
            {
                DeviceId = device.DeviceId,
                MacAddress = device.MacAddress,
                DeviceName = device.DeviceName,
                SiteCode = device.SiteCode,
                WarehouseCode = device.WarehouseCode,
                LocationCode = device.LocationCode,
                AssignedUserId = device.AssignedUserId,
                AssignedUserName = device.AssignedUserName,
                IsActive = device.IsActive,
                UpdatedAt = device.UpdatedAt,
                UpdatedBy = device.UpdatedBy
            });
        }

        /// <summary>
        /// Delete a device location mapping.
        /// </summary>
        [HttpDelete("{deviceId}")]
        public async Task<IActionResult> Delete(string deviceId)
        {
            var device = await _context.DeviceLocations.FirstOrDefaultAsync(d => d.DeviceId == deviceId);
            if (device == null) return NotFound();

            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(userSiteCode) && userSiteCode != "ALL" && device.SiteCode != userSiteCode)
            {
                return Forbid();
            }

            _context.DeviceLocations.Remove(device);
            await _context.SaveChangesAsync();
            return NoContent();
        }
    }
}
