using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public interface IAuthService
    {
        Task<AuthResponse?> LoginAsync(LoginRequest request);
        Task<bool> RegisterAsync(RegisterRequest request);
        Task<bool> ForgotPasswordAsync(ForgotPasswordRequest request);
    }

    public class AuthService : IAuthService
    {
        private readonly IUserRepository _userRepository;
        private readonly IRoleRepository _roleRepository;
        private readonly IPasswordHasher _passwordHasher;
        private readonly ITokenService _tokenService;

        public AuthService(
            IUserRepository userRepository, 
            IRoleRepository roleRepository,
            IPasswordHasher passwordHasher, 
            ITokenService tokenService)
        {
            _userRepository = userRepository;
            _roleRepository = roleRepository;
            _passwordHasher = passwordHasher;
            _tokenService = tokenService;
        }

        public async Task<AuthResponse?> LoginAsync(LoginRequest request)
        {
            var user = await _userRepository.GetByUsernameAsync(request.Username);
            if (user == null)
            {
                // Try case-insensitive fallback if the repository doesn't handle it
                var allUsers = await _userRepository.GetAllAsync();
                user = allUsers.FirstOrDefault(u => u.Username.Equals(request.Username, StringComparison.OrdinalIgnoreCase));
            }

            if (user == null || !user.IsActive) return null;

            if (!_passwordHasher.VerifyPassword(request.Password, user.PasswordHash, user.Salt))
                return null;

            var token = _tokenService.GenerateToken(user);

            var permissions = user.Roles.SelectMany(r => r.Permissions).Select(p => p.Name).Distinct().ToList();
            
            Console.WriteLine($"AuthService: User {user.Username} logged in with {permissions.Count} permissions.");
            foreach(var p in permissions.Take(10)) Console.WriteLine($" - {p}");

            return new AuthResponse
            {
                Token = token,
                Username = user.Username,
                Permissions = permissions
            };
        }

        public async Task<bool> RegisterAsync(RegisterRequest request)
        {
            var existingUser = await _userRepository.GetByEmailAsync(request.Email);
            if (existingUser != null) return false;

            var viewerRole = await _roleRepository.GetByNameAsync("Viewer");
            var logisticsGroup = (await _userRepository.GetAllAsync())
                .Select(u => u.UserGroup)
                .Where(g => g != null)
                .FirstOrDefault(g => g!.Name == "Logistics"); 
            
            // Note: In a production app, we'd have a dedicated IUserGroupRepository.GetByNameAsync
            
            var passwordHash = _passwordHasher.HashPassword(request.Password, out string salt);

            var user = new User
            {
                Id = Guid.NewGuid(),
                Email = request.Email,
                Username = request.Username,
                PasswordHash = passwordHash,
                Salt = salt,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                Roles = viewerRole != null ? new List<Role> { viewerRole } : new List<Role>(),
                UserGroupId = logisticsGroup?.Id
            };

            await _userRepository.AddAsync(user);
            return true;
        }

        public async Task<bool> ForgotPasswordAsync(ForgotPasswordRequest request)
        {
            var user = await _userRepository.GetByEmailAsync(request.Email);
            if (user == null) return false;

            // In a real app, send an email with a reset token
            return true;
        }
    }
}
