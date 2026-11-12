using System;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public class SiteContextResolver : ISiteContextResolver
    {
        private readonly ISalesInvoiceRepository _salesInvoiceRepository;
        private readonly ILogger<SiteContextResolver> _logger;

        public SiteContextResolver(
            ISalesInvoiceRepository salesInvoiceRepository,
            ILogger<SiteContextResolver> logger)
        {
            _salesInvoiceRepository = salesInvoiceRepository;
            _logger = logger;
        }

        public async Task<(SiteContext? Context, IActionResult? Error)> ResolveSiteContextAsync(
            ClaimsPrincipal user, 
            string? requestedSiteCode, 
            bool allowAll = false)
        {
            var userSiteCode = user.FindFirst("SiteCode")?.Value?.Trim();
            bool isMultiSiteAdmin = string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase)
                                    || user.IsInRole("Admin")
                                    || user.IsInRole("SuperAdmin");

            string targetSite;

            // Case 1: Standard user bound to a specific site
            if (!string.IsNullOrWhiteSpace(userSiteCode) && !string.Equals(userSiteCode, "ALL", StringComparison.OrdinalIgnoreCase))
            {
                var cleanUserSite = userSiteCode.ToUpperInvariant();
                var expectedFinancialSite = await _salesInvoiceRepository.GetFinancialSiteForSalesSiteAsync(cleanUserSite);

                if (!string.IsNullOrWhiteSpace(requestedSiteCode))
                {
                    var cleanReq = requestedSiteCode.Trim().ToUpperInvariant();
                    // Authorized if requestedSite matches userSiteCode OR its financial facility counterpart
                    if (!string.Equals(cleanReq, cleanUserSite, StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(cleanReq, expectedFinancialSite, StringComparison.OrdinalIgnoreCase))
                    {
                        var userName = user.FindFirst(ClaimTypes.Name)?.Value 
                                       ?? user.FindFirst("username")?.Value 
                                       ?? user.Identity?.Name 
                                       ?? "unknown";
                        _logger.LogWarning("Security: User {User} assigned to {UserSite} attempted to query unauthorized site {RequestedSite}.",
                            userName, cleanUserSite, requestedSiteCode);
                    }
                }

                targetSite = cleanUserSite;
            }
            // Case 2: Multi-site administrator
            else if (isMultiSiteAdmin)
            {
                if (string.IsNullOrWhiteSpace(requestedSiteCode) || string.Equals(requestedSiteCode.Trim(), "ALL", StringComparison.OrdinalIgnoreCase))
                {
                    if (allowAll)
                    {
                        return (new SiteContext
                        {
                            RawSiteCode = "ALL",
                            ShippingSiteCode = string.Empty,
                            FinancialSiteCode = string.Empty,
                            IsMultiSiteAdmin = true,
                            LegalCompany = "INL"
                        }, null);
                    }

                    return (null, new BadRequestObjectResult(new { error = "An explicit sitecode is required to fetch records. 'ALL' is not permitted." }));
                }

                targetSite = requestedSiteCode.Trim().ToUpperInvariant();
            }
            // Case 3: Unassigned / unauthorized user
            else
            {
                var userName = user.FindFirst(ClaimTypes.Name)?.Value 
                               ?? user.FindFirst("username")?.Value 
                               ?? user.Identity?.Name 
                               ?? "unknown";
                _logger.LogWarning("Security: Unassigned user {User} attempted to access site-scoped resource.", userName);
                return (null, new ObjectResult(new { error = "User account is not assigned to a valid site." })
                {
                    StatusCode = StatusCodes.Status403Forbidden
                });
            }

            // Centralized resolution of Financial vs Shipping site codes
            string financialSite = await _salesInvoiceRepository.GetFinancialSiteForSalesSiteAsync(targetSite);
            string shippingSite = targetSite;

            var context = new SiteContext
            {
                RawSiteCode = targetSite,
                ShippingSiteCode = shippingSite,
                FinancialSiteCode = financialSite,
                IsMultiSiteAdmin = isMultiSiteAdmin,
                LegalCompany = "INL"
            };

            return (context, null);
        }
    }
}

