using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using Microsoft.AspNetCore.Authorization;
using System.Collections.Generic;

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
        public async Task<ActionResult<SyncPackageDto>> GetRefreshPackage([FromQuery] string site = "IPL")
        {
            var package = await _syncRepository.GetRefreshPackageAsync(site);
            return Ok(package);
        }

        [HttpPost("push")]
        public async Task<ActionResult<int>> PushScans([FromBody] SyncPushRequestDto request)
        {
            if (request == null || request.Scans == null)
            {
                return BadRequest("Invalid sync request");
            }

            int count = await _syncRepository.PushUpdatesAsync(request);
            return Ok(count);
        }
    }
}
