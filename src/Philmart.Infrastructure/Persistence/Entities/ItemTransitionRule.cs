namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ItemTransitionRule
{
    public string FromState { get; set; } = null!;

    public string ToState { get; set; } = null!;

    public bool RequiresReason { get; set; }

    public string DecisionRef { get; set; } = null!;

    public string? Note { get; set; }
}
