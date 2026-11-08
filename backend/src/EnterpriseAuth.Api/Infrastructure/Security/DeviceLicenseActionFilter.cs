using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Infrastructure.Persistence;

namespace EnterpriseAuth.Api.Infrastructure.Security
{
    /// <summary>
    /// Action filter attribute to enforce that the calling device has a VALID operational license.
    /// Excludes administrative endpoints (such as DevicesController).
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
    public class ValidateDeviceLicenseAttribute : TypeFilterAttribute
    {
        public ValidateDeviceLicenseAttribute() : base(typeof(DeviceLicenseActionFilter))
        {
        }
    }

    public class DeviceLicenseActionFilter : IAsyncActionFilter
    {
        private readonly ScanProductionDbContext _dbContext;

        public DeviceLicenseActionFilter(ScanProductionDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            // 1. Resolve Device Identifier from X-Device-Id header or query parameter
            var deviceId = context.HttpContext.Request.Headers["X-Device-Id"].FirstOrDefault();
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                deviceId = context.HttpContext.Request.Query["deviceId"].FirstOrDefault();
            }

            if (!string.IsNullOrWhiteSpace(deviceId))
            {
                var cleanId = deviceId.Trim();
                var device = await _dbContext.DeviceLocations.AsNoTracking().FirstOrDefaultAsync(d =>
                    (d.DeviceId == cleanId || d.DeviceName == cleanId || d.HardwareIdentifier == cleanId) && d.IsActive);

                if (device != null && (!device.IsLicensed || !string.Equals(device.LicenseStatus, "VALID", StringComparison.OrdinalIgnoreCase)))
                {
                    context.Result = new ObjectResult(new
                    {
                        statusCode = StatusCodes.Status403Forbidden,
                        error = "DEVICE_LICENSE_SUSPENDED",
                        message = $"Device '{device.DeviceName}' operational license is UNVALIDATED. Access suspended.",
                        deviceId = device.DeviceId,
                        deviceName = device.DeviceName,
                        licenseStatus = device.LicenseStatus
                    })
                    {
                        StatusCode = StatusCodes.Status403Forbidden
                    };
                    return;
                }
            }

            await next();
        }
    }
}

