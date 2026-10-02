using System.Text.RegularExpressions;

namespace Philmart.UnitTests;

// Agreement clause 9.2 and task T06. The test clock only works if nothing goes
// around philmart.ServerNow(). One DateTime.Now in a rule or one inline
// SYSDATETIMEOFFSET() in the SQL and that rule can no longer be tested by
// moving the clock, so these fail the build when either appears.
public class AuthoritativeTimeTests
{
    private static readonly Regex DotNetClock = new(
        @"\b(DateTime|DateTimeOffset)\s*\.\s*(Now|UtcNow|Today)\b|\bTimeProvider\.System\b|\bEnvironment\.TickCount",
        RegexOptions.Compiled);

    private static readonly Regex SqlClock = new(
        @"\b(SYSDATETIMEOFFSET|SYSDATETIME|SYSUTCDATETIME|GETDATE|GETUTCDATE|CURRENT_TIMESTAMP)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Raised with the Client, not fixed here: 010 and earlier are controlled
    // files. Shop_CommercialTerms.EffectiveFrom defaults from SYSUTCDATETIME(),
    // so a frozen test clock does not move it. Anything new fails.
    private static readonly string[] KnownSqlExceptions =
    {
        "003_onboarding.sql: DF_sct_from",
    };

    [Fact]
    public void Source_never_reads_the_web_server_clock()
    {
        var offenders = new List<string>();

        foreach (var file in Directory.EnumerateFiles(Path.Combine(RepoRoot(), "src"), "*.cs", SearchOption.AllDirectories))
        {
            if (IsBuildOutput(file))
            {
                continue;
            }

            var lines = File.ReadAllLines(file);
            for (int i = 0; i < lines.Length; i++)
            {
                var code = StripCSharpComment(lines[i]);
                if (DotNetClock.IsMatch(code))
                {
                    offenders.Add($"{Path.GetRelativePath(RepoRoot(), file)}:{i + 1}: {lines[i].Trim()}");
                }
            }
        }

        Assert.True(offenders.Count == 0, "Use IServerClock instead:\n" + string.Join("\n", offenders));
    }

    [Fact]
    public void Migrations_only_read_the_clock_inside_ServerNow()
    {
        var offenders = new List<string>();

        foreach (var file in Directory.EnumerateFiles(Path.Combine(RepoRoot(), "database", "migrations"), "*.sql").Order())
        {
            var name = Path.GetFileName(file);
            var sql = StripSqlComments(File.ReadAllText(file));

            sql = Regex.Replace(
                sql,
                @"CREATE\s+FUNCTION\s+philmart\.ServerNow\s*\(.*?^\s*GO\s*$",
                "",
                RegexOptions.Singleline | RegexOptions.Multiline | RegexOptions.IgnoreCase);

            foreach (var line in sql.Split('\n'))
            {
                if (!SqlClock.IsMatch(line))
                {
                    continue;
                }

                bool known = KnownSqlExceptions.Any(k =>
                    k.StartsWith(name + ":") && line.Contains(k[(name.Length + 2)..]));

                if (!known)
                {
                    offenders.Add($"{name}: {line.Trim()}");
                }
            }
        }

        Assert.True(offenders.Count == 0, "Call philmart.ServerNow() instead:\n" + string.Join("\n", offenders));
    }

    [Fact]
    public void Known_exceptions_are_still_real()
    {
        // When the Client's fix lands, the exception has to come out of the
        // list too, or it would quietly allow the same mistake to come back.
        var sql = File.ReadAllText(Path.Combine(RepoRoot(), "database", "migrations", "003_onboarding.sql"));

        Assert.Matches(@"DF_sct_from\s+DEFAULT\s*\(\s*CAST\s*\(\s*SYSUTCDATETIME\(\)", sql);
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "Philmart.sln")))
        {
            dir = dir.Parent;
        }

        return dir?.FullName ?? throw new InvalidOperationException("Could not find Philmart.sln above " + AppContext.BaseDirectory);
    }

    private static bool IsBuildOutput(string path)
    {
        var parts = path.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return parts.Contains("bin") || parts.Contains("obj");
    }

    private static string StripCSharpComment(string line)
    {
        int comment = line.IndexOf("//", StringComparison.Ordinal);
        return comment < 0 ? line : line[..comment];
    }

    private static string StripSqlComments(string sql)
    {
        sql = Regex.Replace(sql, @"/\*.*?\*/", "", RegexOptions.Singleline);
        return Regex.Replace(sql, @"--[^\n]*", "");
    }
}
