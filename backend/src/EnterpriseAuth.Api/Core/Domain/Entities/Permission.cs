using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class Permission
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty; // e.g., "User.Create"
        public string Description { get; set; } = string.Empty;

        public ICollection<Role> Roles { get; set; } = new List<Role>();
    }
}
