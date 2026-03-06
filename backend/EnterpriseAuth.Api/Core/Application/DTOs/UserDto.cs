using System;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class UserDto
    {
        public Guid Id { get; set; }
        public string Email { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public bool IsActive { get; set; }
        public Guid? UserGroupId { get; set; }
        public List<string> Permissions { get; set; } = new List<string>();
    }

    public class UserCreateRequest
    {
        public string Email { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
        public Guid UserGroupId { get; set; }
        public List<string> Permissions { get; set; } = new List<string>();
    }
}
