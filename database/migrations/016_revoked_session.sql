/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 16 : signed-out sessions

   A sign-in token is a signed JWT that lives for hours. Until now Sign out
   only threw the token away in the browser, so a copy of it kept working
   until it expired (client review N03: signed-out, expired or revoked
   sessions must be refused by the API).

   Sign out now records the token's ID here, and every request checks it, the
   same way a disabled user is already refused at once (D049). Rows are only
   useful until the token would have expired anyway; they are kept as a
   record, not deleted.
   Additive only: an older API that doesn't know the table is unaffected.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE philmart.Sys_RevokedSession (
    TokenID    VARCHAR(64)       NOT NULL CONSTRAINT PK_revoked_session PRIMARY KEY,
    ActorKind  VARCHAR(20)       NOT NULL,
    ActorID    UNIQUEIDENTIFIER  NOT NULL,
    ExpiresAt  DATETIMEOFFSET(7) NOT NULL,
    RevokedAt  DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_rs_revoked DEFAULT (philmart.ServerNow()),
    Reason     VARCHAR(30)       NOT NULL CONSTRAINT DF_rs_reason DEFAULT ('sign_out'),
    CONSTRAINT CK_rs_actor_kind CHECK (ActorKind IN ('Buy_Buyer','Shop_User','platform_admin')),
    CONSTRAINT CK_rs_reason CHECK (Reason IN ('sign_out'))
);
GO

CREATE INDEX IX_rs_actor ON philmart.Sys_RevokedSession (ActorID, RevokedAt);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'N03. One row per signed-out login token (its jti). The API refuses a token listed here even though its signature and expiry are still valid.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_RevokedSession';
GO
