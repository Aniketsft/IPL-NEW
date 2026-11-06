namespace EnterpriseAuth.Api.Core.Application.DTOs
{
    public class DeviceSyncEventDto
    {
        public string? DeviceId { get; set; }
        public string ActionType { get; set; } = "SYNC";
        public string? Site { get; set; }
        public string? PerformedBy { get; set; }
        public string? Payload { get; set; }
    }
}
