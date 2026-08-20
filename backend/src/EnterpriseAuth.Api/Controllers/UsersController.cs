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
                RoleId = u.Roles.FirstOrDefault()?.Id,
                Permissions = u.Roles.SelectMany(r => r.Permissions).Concat(u.Permissions).Select(p => p.Name).Distinct().ToList()
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
                RoleId = user.Roles.FirstOrDefault()?.Id,
                Permissions = user.Roles.SelectMany(r => r.Permissions).Concat(user.Permissions).Select(p => p.Name).Distinct().ToList()
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
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            // Assign standard role if RoleId is provided
            if (request.RoleId.HasValue && request.RoleId.Value != Guid.Empty)
            {
                var standardRole = await _context.Roles.FindAsync(request.RoleId.Value);
                if (standardRole != null)
                {
                    user.Roles.Add(standardRole);
                }
            }

            // Handle custom permissions directly mapping to User
            if (request.Permissions != null && request.Permissions.Any())
            {
                var normalizedRequestPermissions = request.Permissions.Select(p => p.ToLowerInvariant()).ToList();
                var allPermissions = await _context.Permissions.ToListAsync();
                var permissions = allPermissions
                    .Where(p => normalizedRequestPermissions.Contains(p.Name.ToLowerInvariant()))
                    .ToList();

                if (permissions.Any())
                {
                    foreach (var p in permissions) user.Permissions.Add(p);
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
            user.UpdatedAt = DateTime.UtcNow;

            // Handle standard role update
            var currentStandardRole = user.Roles.FirstOrDefault();
            if (dto.RoleId.HasValue && dto.RoleId.Value != Guid.Empty)
            {
                if (currentStandardRole == null || currentStandardRole.Id != dto.RoleId.Value)
                {
                    if (currentStandardRole != null)
                    {
                        user.Roles.Remove(currentStandardRole);
                    }
                    var newStandardRole = await _context.Roles.FindAsync(dto.RoleId.Value);
                    if (newStandardRole != null)
                    {
                        user.Roles.Add(newStandardRole);
                    }
                }
            }
            else
            {
                if (currentStandardRole != null)
                {
                    user.Roles.Remove(currentStandardRole);
                }
            }

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
                .Include(u => u.Permissions)
                .FirstOrDefaultAsync(u => u.Id == id);

            if (user == null) return NotFound();

            var normalizedRequestPermissions = permissionNames.Select(p => p.ToLowerInvariant()).ToList();
            
            // Load all permissions first to avoid EF Core translation issues with ToLower inside Contains
            var allPermissions = await _context.Permissions.ToListAsync();
            var permissions = allPermissions
                .Where(p => normalizedRequestPermissions.Contains(p.Name.ToLowerInvariant()))
                .ToList();

            user.Permissions.Clear();
            foreach (var p in permissions)
            {
                user.Permissions.Add(p);
            }

            await _context.SaveChangesAsync();
            return Ok();
        }
        [HttpPut("{id}/password")]
        public async Task<IActionResult> UpdatePassword(Guid id, [FromBody] ChangePasswordRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Password)) return BadRequest("Password cannot be empty.");

            var user = await _userRepository.GetByIdAsync(id);
            if (user == null) return NotFound();

            var passwordHash = _passwordHasher.HashPassword(request.Password, out string salt);
            user.PasswordHash = passwordHash;
            user.Salt = salt;
            user.UpdatedAt = DateTime.UtcNow;

            await _userRepository.UpdateAsync(user);
            return Ok();
        }
    }

    public class ChangePasswordRequest
    {
        public string Password { get; set; } = string.Empty;
    }
}
