namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class PriceListDto
    {
        public string PliCode { get; set; }
        public int Priority { get; set; }
        public int RuleType { get; set; }
        public int IsQtyBased { get; set; }
        public int FocType { get; set; }
        public string Fil0 { get; set; }
        public string Fld0 { get; set; }
        public string Fil1 { get; set; }
        public string Fld1 { get; set; }
        public string MatchKey1 { get; set; }
        public string MatchKey2 { get; set; }
        public double BasePrice { get; set; }
        public double DiscountPct { get; set; }
        public double DiscountAmt { get; set; }
        public double FocQtyMin { get; set; }
        public double FocQtyBkt { get; set; }
        public string FocItmRef { get; set; }
        public double FocQty { get; set; }
        public double MinQty { get; set; }
        public double MaxQty { get; set; }
        public string ValidFrom { get; set; }
        public string ValidTo { get; set; }
    }
}
