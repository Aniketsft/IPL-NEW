using Xunit;
using EnterpriseAuth.Api.Core.Application.DTOs;
using System.Text.Json;
using System.Collections.Generic;

namespace EnterpriseAuth.UnitTests
{
    public class ProductMappingTests
    {
        [Fact]
        public void ProductLookupDto_ShouldSerializeToCamelCase()
        {
            // Arrange
            var dto = new ProductLookupDto
            {
                ProductCode = "P001",
                ProductDescription = "Test Product",
                StockUnit = "KG",
                SalesUnit = "PK"
            };

            var options = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            };

            // Act
            var json = JsonSerializer.Serialize(dto, options);

            // Assert
            Assert.Contains("\"productCode\":\"P001\"", json);
            Assert.Contains("\"productDescription\":\"Test Product\"", json);
            Assert.Contains("\"stockUnit\":\"KG\"", json);
            Assert.Contains("\"salesUnit\":\"PK\"", json);
        }
    }
}
