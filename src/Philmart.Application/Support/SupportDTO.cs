namespace Philmart.Application.Support;

public class SupportRequest
{
    public string Category { get; set; } = string.Empty;

    public string Subject { get; set; } = string.Empty;

    // PHILMART No. or invoice number, optional
    public string? RelatedReference { get; set; }

    public string Message { get; set; } = string.Empty;

    // only asked for when nobody is signed in, a buyer's come from their account
    public string? ContactName { get; set; }

    public string? ContactEmail { get; set; }
}

public class SupportReceiptDTO
{
    public string Reference { get; set; } = string.Empty;

    public DateTimeOffset SubmittedAt { get; set; }
}

public class SupportCategoryDTO
{
    public string Value { get; set; } = string.Empty;

    public string Label { get; set; } = string.Empty;
}
