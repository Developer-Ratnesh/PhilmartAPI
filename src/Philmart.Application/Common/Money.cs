namespace Philmart.Application.Common;

// Money is a whole number of cents in a long. R 245.50 is stored as 24550.
// Don't use double, float or the SQL money type, they all round badly.
public static class Money
{
    public const string DefaultCurrency = "ZAR";

    public static long ToMinor(decimal rands)
    {
        return (long)Math.Round(rands * 100m, 0, MidpointRounding.AwayFromZero);
    }

    public static decimal ToMajor(long cents)
    {
        return cents / 100m;
    }

    public static string Display(long cents, string symbol = "R")
    {
        return symbol + " " + ToMajor(cents).ToString("N0");
    }

    public static string DisplayExact(long cents, string symbol = "R")
    {
        return symbol + " " + ToMajor(cents).ToString("N2");
    }

    // Shop commission and PHILMART fees both come through here so the two can
    // never round differently.
    public static long Percent(long cents, decimal percentage)
    {
        return (long)Math.Round(cents * percentage / 100m, 0, MidpointRounding.AwayFromZero);
    }
}
