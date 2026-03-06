using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface IUserGroupRepository
    {
        Task<UserGroup?> GetByIdAsync(Guid id);
        Task<UserGroup?> GetByNameAsync(string name);
        Task<IEnumerable<UserGroup>> GetAllAsync();
        Task AddAsync(UserGroup group);
        Task UpdateAsync(UserGroup group);
        Task DeleteAsync(Guid id);
    }
}
