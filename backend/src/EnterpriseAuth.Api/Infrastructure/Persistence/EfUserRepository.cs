using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfUserRepository : IUserRepository
    {
        private readonly ApplicationDbContext _context;
        private readonly Microsoft.AspNetCore.Http.IHttpContextAccessor _httpContextAccessor;

        public EfUserRepository(ApplicationDbContext context, Microsoft.AspNetCore.Http.IHttpContextAccessor httpContextAccessor)
        {
            _context = context;
            _httpContextAccessor = httpContextAccessor;
        }

        private string GetCurrentUserSiteCode()
        {
            return _httpContextAccessor.HttpContext?.User?.FindFirst("SiteCode")?.Value ?? "ALL";
        }

        public async Task<User?> GetByIdAsync(Guid id)
        {
            var siteCode = GetCurrentUserSiteCode();
            return await _context.Users
                .Include(u => u.Roles)
                .ThenInclude(r => r.Permissions)
                .Include(u => u.Permissions)
                .AsSplitQuery()
                .FirstOrDefaultAsync(u => u.Id == id && (siteCode == "ALL" || u.SiteCode == siteCode));
        }

        public async Task<User?> GetByEmailAsync(string email)
        {
            return await _context.Users
                .Include(u => u.Roles)
                .ThenInclude(r => r.Permissions)
                .Include(u => u.Permissions)
                .AsSplitQuery()
                .FirstOrDefaultAsync(u => u.Email == email);
        }

        public async Task<User?> GetByUsernameAsync(string username)
        {
            return await _context.Users
                .Include(u => u.Roles)
                .ThenInclude(r => r.Permissions)
                .Include(u => u.Permissions)
                .AsSplitQuery()
                .FirstOrDefaultAsync(u => u.Username == username);
        }

        public async Task<IEnumerable<User>> GetAllAsync()
        {
            var siteCode = GetCurrentUserSiteCode();
            var query = _context.Users
                .Include(u => u.Roles)
                .ThenInclude(r => r.Permissions)
                .Include(u => u.Permissions)
                .AsSplitQuery();

            if (siteCode != "ALL")
            {
                query = query.Where(u => u.SiteCode == siteCode || u.SiteCode == "ALL");
            }

            return await query.ToListAsync();
        }

        public async Task AddAsync(User user)
        {
            await _context.Users.AddAsync(user);
            await _context.SaveChangesAsync();
        }

        public async Task UpdateAsync(User user)
        {
            user.TokenVersion = Guid.NewGuid(); // Invalidate token on update
            _context.Users.Update(user);
            await _context.SaveChangesAsync();
        }

        public async Task DeleteAsync(Guid id)
        {
            var user = await _context.Users.FindAsync(id);
            if (user != null)
            {
                _context.Users.Remove(user);
                await _context.SaveChangesAsync();
            }
        }
    }
}
