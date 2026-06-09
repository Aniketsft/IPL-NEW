using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Infrastructure.Persistence;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class RolesController : ControllerBase
    {
        private readonly IRoleRepository _roleRepository;
        private readonly ApplicationDbContext _context;

        public RolesController(IRoleRepository roleRepository, ApplicationDbContext context)
        {
            _roleRepository = roleRepository;
            _context = context;
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
        public async Task<IActionResult> Create([FromBody] RoleDto roleDto)
        {
            var role = new Role
            {
                Id = roleDto.Id != Guid.Empty ? roleDto.Id : Guid.NewGuid(),
                Name = roleDto.Name,
                Description = roleDto.Description,
                Permissions = new List<Permission>()
            };

            if (roleDto.Permissions != null && roleDto.Permissions.Any())
            {
                var names = roleDto.Permissions.Select(p => p.Name.ToLower()).ToList();
                var dbPermissions = await _context.Permissions
                    .Where(p => names.Contains(p.Name.ToLower()))
                    .ToListAsync();
                foreach (var p in dbPermissions)
                {
                    role.Permissions.Add(p);
                }
            }

            await _roleRepository.AddAsync(role);
            return CreatedAtAction(nameof(GetById), new { id = role.Id }, new { id = role.Id, name = role.Name });
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(Guid id, [FromBody] RoleDto roleDto)
        {
            if (id != roleDto.Id) return BadRequest();

            var existingRole = await _roleRepository.GetByIdAsync(id);
            if (existingRole == null) return NotFound();

            existingRole.Name = roleDto.Name;
            existingRole.Description = roleDto.Description;

            // Safe update of permissions collection
            existingRole.Permissions.Clear();
            if (roleDto.Permissions != null && roleDto.Permissions.Any())
            {
                var names = roleDto.Permissions.Select(p => p.Name.ToLower()).ToList();
                var dbPermissions = await _context.Permissions
                    .Where(p => names.Contains(p.Name.ToLower()))
                    .ToListAsync();
                foreach (var p in dbPermissions)
                {
                    existingRole.Permissions.Add(p);
                }
            }

            await _roleRepository.UpdateAsync(existingRole);
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
