using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Infrastructure.Persistence;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UsersController : ControllerBase
    {
        private readonly IUserRepository _userRepository;
        private readonly IPasswordHasher _passwordHasher;
        private readonly ApplicationDbContext _context;

        public UsersController(IUserRepository userRepository, IPasswordHasher passwordHasher, ApplicationDbContext context)
        {
            _userRepository = userRepository;
            _passwordHasher = passwordHasher;
            _context = context;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var users = await _userRepository.GetAllAsync();
            var dtos = users.Select(u => new UserDto
            {
                Id = u.Id,
                Username = u.Username,
                Email = u.Email,
                IsActive = u.IsActive,
                UserGroupId = u.UserGroupId,
                Permissions = u.Roles.SelectMany(r => r.Permissions).Select(p => p.Name).ToList()
            });
            return Ok(dtos);
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(Guid id)
        {
            var user = await _userRepository.GetByIdAsync(id);
            if (user == null) return NotFound();
            
            var dto = new UserDto
            {
                Id = user.Id,
                Username = user.Username,
                Email = user.Email,
                IsActive = user.IsActive,
                UserGroupId = user.UserGroupId,
                Permissions = user.Roles.SelectMany(r => r.Permissions).Select(p => p.Name).ToList()
            };
            return Ok(dto);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] UserCreateRequest request)
        {
            var passwordHash = _passwordHasher.HashPassword(request.Password, out string salt);
            
            var user = new User
            {
                Id = Guid.NewGuid(),
                Username = request.Username,
                Email = request.Email,
                PasswordHash = passwordHash,
                Salt = salt,
                UserGroupId = request.UserGroupId,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            // Handle custom permissions by creating a dedicated role for this user
            if (request.Permissions != null && request.Permissions.Any())
            {
                var normalizedRequestPermissions = request.Permissions.Select(p => p.ToLowerInvariant()).ToList();
                var allPermissions = await _context.Permissions.ToListAsync();
                var permissions = allPermissions
                    .Where(p => normalizedRequestPermissions.Contains(p.Name.ToLowerInvariant()))
                    .ToList();

                if (permissions.Any())
                {
                    var customRole = new Role
                    {
                        Id = Guid.NewGuid(),
                        Name = $"Custom:{request.Username}:{Guid.NewGuid().ToString().Substring(0, 4)}",
                        Description = $"Custom permissions for {request.Username}",
                        Permissions = new List<Permission>()
                    };
                    _context.Roles.Add(customRole);
                    user.Roles.Add(customRole);
                    foreach (var p in permissions) customRole.Permissions.Add(p);
                }
            }

            await _userRepository.AddAsync(user);
            return CreatedAtAction(nameof(GetById), new { id = user.Id }, user);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(Guid id, [FromBody] UserDto dto)
        {
            if (id != dto.Id) return BadRequest();
            
            var user = await _userRepository.GetByIdAsync(id);
            if (user == null) return NotFound();

            user.Username = dto.Username;
            user.Email = dto.Email;
            user.IsActive = dto.IsActive;
            user.UserGroupId = dto.UserGroupId;
            user.UpdatedAt = DateTime.UtcNow;

            await _userRepository.UpdateAsync(user);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(Guid id)
        {
            await _userRepository.DeleteAsync(id);
            return NoContent();
        }

        [HttpPut("{id}/permissions")]
        public async Task<IActionResult> UpdatePermissions(Guid id, [FromBody] List<string> permissionNames)
        {
            var user = await _context.Users
                .Include(u => u.Roles)
                .ThenInclude(r => r.Permissions)
                .FirstOrDefaultAsync(u => u.Id == id);

            if (user == null) return NotFound();

            // Find or create custom role for this user
            var customRole = user.Roles.FirstOrDefault(r => r.Name.StartsWith("Custom:"));
            
            var normalizedRequestPermissions = permissionNames.Select(p => p.ToLowerInvariant()).ToList();
            
            // Load all permissions first to avoid EF Core translation issues with ToLower inside Contains
            var allPermissions = await _context.Permissions.ToListAsync();
            var permissions = allPermissions
                .Where(p => normalizedRequestPermissions.Contains(p.Name.ToLowerInvariant()))
                .ToList();

            if (customRole == null)
            {
                if (permissions.Any())
                {
                    customRole = new Role
                    {
                        Id = Guid.NewGuid(),
                        Name = $"Custom:{user.Username}:{Guid.NewGuid().ToString().Substring(0, 4)}",
                        Description = $"Custom permissions for {user.Username}",
                        Permissions = new List<Permission>()
                    };
                    _context.Roles.Add(customRole);
                    user.Roles.Add(customRole);
                    foreach (var p in permissions) customRole.Permissions.Add(p);
                }
            }
            else
            {
                // Safe update of many-to-many collection navigation
                customRole.Permissions.Clear();
                foreach (var p in permissions)
                {
                    customRole.Permissions.Add(p);
                }

                if (!permissions.Any())
                {
                    user.Roles.Remove(customRole);
                    _context.Roles.Remove(customRole);
                }
            }

            await _context.SaveChangesAsync();
            return Ok();
        }
    }
}
