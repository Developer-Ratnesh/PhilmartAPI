using Microsoft.EntityFrameworkCore;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

internal static class BuyerAccounts
{
    // D043: one account per buyer per Shop. Credit never crosses Shops.
    public static async Task<Guid> Ensure(PhilmartContext context, Guid shopId, Guid buyerId, CancellationToken cancellationToken)
    {
        var id = await context.Database
            .SqlQuery<Guid?>($"SELECT ID AS Value FROM philmart.Buy_Account WHERE ShopID = {shopId} AND BuyerID = {buyerId}")
            .FirstOrDefaultAsync(cancellationToken);

        if (id != null)
        {
            return id.Value;
        }

        Guid accountId = Guid.NewGuid();
        await context.Database.ExecuteSqlAsync(
            $"INSERT INTO philmart.Buy_Account (ID, ShopID, BuyerID) VALUES ({accountId}, {shopId}, {buyerId})",
            cancellationToken);

        return accountId;
    }
}
