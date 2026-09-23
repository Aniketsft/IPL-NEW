using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfRoleRepository : IRoleRepository
    {
        private readonly ApplicationDbContext _context;
        private readonly Microsoft.AspNetCore.Http.IHttpContextAccessor _httpContextAccessor;

        public EfRoleRepository(ApplicationDbContext context, Microsoft.AspNetCore.Http.IHttpContextAccessor httpContextAccessor)
        {
            _context = context;
            _httpContextAccessor = httpContextAccessor;
        }

        private string GetCurrentUserSiteCode()
        {
            return _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value ?? "ALL";
        }

        public async Task<Role?> GetByIdAsync(Guid id)
        {
            var siteCode = GetCurrentUserSiteCode();
            return await _context.Roles
                .Include(r => r.Permissions)
                .FirstOrDefaultAsync(r => r.Id == id && (siteCode == "ALL" || r.SiteCode == siteCode));
        }

        public async Task<Role?> GetByNameAsync(string name)
        {
            return await _context.Roles
                .Include(r => r.Permissions)
                .FirstOrDefaultAsync(r => r.Name == name);
        }

        public async Task<IEnumerable<Role>> GetAllAsync()
        {
            var siteCode = GetCurrentUserSiteCode();
            var query = _context.Roles.Include(r => r.Permissions).AsQueryable();

            if (siteCode != "ALL")
            {
                query = query.Where(r => r.SiteCode == siteCode || r.SiteCode == "ALL");
            }

            return await query.ToListAsync();
        }

        public async Task AddAsync(Role role)
        {
            await _context.Roles.AddAsync(role);
            await _context.SaveChangesAsync();
        }

        public async Task UpdateAsync(Role role)
        {
            _context.Roles.Update(role);

            // Invalidate tokens for all users associated with this role
            var usersInRole = await _context.Users
                .Where(u => u.Roles.Any(r => r.Id == role.Id))
                .ToListAsync();

            foreach (var user in usersInRole)
            {
                user.TokenVersion = Guid.NewGuid();
            }

            await _context.SaveChangesAsync();
        }

        public async Task DeleteAsync(Guid id)
        {
            var role = await _context.Roles.FindAsync(id);
            if (role != null)
            {
                _context.Roles.Remove(role);
                await _context.SaveChangesAsync();
            }
        }
    }
}
