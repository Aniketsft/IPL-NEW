namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class PriceListDto
    {
        public string PliCode { get; set; } = string.Empty;
        public int Priority { get; set; }
        public int RuleType { get; set; }
        public int IsQtyBased { get; set; }
        public int FocType { get; set; }
        public string Fil0 { get; set; } = string.Empty;
        public string Fld0 { get; set; } = string.Empty;
        public string Fil1 { get; set; } = string.Empty;
        public string Fld1 { get; set; } = string.Empty;
        public string MatchKey1 { get; set; } = string.Empty;
        public string MatchKey2 { get; set; } = string.Empty;
        public double BasePrice { get; set; }
        public double DiscountPct { get; set; }
        public double DiscountAmt { get; set; }
        public double FocQtyMin { get; set; }
        public double FocQtyBkt { get; set; }
        public double FocAmtMin { get; set; }
        public double FocAmtBkt { get; set; }
        public string FocItmRef { get; set; } = string.Empty;
        public double FocQty { get; set; }
        public double MinQty { get; set; }
        public double MaxQty { get; set; }
        public string ValidFrom { get; set; } = string.Empty;
        public string ValidTo { get; set; } = string.Empty;
        public int ReasonType { get; set; }
    }
}
