using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;

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
            var currentUserSiteCode = User.FindFirst("SiteCode")?.Value;
            
            var roles = await _roleRepository.GetAllAsync();
            
            if (!string.IsNullOrEmpty(currentUserSiteCode))
            {
                roles = roles.Where(r => r.SiteCode == currentUserSiteCode);
            }
            var dtos = roles.Select(r => new RoleDto
            {
                Id = r.Id,
                Name = r.Name,
                Description = r.Description,
                SiteCode = r.SiteCode,
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
            
            var currentUserSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(currentUserSiteCode) && r.SiteCode != currentUserSiteCode)
            {
                return Forbid();
            }
            
            var dto = new RoleDto
            {
                Id = r.Id,
                Name = r.Name,
                Description = r.Description,
                SiteCode = r.SiteCode,
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
            var callerUsername = User.FindFirst("username")?.Value 
                ?? User.FindFirst(ClaimTypes.Name)?.Value 
                ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            bool isSuperAdmin = string.Equals(callerUsername, "admin", StringComparison.OrdinalIgnoreCase);

            var currentUserSiteCode = User.FindFirst("SiteCode")?.Value;
            var assignedSiteCode = isSuperAdmin ? roleDto.SiteCode : currentUserSiteCode;

            var role = new Role
            {
                Id = roleDto.Id != Guid.Empty ? roleDto.Id : Guid.NewGuid(),
                Name = roleDto.Name,
                Description = roleDto.Description,
                SiteCode = assignedSiteCode,
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

            var currentUserSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(currentUserSiteCode) && existingRole.SiteCode != currentUserSiteCode)
            {
                return Forbid();
            }

            existingRole.Name = roleDto.Name;
            existingRole.Description = roleDto.Description;
            
            if (string.IsNullOrEmpty(currentUserSiteCode))
            {
                existingRole.SiteCode = roleDto.SiteCode;
            }

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
            var existingRole = await _roleRepository.GetByIdAsync(id);
            if (existingRole == null) return NotFound();

            var currentUserSiteCode = User.FindFirst("SiteCode")?.Value;
            if (!string.IsNullOrEmpty(currentUserSiteCode) && existingRole.SiteCode != currentUserSiteCode)
            {
                return Forbid();
            }

            await _roleRepository.DeleteAsync(id);
            return NoContent();
        }
    }
}
