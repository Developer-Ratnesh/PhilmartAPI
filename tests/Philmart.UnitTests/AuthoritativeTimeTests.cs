using System.Text.RegularExpressions;

namespace Philmart.UnitTests;

// Clause 9.2. Anything reading the clock without philmart.ServerNow() won't
// move with the test clock. These fail the build when that happens.
public class AuthoritativeTimeTests
{
    private static readonly Regex DotNetClock = new(@"\b(DateTime|DateTimeOffset)\.(Now|UtcNow|Today)\b");

    private static readonly Regex SqlClock = new(
        @"\b(SYSDATETIMEOFFSET|SYSDATETIME|SYSUTCDATETIME|GETDATE|GETUTCDATE|CURRENT_TIMESTAMP)\b",
        RegexOptions.IgnoreCase);

    // 003 defaults Shop_CommercialTerms.EffectiveFrom from SYSUTCDATETIME().
    // It's a controlled file so we can't fix it here, raised with the client.
    private static readonly string[] KnownSqlExceptions = { "DF_sct_from" };

    // Login token expiry. The same web server checks it against its own clock,
    // so database time would be wrong here. Not a business rule.
    private static readonly string[] AllowedFiles = { "TokenIssuer.cs" };

    [Fact]
    public void Source_never_reads_the_web_server_clock()
    {
        string root = RepoRoot();
        var offenders = new List<string>();

        foreach (string file in Directory.EnumerateFiles(Path.Combine(root, "src"), "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar)
                || file.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar)
                || AllowedFiles.Contains(Path.GetFileName(file)))
            {
                continue;
            }

            string[] lines = File.ReadAllLines(file);
            for (int i = 0; i < lines.Length; i++)
            {
                // comments are allowed to mention DateTime.Now, see IServerClock
                int comment = lines[i].IndexOf("//");
                string code = comment < 0 ? lines[i] : lines[i].Substring(0, comment);

                if (DotNetClock.IsMatch(code))
                {
                    offenders.Add(Path.GetRelativePath(root, file) + ":" + (i + 1) + ": " + lines[i].Trim());
                }
            }
        }

        Assert.True(offenders.Count == 0, "Use IServerClock instead:\n" + string.Join("\n", offenders));
    }

    [Fact]
    public void Migrations_only_read_the_clock_inside_ServerNow()
    {
        var offenders = new List<string>();

        foreach (string file in Directory.GetFiles(Path.Combine(RepoRoot(), "database", "migrations"), "*.sql"))
        {
            string sql = File.ReadAllText(file);

            sql = Regex.Replace(sql, @"/\*.*?\*/", "", RegexOptions.Singleline);
            sql = Regex.Replace(sql, @"--[^\n]*", "");

            // ServerNow itself is the one place allowed to call the real clock
            sql = Regex.Replace(
                sql,
                @"CREATE\s+FUNCTION\s+philmart\.ServerNow\s*\(.*?^\s*GO\s*$",
                "",
                RegexOptions.Singleline | RegexOptions.Multiline | RegexOptions.IgnoreCase);

            foreach (string line in sql.Split('\n'))
            {
                if (SqlClock.IsMatch(line) && !KnownSqlExceptions.Any(x => line.Contains(x)))
                {
                    offenders.Add(Path.GetFileName(file) + ": " + line.Trim());
                }
            }
        }

        Assert.True(offenders.Count == 0, "Call philmart.ServerNow() instead:\n" + string.Join("\n", offenders));
    }

    // Once the client sends a fixed 003, take DF_sct_from out of the list above.
    // Otherwise it would let the same mistake back in.
    [Fact]
    public void Known_exception_is_still_there()
    {
        string sql = File.ReadAllText(Path.Combine(RepoRoot(), "database", "migrations", "003_onboarding.sql"));

        Assert.Matches(@"DF_sct_from\s+DEFAULT\s*\(\s*CAST\s*\(\s*SYSUTCDATETIME\(\)", sql);
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "Philmart.sln")))
        {
            dir = dir.Parent;
        }

        if (dir == null)
        {
            throw new InvalidOperationException("Couldn't find Philmart.sln above " + AppContext.BaseDirectory);
        }

        return dir.FullName;
    }
}
