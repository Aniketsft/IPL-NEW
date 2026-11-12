using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Application.Common;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    /// <summary>
    /// Centralized service to resolve both financial and shipping facility contexts
    /// from user claims, request parameters, and Sage X3 facility mappings.
    /// </summary>
    public interface ISiteContextResolver
    {
        Task<(SiteContext? Context, IActionResult? Error)> ResolveSiteContextAsync(
            ClaimsPrincipal user, 
            string? requestedSiteCode, 
            bool allowAll = false);
    }
}

