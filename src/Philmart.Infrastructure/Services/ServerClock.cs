using Microsoft.EntityFrameworkCore;
using Philmart.Domain.Abstractions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

// Cached for the life of the request so one request sees one time.
public class ServerClock(IDbContextFactory<PhilmartContext> contextFactory) : IServerClock
{
    private DateTimeOffset? cachedNow;

    public async Task<DateTimeOffset> Now()
    {
        if (cachedNow != null)
        {
            return cachedNow.Value;
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var now = await context.Database
                .SqlQuery<DateTimeOffset>($"SELECT philmart.ServerNow() AS Value")
                .FirstAsync();

            cachedNow = now;

            return now;
        }
    }
}
