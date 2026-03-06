using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfUserGroupRepository : IUserGroupRepository
    {
        private readonly ApplicationDbContext _context;

        public EfUserGroupRepository(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<UserGroup?> GetByIdAsync(Guid id)
        {
            return await _context.UserGroups
                .Include(g => g.Role)
                .Include(g => g.Users)
                .FirstOrDefaultAsync(g => g.Id == id);
        }

        public async Task<UserGroup?> GetByNameAsync(string name)
        {
            return await _context.UserGroups
                .Include(g => g.Role)
                .FirstOrDefaultAsync(g => g.Name == name);
        }

        public async Task<IEnumerable<UserGroup>> GetAllAsync()
        {
            return await _context.UserGroups
                .Include(g => g.Role)
                .ToListAsync();
        }

        public async Task AddAsync(UserGroup group)
        {
            await _context.UserGroups.AddAsync(group);
            await _context.SaveChangesAsync();
        }

        public async Task UpdateAsync(UserGroup group)
        {
            _context.UserGroups.Update(group);
            await _context.SaveChangesAsync();
        }

        public async Task DeleteAsync(Guid id)
        {
            var group = await _context.UserGroups.FindAsync(id);
            if (group != null)
            {
                _context.UserGroups.Remove(group);
                await _context.SaveChangesAsync();
            }
        }
    }
}
