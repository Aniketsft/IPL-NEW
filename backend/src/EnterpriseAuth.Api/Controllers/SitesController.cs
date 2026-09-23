using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SitesController : ControllerBase
    {
        private readonly ISitesRepository _sitesRepository;

        public SitesController(ISitesRepository sitesRepository)
        {
            _sitesRepository = sitesRepository;
        }

        [HttpGet]
        public async Task<IActionResult> GetSites()
        {
            var sites = await _sitesRepository.GetSitesAsync();
            return Ok(sites);
        }
    }
}
