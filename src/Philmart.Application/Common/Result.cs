namespace Philmart.Application.Common;

// For things that can fail for a business reason. Keep exceptions for faults.
public class Result
{
    protected Result(bool succeeded, string? error, string? decisionRef)
    {
        Succeeded = succeeded;
        Error = error;
        DecisionRef = decisionRef;
    }

    public bool Succeeded { get; private set; }

    public string? Error { get; private set; }

    public string? DecisionRef { get; private set; }

    public static Result Ok()
    {
        return new Result(true, null, null);
    }

    public static Result Fail(string error, string? decisionRef = null)
    {
        return new Result(false, error, decisionRef);
    }
}

public class Result<T>
{
    private Result(bool succeeded, T? value, string? error, string? decisionRef)
    {
        Succeeded = succeeded;
        Value = value;
        Error = error;
        DecisionRef = decisionRef;
    }

    public bool Succeeded { get; private set; }

    public T? Value { get; private set; }

    public string? Error { get; private set; }

    public string? DecisionRef { get; private set; }

    public static Result<T> Ok(T value)
    {
        return new Result<T>(true, value, null, null);
    }

    public static Result<T> Fail(string error, string? decisionRef = null)
    {
        return new Result<T>(false, default, error, decisionRef);
    }
}
