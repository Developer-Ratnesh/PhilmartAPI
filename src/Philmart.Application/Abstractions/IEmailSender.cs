namespace Philmart.Application.Abstractions;

public interface IEmailSender
{
    // false until Email:Host is set. Locally that's normal, PINs go to the log instead.
    bool IsConfigured { get; }

    Task Send(string to, string subject, string body, CancellationToken cancellationToken = default);
}

public interface IEmailDispatcher
{
    // sends what's waiting in Sys_EmailMessage, returns how many went
    Task<int> SendQueued(int batchSize, CancellationToken cancellationToken = default);
}
