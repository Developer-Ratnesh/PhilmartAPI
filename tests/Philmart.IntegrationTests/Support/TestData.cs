using Microsoft.Data.SqlClient;
using Philmart.Infrastructure.Security;

namespace Philmart.IntegrationTests.Support;

// Sets up rows directly as system. Nothing can be deleted, so each test
// makes its own Shop, buyer and items instead of cleaning up.
public class TestData(string connectionString)
{
    public const string Password = "Test-password-1";

    private static readonly string PasswordHash = Passwords.Hash(Password);

    public async Task EnsureReferenceData()
    {
        await Execute(@"
            IF NOT EXISTS (SELECT 1 FROM philmart.Sys_DeliveryMethod WHERE Code = 'TEST_COURIER')
                INSERT INTO philmart.Sys_DeliveryMethod (Code, Name, MethodKind, RequiresAddress, SortOrder)
                VALUES ('TEST_COURIER', N'Test courier', 'shipping', 1, 90);

            IF NOT EXISTS (SELECT 1 FROM philmart.Sys_DeliveryMethod WHERE Code = 'TEST_PICKUP')
                INSERT INTO philmart.Sys_DeliveryMethod (Code, Name, MethodKind, RequiresPickupPoint, SortOrder)
                VALUES ('TEST_PICKUP', N'Test pickup', 'shipping', 1, 91);

            IF NOT EXISTS (SELECT 1 FROM philmart.Sys_PickupPoint WHERE Code = 'TEST-PP-1')
                INSERT INTO philmart.Sys_PickupPoint (DeliveryMethodID, Code, Name, AddressLine1, City)
                SELECT ID, 'TEST-PP-1', N'Test pickup point', N'1 Test Street', N'Cape Town'
                FROM philmart.Sys_DeliveryMethod WHERE Code = 'TEST_PICKUP';

            INSERT INTO philmart.Sys_LegalDocumentVersion (DocumentCode, Version, Body, ContentSha256, IsDraft, PublishedAt)
            SELECT d.Code, 'test-1', N'Test wording for ' + d.Code,
                   CONVERT(CHAR(64), HASHBYTES('SHA2_256', N'test ' + d.Code), 2), 0, philmart.ServerNow()
            FROM philmart.Sys_LegalDocument d
            WHERE NOT EXISTS (SELECT 1 FROM philmart.Sys_LegalDocumentVersion v
                              WHERE v.DocumentCode = d.Code AND v.PublishedAt IS NOT NULL AND v.SupersededAt IS NULL);");
    }

    public async Task<TestShop> CreateShop(string status = "active")
    {
        var shop = new TestShop();
        shop.ID = Guid.NewGuid();
        shop.Reference = "T-" + Unique();
        shop.AdminID = Guid.NewGuid();
        shop.AdminEmail = "admin-" + shop.Reference.ToLowerInvariant() + "@test.local";

        await Execute(@"
            INSERT INTO philmart.Shop_Shop (ID, Reference, TradingName, Status, SetupAccessGrantedAt, ActivatedAt, DeactivationReason)
            VALUES (@shop, @ref, N'Test Shop ' + @ref, @status, philmart.ServerNow(), philmart.ServerNow(),
                    CASE WHEN @status = 'deactivated' THEN N'test' END);

            INSERT INTO philmart.Shop_User (ID, ShopID, Email, FullName, PasswordHash, IsAdministrator, AcceptedAt)
            VALUES (@admin, @shop, @email, N'Test Admin', @hash, 1, philmart.ServerNow());

            INSERT INTO philmart.Shop_DeliveryMethod (ShopID, DeliveryMethodID)
            SELECT @shop, ID FROM philmart.Sys_DeliveryMethod WHERE Code IN ('TEST_COURIER', 'TEST_PICKUP');",
            P("@shop", shop.ID), P("@ref", shop.Reference), P("@status", status), P("@admin", shop.AdminID),
            P("@email", shop.AdminEmail), P("@hash", PasswordHash));

        return shop;
    }

    public async Task<(Guid Id, string Email)> AddShopUser(TestShop shop, params string[] permissions)
    {
        Guid id = Guid.NewGuid();
        string email = "user-" + Unique() + "@test.local";

        await Execute(@"INSERT INTO philmart.Shop_User (ID, ShopID, Email, FullName, PasswordHash, AcceptedAt)
                        VALUES (@id, @shop, @email, N'Test User', @hash, philmart.ServerNow());",
            P("@id", id), P("@shop", shop.ID), P("@email", email), P("@hash", PasswordHash));

        foreach (string code in permissions)
        {
            await Execute("INSERT INTO philmart.Shop_UserPermission (ShopUserID, PermissionCode, ShopID) VALUES (@id, @code, @shop)",
                P("@id", id), P("@code", code), P("@shop", shop.ID));
        }

        return (id, email);
    }

    // a buyer who finished all four steps and accepted what's current now.
    // No password, buyers sign in with an emailed PIN.
    public async Task<(Guid Id, string Email)> CreateBuyer()
    {
        Guid id = Guid.NewGuid();
        string email = "buyer-" + Unique() + "@test.local";

        await Execute(@"
            INSERT INTO philmart.Buy_Buyer (ID, Email, FullName, Mobile, IdentificationType, IdentificationNumber,
                                            DateOfBirth, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep)
            VALUES (@id, @email, N'Test Buyer', '0820000000', 'sa_id', '9001015800085', '1990-01-01',
                    philmart.ServerNow(), philmart.ServerNow(), 4);

            INSERT INTO philmart.Buy_Address (BuyerID, AddressLine1, City, PostalCode, IsDefault)
            VALUES (@id, N'1 Buyer Road', N'Cape Town', '8001', 1);

            INSERT INTO philmart.Sys_LegalAcceptance (VersionID, DocumentCode, DocumentVersion, SubjectKind, BuyerID, Context)
            SELECT v.ID, v.DocumentCode, v.Version, 'Buy_Buyer', @id, 'registration'
            FROM philmart.Sys_LegalDocumentVersion v
            WHERE v.PublishedAt IS NOT NULL AND v.SupersededAt IS NULL
              AND v.DocumentCode IN ('LEGAL-BUY-001', 'LEGAL-AUC-001', 'LEGAL-PRV-001');",
            P("@id", id), P("@email", email));

        return (id, email);
    }

    public async Task<Guid> CreateItem(TestShop shop, string state = "ready_to_list", long? sellerMinimum = null)
    {
        Guid id = Guid.NewGuid();
        Guid? sellerId = null;

        if (sellerMinimum != null)
        {
            sellerId = Guid.NewGuid();
            await Execute("INSERT INTO philmart.Sell_Seller (ID, ShopID, Reference, FullName) VALUES (@id, @shop, @ref, N'Test Seller')",
                P("@id", sellerId.Value), P("@shop", shop.ID), P("@ref", "S-" + Unique()));
        }

        await Execute(@"INSERT INTO philmart.Item_Item (ID, ShopID, Reference, Title, State, ReadyToListSince, IsConsigned, SellerID, SellerMinimumPriceMinor)
                        VALUES (@id, @shop, @ref, N'Test item ' + @ref, @state,
                                CASE WHEN @state = 'ready_to_list' THEN philmart.ServerNow() END,
                                CASE WHEN @seller IS NULL THEN 0 ELSE 1 END, @seller, @min)",
            P("@id", id), P("@shop", shop.ID), P("@ref", "I-" + Unique()), P("@state", state),
            P("@seller", (object?)sellerId ?? DBNull.Value), P("@min", (object?)sellerMinimum ?? DBNull.Value));

        return id;
    }

    public async Task<Guid> CreateFixedPrice(TestShop shop, long priceMinor)
    {
        Guid item = await CreateItem(shop, "listed");
        Guid id = Guid.NewGuid();

        await Execute(@"INSERT INTO philmart.List_Listing (ID, ShopID, ItemID, ListingType, State, Reference, PriceMinor, ListedAt, ExpiresAt)
                        VALUES (@id, @shop, @item, 'fixed_price', 'live', @ref, @price, philmart.ServerNow(), DATEADD(DAY, 30, philmart.ServerNow()))",
            P("@id", id), P("@shop", shop.ID), P("@item", item), P("@ref", "L-" + Unique()), P("@price", priceMinor));

        return id;
    }

    // live auction, started an hour ago by database time, ending at the given time
    public async Task<Guid> CreateAuction(TestShop shop, DateTimeOffset endsAt, long startMinor = 10000, long incrementMinor = 500,
        long? reserveMinor = null, int? softCloseSeconds = null)
    {
        Guid item = await CreateItem(shop, "listed");
        Guid id = Guid.NewGuid();

        await Execute(@"INSERT INTO philmart.List_Listing (ID, ShopID, ItemID, ListingType, State, Reference, StartingPriceMinor, ReservePriceMinor,
                                                          BidIncrementMinor, StartsAt, EndsAt, SoftCloseSeconds, SoftCloseExtensionSeconds)
                        VALUES (@id, @shop, @item, 'auction', 'live', @ref, @start, @reserve, @inc,
                                DATEADD(HOUR, -1, philmart.ServerNow()), @ends, @soft, @soft)",
            P("@id", id), P("@shop", shop.ID), P("@item", item), P("@ref", "A-" + Unique()), P("@start", startMinor),
            P("@reserve", (object?)reserveMinor ?? DBNull.Value), P("@inc", incrementMinor), P("@ends", endsAt),
            P("@soft", (object?)softCloseSeconds ?? DBNull.Value));

        return id;
    }

    public Task Restrict(Guid buyerId, Guid? shopId)
    {
        return Execute(@"INSERT INTO philmart.Buy_Restriction (BuyerID, Scope, ShopID, Reason, ImposedBy)
                         VALUES (@buyer, CASE WHEN @shop IS NULL THEN 'platform' ELSE 'Shop_Shop' END, @shop, N'test restriction', @buyer)",
            P("@buyer", buyerId), P("@shop", (object?)shopId ?? DBNull.Value));
    }

    public async Task<T?> Scalar<T>(string sql, params SqlParameter[] parameters)
    {
        using (var conn = await Open())
        using (var cmd = new SqlCommand(sql, conn))
        {
            cmd.Parameters.AddRange(parameters);
            object? value = await cmd.ExecuteScalarAsync();
            return value == null || value == DBNull.Value ? default : (T)value;
        }
    }

    // runs as system unless told otherwise, for the RLS tests
    public async Task Execute(string sql, params SqlParameter[] parameters)
    {
        using (var conn = await Open())
        using (var cmd = new SqlCommand(sql, conn))
        {
            cmd.Parameters.AddRange(parameters);
            await cmd.ExecuteNonQueryAsync();
        }
    }

    public async Task<SqlConnection> Open(string actorKind = "system", Guid? shopId = null, Guid? actorId = null)
    {
        var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();

        using (var cmd = new SqlCommand(@"EXEC sp_set_session_context N'philmart.actor_kind', @kind;
                                          EXEC sp_set_session_context N'philmart.shop_id', @shop;
                                          EXEC sp_set_session_context N'philmart.actor_id', @actor;
                                          SET QUOTED_IDENTIFIER ON;", conn))
        {
            cmd.Parameters.Add(P("@kind", actorKind));
            cmd.Parameters.Add(P("@shop", (object?)shopId ?? DBNull.Value));
            cmd.Parameters.Add(P("@actor", (object?)actorId ?? DBNull.Value));
            await cmd.ExecuteNonQueryAsync();
        }

        return conn;
    }

    public static SqlParameter P(string name, object value)
    {
        return new SqlParameter(name, value);
    }

    private static string Unique()
    {
        return Guid.NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant();
    }
}

public class TestShop
{
    public Guid ID { get; set; }

    public string Reference { get; set; } = "";

    public Guid AdminID { get; set; }

    public string AdminEmail { get; set; } = "";
}
