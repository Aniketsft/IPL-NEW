using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Domain.Entities
{
    public class User
    {
        public Guid Id { get; set; }
        public string Email { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public string PasswordHash { get; set; } = string.Empty;
        public string Salt { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? UpdatedAt { get; set; }

        public Guid? UserGroupId { get; set; }
        public UserGroup? UserGroup { get; set; }

        public ICollection<Role> Roles { get; set; } = new List<Role>();
    }
}
