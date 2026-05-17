namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface IPasswordHasher
    {
        string HashPassword(string password, out string salt);
        bool VerifyPassword(string password, string hash, string salt);
    }
}
