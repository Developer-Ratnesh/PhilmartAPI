/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 12 : taking a permission away from a Shop user

   D051 says editing a user changes their permissions directly, and that
   includes removing one. Shop_UserPermission has no revoked flag, and 009
   denies DELETE on the whole schema to philmart_app, so as shipped a grant
   could never be taken back.

   This procedure is the one way to remove a grant. It runs by ownership
   chaining, so the schema-wide DENY stays in place for everything else, and
   RLS still applies, so a Shop can only touch its own users. The caller
   writes the audit row in the same transaction, so the history of who had
   what, and who removed it, is kept (clause 8).

   Raised with the Client alongside 011.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE philmart.P_Shop_UserPermission_Revoke
    @shopUserId     UNIQUEIDENTIFIER,
    @permissionCode VARCHAR(60)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM philmart.Shop_UserPermission
    WHERE ShopUserID = @shopUserId AND PermissionCode = @permissionCode;

    RETURN 0;
END;
GO
