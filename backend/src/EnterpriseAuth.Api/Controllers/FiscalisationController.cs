using System;
using System.Linq;
using System.Security.Claims;
using System.Threading;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Infrastructure.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    [ValidateDeviceLicense]
    public class FiscalisationController : ControllerBase
    {
        private readonly IFiscalisationService _fiscalisationService;
        private readonly ScanProductionDbContext _dbContext;
        private readonly ISageX3SoapService _soapService;

        public FiscalisationController(
            IFiscalisationService fiscalisationService,
            ScanProductionDbContext dbContext,
            ISageX3SoapService soapService)
        {
            _fiscalisationService = fiscalisationService;
            _dbContext = dbContext;
            _soapService = soapService;
        }

        private bool IsAdminUser(string? username)
        {
            return string.Equals(username, "admin", StringComparison.OrdinalIgnoreCase) ||
                   User.HasClaim("permission", "administration.devices.write") ||
                   User.HasClaim(ClaimTypes.Role, "Admin") ||
                   User.HasClaim(ClaimTypes.Role, "SuperAdmin");
        }

        [HttpPost("fiscalise")]
        public async Task<IActionResult> Fiscalise(
            [FromBody] FiscaliseDocumentRequestDto request,
            [FromHeader(Name = "X-Device-Id")] string? headerDeviceId = null,
            CancellationToken cancellationToken = default)
        {
            if (request == null)
            {
                return BadRequest(new FiscaliseResultDto
                {
                    Success = false,
                    StatusMessage = "Request body is required."
                });
            }

            var userName = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value
                           ?? User.Identity?.Name
                           ?? "mobile-user";
            var userSiteCode = User.FindFirst("SiteCode")?.Value;
            var resolvedHeaderDev = !string.IsNullOrWhiteSpace(headerDeviceId)
                ? headerDeviceId
                : User.FindFirst("DeviceId")?.Value;

            var (statusCode, result) = await _fiscalisationService.FiscaliseAsync(
                request,
                resolvedHeaderDev,
                userName,
                userSiteCode,
                cancellationToken);

            return StatusCode(statusCode, result);
        }

        [HttpGet("{documentNo}")]
        public async Task<IActionResult> GetByDocumentNo(string documentNo, CancellationToken cancellationToken = default)
        {
            var record = await _fiscalisationService.GetFiscalInvoiceAsync(documentNo, cancellationToken);
            if (record == null)
            {
                return NotFound(new { success = false, documentNo, message = "Document has not been fiscalised." });
            }

            return Ok(new FiscaliseResultDto
            {
                Success = true,
                DocumentNo = record.DocumentNo,
                IsFiscalised = record.IsFiscalised,
                HepId = record.HepId,
                HepStatus = record.HepStatus,
                StatusMessage = record.HepStatusMessage,
                Irn = record.Irn,
                QrBase64 = record.QrBase64,
                MraStatus = record.MraStatus,
                MraEnvironment = record.MraEnvironment,
                MraRequestId = record.MraRequestId,
                MraResponseId = record.MraResponseId,
                FiscalisedAt = record.FiscalisedAt
            });
        }

        /// <summary>
        /// Troubleshooting: lists fiscalised documents that have not yet synced to Sage X3.
        /// </summary>
        [HttpGet("pending-x3")]
        public async Task<IActionResult> GetPendingX3([FromQuery] int limit = 100, CancellationToken cancellationToken = default)
        {
            var items = await _fiscalisationService.GetPendingX3SyncAsync(limit, cancellationToken);
            return Ok(items.Select(f => new
            {
                f.DocumentNo,
                f.DocumentType,
                f.DocumentCategory,
                f.CustomerCode,
                f.CustomerName,
                f.InvoiceTotal,
                f.TransactionType,
                f.SalesTransactions,
                f.Irn,
                f.HepId,
                f.MraEnvironment,
                f.FiscalisedAt,
                f.DeviceId,
                f.SiteCode,
                f.X3Synced,
                f.X3DocumentId
            }));
        }

        /// <summary>
        /// Troubleshooting: lists recent failed HEP fiscalisation attempts.
        /// </summary>
        [HttpGet("failures")]
        public async Task<IActionResult> GetFailureLogs(
            [FromQuery] string? documentNo = null,
            [FromQuery] int limit = 100,
            CancellationToken cancellationToken = default)
        {
            var logs = await _fiscalisationService.GetFailureLogsAsync(documentNo, limit, cancellationToken);
            return Ok(logs);
        }

        /// <summary>
        /// Troubleshooting: retries Sage X3 SOAP integration for an already-staged fiscalised document.
        /// </summary>
        [HttpPost("retry-x3/{documentNo}")]
        public async Task<IActionResult> RetryX3Sync(string documentNo, CancellationToken cancellationToken = default)
        {
            var username = User.Claims.FirstOrDefault(c => c.Type == "username")?.Value ?? User.Identity?.Name;
            if (!IsAdminUser(username))
            {
                return Forbid();
            }

            var fiscal = await _fiscalisationService.GetFiscalInvoiceAsync(documentNo, cancellationToken);
            if (fiscal == null || !fiscal.IsFiscalised)
            {
                return Conflict(new { success = false, documentNo, error = "Document is not fiscalised in HEP." });
            }

            var staged = await _dbContext.StagingSalesInvoiceHeaders
                .Include(h => h.Lines)
                .FirstOrDefaultAsync(h => h.InvoiceId == documentNo, cancellationToken);

            if (staged == null)
            {
                return NotFound(new { success = false, documentNo, error = "Document is fiscalised but not yet staged from the mobile device. Sync from mobile first." });
            }

            if (staged.IsProcessedByX3 && !string.IsNullOrWhiteSpace(staged.X3DocumentId))
            {
                await _fiscalisationService.MarkX3SyncedAsync(documentNo, staged.X3DocumentId, cancellationToken);
                return Ok(new { success = true, documentNo, x3DocumentId = staged.X3DocumentId, message = "Already synced to Sage X3." });
            }

            bool isCreditOrReturn = string.Equals(fiscal.DocumentType, "CRN", StringComparison.OrdinalIgnoreCase);
            var importRes = isCreditOrReturn
                ? await _soapService.ImportCreditNoteAsync(staged)
                : await _soapService.ImportSalesInvoiceAsync(staged);

            bool ok = importRes.Success || (!string.IsNullOrEmpty(importRes.RawPayload) && importRes.RawPayload.Contains("Creation of ", StringComparison.OrdinalIgnoreCase));
            if (!ok)
            {
                return BadRequest(new
                {
                    success = false,
                    documentNo,
                    error = importRes.TechnicalError ?? string.Join(" | ", importRes.Messages),
                    messages = importRes.Messages
                });
            }

            staged.IsProcessedByX3 = true;
            if (!string.IsNullOrWhiteSpace(importRes.DocumentId))
            {
                staged.X3DocumentId = importRes.DocumentId;
            }
            await _dbContext.SaveChangesAsync(cancellationToken);
            await _fiscalisationService.MarkX3SyncedAsync(documentNo, staged.X3DocumentId, cancellationToken);

            return Ok(new
            {
                success = true,
                documentNo,
                x3DocumentId = staged.X3DocumentId,
                messages = importRes.Messages
            });
        }
    }
}
