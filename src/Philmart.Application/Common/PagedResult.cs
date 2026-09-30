namespace Philmart.Application.Common;

public class PagedResult<T>
{
    public List<T> Items { get; set; } = new List<T>();

    public int Page { get; set; }

    public int PageSize { get; set; }

    public int TotalCount { get; set; }

    public int TotalPages
    {
        get
        {
            if (PageSize <= 0)
            {
                return 0;
            }

            return (int)Math.Ceiling(TotalCount / (double)PageSize);
        }
    }

    public bool HasPrevious
    {
        get { return Page > 1; }
    }

    public bool HasNext
    {
        get { return Page < TotalPages; }
    }

    public static PagedResult<T> Create(List<T> items, int page, int pageSize, int totalCount)
    {
        var result = new PagedResult<T>();
        result.Items = items;
        result.Page = page;
        result.PageSize = pageSize;
        result.TotalCount = totalCount;

        return result;
    }

    public static PagedResult<T> Empty(int page, int pageSize)
    {
        return Create(new List<T>(), page, pageSize, 0);
    }
}

public class PageRequest
{
    public const int MaxPageSize = 100;

    public PageRequest()
    {
        Page = 1;
        PageSize = 24;
    }

    public PageRequest(int page, int pageSize)
    {
        Page = page;
        PageSize = pageSize;
    }

    public int Page { get; set; }

    public int PageSize { get; set; }

    public int SafePage
    {
        get
        {
            if (Page < 1)
            {
                return 1;
            }

            return Page;
        }
    }

    public int SafePageSize
    {
        get
        {
            if (PageSize < 1)
            {
                return 24;
            }

            if (PageSize > MaxPageSize)
            {
                return MaxPageSize;
            }

            return PageSize;
        }
    }

    public int Skip
    {
        get { return (SafePage - 1) * SafePageSize; }
    }
}
