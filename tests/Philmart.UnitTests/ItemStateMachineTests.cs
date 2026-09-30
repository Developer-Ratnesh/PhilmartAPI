using Philmart.Domain.Exceptions;
using Philmart.Domain.Rules;

using static Philmart.Domain.Constants.PhilmartConstants;

namespace Philmart.UnitTests;

public class ItemStateMachineTests
{
    [Theory]
    [InlineData(ItemState.ReadyToList, ItemState.Listed)]
    [InlineData(ItemState.Listed, ItemState.SoldFulfilmentPending)]
    [InlineData(ItemState.Listed, ItemState.ReadyToList)]
    [InlineData(ItemState.SoldFulfilmentPending, ItemState.Complete)]
    [InlineData(ItemState.RemovedFromStock, ItemState.ReadyToList)]
    public void Allows_the_normal_moves(string from, string to)
    {
        ItemStateMachine.Assert(from, to, "test");

        Assert.NotNull(ItemStateMachine.Find(from, to));
    }

    [Fact]
    public void Item_comes_back_when_a_listing_ends_without_a_sale()
    {
        var rule = ItemStateMachine.Find(ItemState.Listed, ItemState.ReadyToList);

        Assert.NotNull(rule);
        Assert.False(rule!.RequiresReason);
    }

    [Fact]
    public void Returned_to_seller_is_the_end()
    {
        Assert.True(ItemStateMachine.IsTerminal(ItemState.ReturnedToSeller));
        Assert.Empty(ItemStateMachine.AvailableFrom(ItemState.ReturnedToSeller));
    }

    [Fact]
    public void Written_off_is_the_end()
    {
        Assert.True(ItemStateMachine.IsTerminal(ItemState.WrittenOff));
        Assert.Empty(ItemStateMachine.AvailableFrom(ItemState.WrittenOff));
    }

    // easy one to get wrong. a missing item doesn't come back on its own,
    // someone has to say it was found and give a reason
    [Fact]
    public void Missing_item_does_not_come_back_on_its_own()
    {
        var rule = ItemStateMachine.Find(ItemState.MissingDamaged, ItemState.ReadyToList);

        Assert.NotNull(rule);
        Assert.True(rule!.RequiresReason);
        Assert.Equal("D016", rule.DecisionRef);
    }

    [Theory]
    [InlineData(ItemState.ReadyToList, ItemState.Complete)]
    [InlineData(ItemState.ReadyToList, ItemState.SoldFulfilmentPending)]
    [InlineData(ItemState.WrittenOff, ItemState.ReadyToList)]
    [InlineData(ItemState.ReturnedToSeller, ItemState.ReadyToList)]
    [InlineData(ItemState.Complete, ItemState.Listed)]
    public void Blocks_a_move_that_is_not_in_the_list(string from, string to)
    {
        var error = Assert.Throws<BusinessRuleViolationException>(
            () => ItemStateMachine.Assert(from, to, "test"));

        Assert.Contains("can't go from", error.Message);
    }

    [Theory]
    [InlineData(ItemState.ReadyToList, ItemState.RemovedFromStock)]
    [InlineData(ItemState.ReadyToList, ItemState.MissingDamaged)]
    [InlineData(ItemState.ReadyToList, ItemState.ReturnedToSeller)]
    [InlineData(ItemState.ReadyToList, ItemState.WrittenOff)]
    public void Blocks_a_move_that_needs_a_reason_when_none_given(string from, string to)
    {
        var error = Assert.Throws<BusinessRuleViolationException>(
            () => ItemStateMachine.Assert(from, to, null));

        Assert.Contains("needs a reason", error.Message);
        Assert.NotNull(error.DecisionRef);
    }

    [Fact]
    public void Spaces_are_not_a_reason()
    {
        Assert.Throws<BusinessRuleViolationException>(
            () => ItemStateMachine.Assert(ItemState.ReadyToList, ItemState.WrittenOff, "   "));
    }

    [Fact]
    public void Moving_to_the_same_state_does_nothing()
    {
        ItemStateMachine.Assert(ItemState.ReadyToList, ItemState.ReadyToList, null);
    }

    [Fact]
    public void Every_rule_names_a_decision()
    {
        foreach (var rule in ItemStateMachine.All)
        {
            Assert.False(string.IsNullOrWhiteSpace(rule.DecisionRef));
        }
    }
}
