using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class RoleDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public List<PermissionDto> Permissions { get; set; } = new List<PermissionDto>();
    }

    public class PermissionDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
    }

    public class UserGroupDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public Guid RoleId { get; set; }
    }
}
