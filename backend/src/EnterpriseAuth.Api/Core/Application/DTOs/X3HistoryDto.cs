using System;
using System.Collections.Generic;

namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class X3HistoryDocumentDto
    {
        public string Company { get; set; } = string.Empty;
        public string SalesSite { get; set; } = string.Empty;
        public string InvoiceNumber { get; set; } = string.Empty;
        public int InvoiceTypeFlag { get; set; } // 1 = Invoice, 2 = Credit Note
        public string DocType => InvoiceTypeFlag == 2 ? "CREDIT_NOTE" : "INVOICE";
        public string BillToCustomer { get; set; } = string.Empty;
        public string CustomerCode { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public DateTime InvoiceDate { get; set; }
        public string CreationUser { get; set; } = string.Empty;
        public string SoNumber { get; set; } = string.Empty;
        public string DeliveryNumber { get; set; } = string.Empty;
        public decimal TotalAmountNotTax { get; set; }
        public decimal TotalAmountIncTax { get; set; }
        public List<X3HistoryLineDto> Lines { get; set; } = new List<X3HistoryLineDto>();
    }

    public class X3HistoryLineDto
    {
        public int LineNumber { get; set; }
        public string ProductCode { get; set; } = string.Empty;
        public string ProductDescription { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public string SalesUOM { get; set; } = string.Empty;
        public decimal GrossPrice { get; set; }
        public decimal NetPrice { get; set; }
        public decimal LineAmountNotTax { get; set; }
        public decimal LineAmountIncTax { get; set; }
        public decimal DiscountValue1 { get; set; }
        public decimal DiscountValue2 { get; set; }
    }

    public class X3HistoryRawRowDto
    {
        public string Company { get; set; } = string.Empty;
        public string SalesSite { get; set; } = string.Empty;
        public string InvoiceNumber { get; set; } = string.Empty;
        public int InvoiceTypeFlag { get; set; }
        public string BillToCustomer { get; set; } = string.Empty;
        public string CustomerCode { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public DateTime InvoiceDate { get; set; }
        public string CreationUser { get; set; } = string.Empty;
        public string SoNumber { get; set; } = string.Empty;
        public string DeliveryNumber { get; set; } = string.Empty;
        public int LineNumber { get; set; }
        public string ProductCode { get; set; } = string.Empty;
        public string ProductDescription { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public string SalesUOM { get; set; } = string.Empty;
        public decimal GrossPrice { get; set; }
        public decimal NetPrice { get; set; }
        public decimal LineAmountNotTax { get; set; }
        public decimal LineAmountIncTax { get; set; }
        public decimal DiscountValue1 { get; set; }
        public decimal DiscountValue2 { get; set; }
    }
}
