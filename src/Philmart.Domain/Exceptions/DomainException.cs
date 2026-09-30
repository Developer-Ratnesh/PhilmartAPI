namespace Philmart.Domain.Exceptions;

public abstract class DomainException : Exception
{
    protected DomainException(string message) : base(message)
    {
    }
}

// DecisionRef is the decision number from the register so the message can be
// traced back to the rule.
public class BusinessRuleViolationException : DomainException
{
    public BusinessRuleViolationException(string message, string? decisionRef = null)
        : base(message)
    {
        DecisionRef = decisionRef;
    }

    public string? DecisionRef { get; private set; }
}

public class NotAuthorisedException : DomainException
{
    public NotAuthorisedException(string message) : base(message)
    {
    }
}

public class NotFoundException : DomainException
{
    public NotFoundException(string entity, object key)
        : base(entity + " '" + key + "' was not found.")
    {
    }
}
