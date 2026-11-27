using System;
using Microsoft.AspNetCore.DataProtection;

namespace EnterpriseAuth.Api.Infrastructure.Security
{
    public interface IHepSecretProtector
    {
        string? Protect(string? plaintext);
        string? UnprotectOrPlaintext(string? storedValue);
        string MaskApiKey(string? apiKey);
        bool IsMaskedPlaceholder(string? input);
    }

    /// <summary>
    /// Encrypts per-device HEP API keys at rest using ASP.NET Core Data Protection,
    /// while safely handling legacy plaintext values until they are rotated/re-saved.
    /// </summary>
    public sealed class HepSecretProtector : IHepSecretProtector
    {
        private const string ProtectedPrefix = "dp:";
        private readonly IDataProtector? _protector;

        public HepSecretProtector(IDataProtectionProvider? dataProtectionProvider = null)
        {
            _protector = dataProtectionProvider?.CreateProtector("EnterpriseAuth.Device.HepApiKey.v1");
        }

        public string? Protect(string? plaintext)
        {
            if (string.IsNullOrWhiteSpace(plaintext)) return null;
            var trimmed = plaintext.Trim();
            if (trimmed.StartsWith(ProtectedPrefix, StringComparison.Ordinal)) return trimmed;
            if (_protector == null) return trimmed;
            return ProtectedPrefix + _protector.Protect(trimmed);
        }

        public string? UnprotectOrPlaintext(string? storedValue)
        {
            if (string.IsNullOrWhiteSpace(storedValue)) return null;
            var trimmed = storedValue.Trim();
            if (!trimmed.StartsWith(ProtectedPrefix, StringComparison.Ordinal))
            {
                return trimmed;
            }
            if (_protector == null) return null;
            try
            {
                return _protector.Unprotect(trimmed.Substring(ProtectedPrefix.Length));
            }
            catch
            {
                return null;
            }
        }

        public string MaskApiKey(string? storedOrPlaintext)
        {
            var plain = UnprotectOrPlaintext(storedOrPlaintext);
            if (string.IsNullOrEmpty(plain)) return string.Empty;
            if (plain.Length <= 4) return new string('•', plain.Length);
            return new string('•', Math.Min(12, plain.Length - 4)) + plain.Substring(plain.Length - 4);
        }

        public bool IsMaskedPlaceholder(string? input)
        {
            return !string.IsNullOrWhiteSpace(input) && input.Contains('•');
        }
    }
}
