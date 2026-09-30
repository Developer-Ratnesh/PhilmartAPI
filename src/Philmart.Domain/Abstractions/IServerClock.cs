namespace Philmart.Domain.Abstractions;

// Current time, from the database. Don't use DateTime.Now in a rule, the web
// server clock can drift and auction results must not depend on it.
public interface IServerClock
{
    Task<DateTimeOffset> Now();
}
