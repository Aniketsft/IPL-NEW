namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class CustomerLiveCreditDto
    {
        public string CustomerNo { get; set; } = string.Empty;
        public decimal AuthorizedCreditLimit { get; set; }
        public string CreditControlStatus { get; set; } = string.Empty;
        public decimal LiveOutstandingBalance { get; set; }
        public decimal LiveAvailableCredit { get; set; }
        public bool IsOnHold => CreditControlStatus.Equals("2", System.StringComparison.OrdinalIgnoreCase) ||
                                CreditControlStatus.Equals("BLOCKED", System.StringComparison.OrdinalIgnoreCase);
    }
}
