using Microsoft.EntityFrameworkCore;
using Philmart.Application.Common;
using Philmart.Application.Items;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Domain.Rules;
using Philmart.Infrastructure.Persistence;
using Philmart.Infrastructure.Persistence.Entities;

namespace Philmart.Infrastructure.Services;

public class ItemService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant,
    IServerClock clock,
    IAuditWriter audit) : IItemService
{
    public async Task<ItemDTO?> GetById(Guid id, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var now = await clock.Now();

            var item = await context.ItemItems.Include(i => i.ItemImages).Where(x => x.ID == id).FirstOrDefaultAsync(cancellationToken);

            if (item == null)
            {
                return null;
            }

            return ToDto(item, now);
        }
    }

    public async Task<PagedResult<ItemDTO>> GetByState(string state, PageRequest page, CancellationToken cancellationToken = default)
    {
        var request = new ItemSearchRequest();
        request.State = state;
        request.Page = page;

        return await Search(request, cancellationToken);
    }

    public async Task<PagedResult<ItemDTO>> Search(ItemSearchRequest request, CancellationToken cancellationToken = default)
    {
        var page = request.Page ?? new PageRequest();

        using (var context = contextFactory.CreateDbContext())
        {
            var now = await clock.Now();

            // no shop filter here, the database security rules already limit
            // this to the user's own shop
            var query = context.ItemItems.Include(i => i.ItemImages).AsNoTracking();

            if (!string.IsNullOrWhiteSpace(request.State))
            {
                query = query.Where(x => x.State == request.State);
            }

            if (!string.IsNullOrWhiteSpace(request.Query))
            {
                string term = request.Query.Trim();
                query = query.Where(x => x.Title.Contains(term) || x.Reference.Contains(term));
            }

            if (request.AreaCountryID != null)
            {
                query = query.Where(x => x.AreaCountryID == request.AreaCountryID);
            }

            if (request.TypeID != null)
            {
                query = query.Where(x => x.TypeID == request.TypeID);
            }

            if (request.ThemeID != null)
            {
                query = query.Where(x => x.ThemeID == request.ThemeID);
            }

            if (request.SellerID != null)
            {
                query = query.Where(x => x.SellerID == request.SellerID);
            }

            int total = await query.CountAsync(cancellationToken);

            var rows = await query.OrderByDescending(x => x.CreatedAt).Skip(page.Skip).Take(page.SafePageSize).ToListAsync(cancellationToken);

            var items = new List<ItemDTO>();

            foreach (var row in rows)
            {
                items.Add(ToDto(row, now));
            }

            return PagedResult<ItemDTO>.Create(items, page.SafePage, page.SafePageSize, total);
        }
    }

    public async Task<List<ItemTransitionOption>> GetTransitions(Guid id, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            string? state = await context.ItemItems.Where(x => x.ID == id).Select(x => x.State).FirstOrDefaultAsync(cancellationToken);

            if (state == null)
            {
                throw new NotFoundException("Item", id);
            }

            var options = new List<ItemTransitionOption>();

            foreach (var rule in ItemStateMachine.AvailableFrom(state))
            {
                var option = new ItemTransitionOption();
                option.ToState = rule.ToState;
                option.Label = ButtonLabel(rule.ToState);
                option.RequiresReason = rule.RequiresReason;
                option.DecisionRef = rule.DecisionRef;

                options.Add(option);
            }

            return options;
        }
    }

    public async Task<Result> Transition(Guid id, ItemTransitionRequest request, CancellationToken cancellationToken = default)
    {
        if (!tenant.Has(PhilmartConstants.Permission.ItemRemove) && !tenant.Has(PhilmartConstants.Permission.ItemManage))
        {
            throw new NotAuthorisedException("You don't have permission to change the state of an item.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var item = await context.ItemItems.FirstOrDefaultAsync(x => x.ID == id, cancellationToken);

            if (item == null)
            {
                throw new NotFoundException("Item", id);
            }

            string fromState = item.State;

            try
            {
                ItemStateMachine.Assert(fromState, request.ToState, request.Reason);
            }
            catch (BusinessRuleViolationException ex)
            {
                return Result.Fail(ex.Message, ex.DecisionRef);
            }

            bool removedForOther = request.ToState == PhilmartConstants.ItemState.RemovedFromStock
                && request.RemovalReason == PhilmartConstants.RemovalReason.Other;

            if (removedForOther && string.IsNullOrWhiteSpace(request.Reason))
            {
                return Result.Fail("Removing an item with the reason 'other' needs a note.", "D066");
            }

            item.State = request.ToState;
            item.RemovalReason = request.RemovalReason;
            item.RemovalNote = request.Reason;
            item.UpdatedAt = await clock.Now();

            // a trigger sets ReadyToListSince and StateChangedAt and writes the
            // history row, don't do it here
            await context.SaveChangesAsync(cancellationToken);

            string action = removedForOther
                ? PhilmartConstants.AuditAction.ItemRemovedFromStockOther
                : "item.state." + request.ToState;

            await audit.Write("Item_Item", id.ToString(), action,
                new { State = fromState }, new { State = request.ToState },
                request.Reason, cancellationToken);

            return Result.Ok();
        }
    }

    public async Task<List<ItemDTO>> GetAgeing(int minimumDays, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var now = await clock.Now();
            var cutoff = now.AddDays(-minimumDays);

            var rows = await context.ItemItems.Include(i => i.ItemImages).AsNoTracking()
                .Where(x => x.State == PhilmartConstants.ItemState.ReadyToList && x.ReadyToListSince != null && x.ReadyToListSince <= cutoff)
                .OrderBy(x => x.ReadyToListSince)
                .ToListAsync(cancellationToken);

            var items = new List<ItemDTO>();

            foreach (var row in rows)
            {
                items.Add(ToDto(row, now));
            }

            return items;
        }
    }

    private static ItemDTO ToDto(ItemItem item, DateTimeOffset now)
    {
        var dto = new ItemDTO();
        dto.ID = item.ID;
        dto.ShopID = item.ShopID;
        dto.Reference = item.Reference;
        dto.Title = item.Title;
        dto.Description = item.Description;
        dto.State = item.State;
        dto.ReadyToListSince = item.ReadyToListSince;
        dto.IsConsigned = item.IsConsigned;
        dto.SellerID = item.SellerID;
        dto.SellerMinimumPriceMinor = item.SellerMinimumPriceMinor;
        dto.CreatedAt = item.CreatedAt;
        dto.ImageCount = item.ItemImages.Count;

        if (item.ReadyToListSince != null)
        {
            dto.DaysReadyToList = (int)(now - item.ReadyToListSince.Value).TotalDays;
        }

        foreach (var image in item.ItemImages)
        {
            if (image.IsPrimary)
            {
                dto.PrimaryImageUrl = image.StorageKey;
                break;
            }
        }

        return dto;
    }

    private static string ButtonLabel(string state)
    {
        switch (state)
        {
            case PhilmartConstants.ItemState.ReadyToList:
                return "Return to Ready to List";

            case PhilmartConstants.ItemState.Listed:
                return "Create Listing";

            case PhilmartConstants.ItemState.RemovedFromStock:
                return "Remove from Stock";

            case PhilmartConstants.ItemState.MissingDamaged:
                return "Mark Missing or Damaged";

            case PhilmartConstants.ItemState.ReturnedToSeller:
                return "Return to Seller";

            case PhilmartConstants.ItemState.WrittenOff:
                return "Write Off";

            case PhilmartConstants.ItemState.Complete:
                return "Mark Complete";

            default:
                return state;
        }
    }
}
