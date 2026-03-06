using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ITokenService
    {
        string GenerateToken(User user);
    }
}
