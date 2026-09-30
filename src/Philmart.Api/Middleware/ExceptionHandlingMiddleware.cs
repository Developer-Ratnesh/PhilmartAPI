using System.Net;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.Domain.Exceptions;

namespace Philmart.Api.Middleware;

public class ExceptionHandlingMiddleware(
    RequestDelegate next,
    ILogger<ExceptionHandlingMiddleware> logger)
{
    // our database guards throw in this range
    private const int FirstPhilmartError = 50001;
    private const int LastPhilmartError = 50099;

    private const int DeadlockError = 1205;

    public async Task Invoke(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (NotFoundException ex)
        {
            await WriteError(context, HttpStatusCode.NotFound, ex.Message, null);
        }
        catch (NotAuthorisedException ex)
        {
            logger.LogWarning("Request refused: {Message}", ex.Message);

            await WriteError(context, HttpStatusCode.Forbidden, ex.Message, null);
        }
        catch (BusinessRuleViolationException ex)
        {
            await WriteError(
                context, HttpStatusCode.UnprocessableEntity, ex.Message, ex.DecisionRef);
        }
        catch (SqlException ex) when (IsPhilmartGuard(ex.Number))
        {
            // business rule, not a fault, so don't return a 500
            logger.LogWarning(ex, "A database guard blocked the change: {Message}", ex.Message);

            await WriteError(
                context, HttpStatusCode.UnprocessableEntity, ex.Message, "database rule");
        }
        catch (SqlException ex) when (ex.Number == DeadlockError)
        {
            // bidding already retried, so the site is genuinely busy
            logger.LogWarning("Request cancelled after retries on {Path}", context.Request.Path);

            await WriteError(
                context,
                HttpStatusCode.Conflict,
                "The site was busy and the request could not be finished. Please try again.",
                null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error on {Path}", context.Request.Path);

            await WriteError(
                context,
                HttpStatusCode.InternalServerError,
                "Something went wrong. Please try again.",
                null);
        }
    }

    private static bool IsPhilmartGuard(int errorNumber)
    {
        return errorNumber >= FirstPhilmartError && errorNumber <= LastPhilmartError;
    }

    private static async Task WriteError(
        HttpContext context,
        HttpStatusCode status,
        string message,
        string? decisionRef)
    {
        if (context.Response.HasStarted)
        {
            return;
        }

        context.Response.Clear();
        context.Response.StatusCode = (int)status;
        context.Response.ContentType = "application/problem+json";

        var body = new
        {
            status = (int)status,
            title = status.ToString(),
            detail = message,
            decisionRef = decisionRef,
            traceId = context.TraceIdentifier
        };

        await context.Response.WriteAsync(JsonSerializer.Serialize(body));
    }
}
