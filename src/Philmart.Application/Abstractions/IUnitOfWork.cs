using System.Data;

namespace Philmart.Application.Abstractions;

// Bidding needs Serializable. When two bids clash SQL Server kills one with
// error 1205 and the caller retries.
public interface IUnitOfWork
{
    Task<T> InTransaction<T>(
        Func<CancellationToken, Task<T>> work,
        IsolationLevel isolation = IsolationLevel.ReadCommitted,
        CancellationToken cancellationToken = default);
}
