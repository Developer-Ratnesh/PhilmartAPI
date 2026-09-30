using Philmart.Domain.Exceptions;

using static Philmart.Domain.Constants.PhilmartConstants;

namespace Philmart.Domain.Rules;

// Mirror of the Item_TransitionRule table. The database blocks anything not in
// that table, we keep a copy here so the screens can work out which buttons to
// show without a round trip. A test checks the two lists still match.
public static class ItemStateMachine
{
    public class Transition
    {
        public string FromState { get; set; } = string.Empty;
        public string ToState { get; set; } = string.Empty;
        public bool RequiresReason { get; set; }
        public string DecisionRef { get; set; } = string.Empty;
        public string Note { get; set; } = string.Empty;
    }

    private static readonly List<Transition> Rules = BuildRules();

    private static List<Transition> BuildRules()
    {
        var rules = new List<Transition>();

        Add(rules, ItemState.ReadyToList, ItemState.Listed, false, "D013", "listing created");
        Add(rules, ItemState.ReadyToList, ItemState.RemovedFromStock, true, "D010", "can be undone");
        Add(rules, ItemState.ReadyToList, ItemState.MissingDamaged, true, "D016", "");
        Add(rules, ItemState.ReadyToList, ItemState.ReturnedToSeller, true, "D065", "handed back, final");
        Add(rules, ItemState.ReadyToList, ItemState.WrittenOff, true, "D056", "final");

        Add(rules, ItemState.Listed, ItemState.SoldFulfilmentPending, false, "D017", "sold or won");
        Add(rules, ItemState.Listed, ItemState.ReadyToList, false, "D012/D014/D015/D016", "listing ended, no sale");
        Add(rules, ItemState.Listed, ItemState.MissingDamaged, true, "D016", "auction cancelled");

        Add(rules, ItemState.SoldFulfilmentPending, ItemState.Complete, false, "D017", "paid and delivered");
        Add(rules, ItemState.SoldFulfilmentPending, ItemState.ReadyToList, true, "D018", "sale cancelled, still saleable");
        Add(rules, ItemState.SoldFulfilmentPending, ItemState.MissingDamaged, true, "D018", "sale cancelled, not saleable");

        Add(rules, ItemState.RemovedFromStock, ItemState.ReadyToList, false, "D010", "put back");
        Add(rules, ItemState.RemovedFromStock, ItemState.ReturnedToSeller, true, "D065", "");
        Add(rules, ItemState.RemovedFromStock, ItemState.WrittenOff, true, "D056", "");

        Add(rules, ItemState.MissingDamaged, ItemState.WrittenOff, true, "D056", "only now do we tell the seller");
        Add(rules, ItemState.MissingDamaged, ItemState.ReadyToList, true, "D016", "found or repaired");

        return rules;
    }

    private static void Add(List<Transition> rules, string from, string to,
        bool needsReason, string decision, string note)
    {
        var t = new Transition();
        t.FromState = from;
        t.ToState = to;
        t.RequiresReason = needsReason;
        t.DecisionRef = decision;
        t.Note = note;

        rules.Add(t);
    }

    public static IReadOnlyList<Transition> All
    {
        get { return Rules; }
    }

    public static bool IsTerminal(string state)
    {
        return state == ItemState.ReturnedToSeller || state == ItemState.WrittenOff;
    }

    public static Transition? Find(string fromState, string toState)
    {
        foreach (var rule in Rules)
        {
            if (rule.FromState == fromState && rule.ToState == toState)
            {
                return rule;
            }
        }

        return null;
    }

    public static List<Transition> AvailableFrom(string fromState)
    {
        var found = new List<Transition>();

        foreach (var rule in Rules)
        {
            if (rule.FromState == fromState)
            {
                found.Add(rule);
            }
        }

        return found;
    }

    // Checked here as well as in the database so the user gets a readable
    // message instead of SQL error 50027.
    public static void Assert(string fromState, string toState, string? reason)
    {
        if (fromState == toState)
        {
            return;
        }

        var rule = Find(fromState, toState);

        if (rule == null)
        {
            throw new BusinessRuleViolationException(
                "An item can't go from " + fromState + " to " + toState + ".",
                "D010/D016/D017/D065");
        }

        if (rule.RequiresReason && string.IsNullOrWhiteSpace(reason))
        {
            throw new BusinessRuleViolationException(
                "Moving an item from " + fromState + " to " + toState + " needs a reason.",
                rule.DecisionRef);
        }
    }
}
