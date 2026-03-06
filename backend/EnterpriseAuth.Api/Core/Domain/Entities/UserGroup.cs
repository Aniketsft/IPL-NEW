using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class UserGroup
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;

        // A group has one role in the current frontend design, but we'll make it flexible
        public Guid RoleId { get; set; }
        public Role? Role { get; set; }

        public ICollection<User> Users { get; set; } = new List<User>();
    }
}
