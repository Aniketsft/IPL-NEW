using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class RolesController : ControllerBase
    {
        private readonly IRoleRepository _roleRepository;

        public RolesController(IRoleRepository roleRepository)
        {
            _roleRepository = roleRepository;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var roles = await _roleRepository.GetAllAsync();
            var dtos = roles.Select(r => new RoleDto
            {
                Id = r.Id,
                Name = r.Name,
                Description = r.Description,
                Permissions = r.Permissions.Select(p => new PermissionDto
                {
                    Id = p.Id,
                    Name = p.Name,
                    Description = p.Description
                }).ToList()
            });
            return Ok(dtos);
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(Guid id)
        {
            var r = await _roleRepository.GetByIdAsync(id);
            if (r == null) return NotFound();
            
            var dto = new RoleDto
            {
                Id = r.Id,
                Name = r.Name,
                Description = r.Description,
                Permissions = r.Permissions.Select(p => new PermissionDto
                {
                    Id = p.Id,
                    Name = p.Name,
                    Description = p.Description
                }).ToList()
            };
            return Ok(dto);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] Role role)
        {
            await _roleRepository.AddAsync(role);
            // Return only the ID or a flat DTO to avoid loops
            return CreatedAtAction(nameof(GetById), new { id = role.Id }, new { id = role.Id, name = role.Name });
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(Guid id, [FromBody] Role role)
        {
            if (id != role.Id) return BadRequest();
            await _roleRepository.UpdateAsync(role);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(Guid id)
        {
            await _roleRepository.DeleteAsync(id);
            return NoContent();
        }
    }
}
