using System;

namespace EnterpriseAuth.Api.Core.Application.Common
{
    public class Result<T>
    {
        public bool IsSuccess { get; }
        public T? Value { get; }
        public string? Error { get; }
        public string? ErrorCode { get; }

        private Result(bool isSuccess, T? value, string? error, string? errorCode)
        {
            IsSuccess = isSuccess;
            Value = value;
            Error = error;
            ErrorCode = errorCode;
        }

        public static Result<T> Success(T value) => new(true, value, null, null);
        public static Result<T> Failure(string error, string? code = null) => new(false, default, error, code);
    }

    public class Result
    {
        public bool IsSuccess { get; }
        public string? Error { get; }
        public string? ErrorCode { get; }

        private Result(bool isSuccess, string? error, string? errorCode)
        {
            IsSuccess = isSuccess;
            Error = error;
            ErrorCode = errorCode;
        }

        public static Result Success() => new(true, null, null);
        public static Result Failure(string error, string? code = null) => new(false, error, code);
    }
}
