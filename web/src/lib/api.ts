import { currentToken, type SignedInUser } from "@/lib/session";

// public/config.js sets this on the server we deploy to, so the API address
// can change without a rebuild
function apiBase(): string {
  const fromConfig = typeof window === "undefined" ? undefined : (window as { PHILMART_API_URL?: string }).PHILMART_API_URL;
  return fromConfig || process.env.NEXT_PUBLIC_API_URL || "https://localhost:7143";
}

export type PagedResult<T> = {
  items: T[];
  page: number;
  pageSize: number;
  totalCount: number;
  totalPages: number;
  hasPrevious: boolean;
  hasNext: boolean;
};

export type MarketplaceItem = {
  listingID: string;
  itemID: string;
  title: string;
  listingType: "fixed_price" | "auction";
  shopID: string;
  shopName: string;
  areaCountry: string | null;
  type: string | null;
  theme: string | null;
  priceMinor: number | null;
  // auctions only
  currentBidMinor: number | null;
  endsAt: string | null;
  bidCount: number;
  primaryImageUrl: string | null;
  imageCount: number;
  listedAt: string;
};

export type BuyerListItem = {
  listingID: string;
  itemNumber: string | null;
  title: string | null;
  listingType: "fixed_price" | "auction" | null;
  shopID: string | null;
  shopName: string | null;
  priceMinor: number | null;
  currentBidMinor: number | null;
  primaryImageUrl: string | null;
  status: "available" | "auction_open" | "auction_closed" | "sold" | "unavailable";
  // saved date or last viewed, depending on the list
  at: string;
};

export type SupportCategory = { value: string; label: string };

export type SupportReceipt = { reference: string; submittedAt: string };

export type ClassificationOption = {
  id: string;
  code: string;
  name: string;
  sortOrder: number;
};

export type MarketplaceQuery = {
  query?: string;
  sellingMethod?: string;
  areaCountryId?: string;
  typeId?: string;
  subtypeId?: string;
  formatId?: string;
  stampStateId?: string;
  themeId?: string;
  shopId?: string;
  sort?: string;
  page?: number;
  pageSize?: number;
};

export type ShopStatus =
  | "application_submitted"
  | "application_rejected"
  | "setup_access_granted"
  | "active"
  | "deactivated";

export type AdminDashboard = {
  asAt: string;
  applicationsAwaitingReview: number;
  shopsInSetup: number;
  activeShops: number;
  deactivatedShops: number;
  liveFixedPriceListings: number;
  liveAuctions: number;
  liveAuctionsWithBids: number;
  itemsReadyToList: number;
  itemsPastReadyToListEscalation: number;
  feesOutstandingMinor: number;
  feesOverdueMinor: number;
  shopsWithOverdueFees: number;
};

export type AdminShop = {
  id: string;
  reference: string;
  tradingName: string;
  legalEntityName: string | null;
  status: ShopStatus;
  createdAt: string;
  setupAccessGrantedAt: string | null;
  activatedAt: string | null;
  deactivatedAt: string | null;
  deactivationReason: string | null;
  reactivatedAt: string | null;
  liveListingCount: number;
  feesOutstandingMinor: number;
  feesOverdueMinor: number;
  hasOverdueFees: boolean;
};

export type AdminShopQuery = {
  query?: string;
  status?: ShopStatus | "";
  overdueOnly?: boolean;
  page?: number;
  pageSize?: number;
};

export type SignInResponse = { token: string; user: SignedInUser };
export type PinChallenge = { challenge: string };

export type PickupPoint = { id: string; name: string; address: string | null };

export type DeliveryOption = {
  id: string;
  code: string;
  name: string;
  methodKind: "shipping" | "collection";
  requiresPickupPoint: boolean;
  requiresAddress: boolean;
  pickupPoints: PickupPoint[];
};

export type LegalDocument = {
  versionID: string;
  code: string;
  name: string;
  version: string;
  acceptanceMode: "accept" | "acknowledge";
  body: string;
};

export type RegistrationState = {
  step: number;
  emailVerified: boolean;
  completed: boolean;
  email: string;
  fullName: string | null;
};

export type Address = {
  addressLine1: string;
  addressLine2?: string | null;
  city: string;
  province?: string | null;
  postalCode?: string | null;
  countryCode: string;
};

export type ShippingPreference = {
  deliveryMethodID: string;
  available: boolean;
  pickupPointID?: string | null;
  useAddress?: boolean;
};

export type BidHistory = { sequenceNo: number; amountMinor: number; placedAt: string };

export type ListingDetail = {
  listingID: string;
  itemID: string;
  reference: string;
  title: string;
  description: string | null;
  listingType: "fixed_price" | "auction";
  state: string;
  areaCountry: string | null;
  type: string | null;
  subtype: string | null;
  theme: string | null;
  condition: string | null;
  catalogueReference: string | null;
  images: string[];
  shopID: string;
  shopName: string;
  shopReference: string;
  shopActive: boolean;
  priceMinor: number | null;
  startingPriceMinor: number | null;
  bidIncrementMinor: number | null;
  currentBidMinor: number | null;
  nextMinimumBidMinor: number | null;
  reserveMet: boolean;
  startsAt: string | null;
  endsAt: string | null;
  softCloseSeconds: number | null;
  extensionCount: number;
  serverNow: string;
  bids: BidHistory[];
  deliveryOptions: DeliveryOption[];
  commitment: LegalDocument | null;
};

export type ShopProfile = { shopID: string; reference: string; name: string; blurb: string | null; active: boolean };

export type PurchaseDefaults = { deliveryMethodID: string; pickupPointID: string | null; address: Address | null };
export type PurchaseResult = { saleTransactionID: string; priceMinor: number; deliveryMethod: string };
export type BidResult = { bidID: string; amountMinor: number; leading: boolean; endsAt: string; extendedClose: boolean };

export type ShopUser = {
  id: string;
  email: string;
  fullName: string;
  isAdministrator: boolean;
  disabled: boolean;
  pending: boolean;
  permissions: string[];
};

export type Permission = { code: string; name: string; category: string; description: string; adminOnly: boolean };

export type ShopAuction = {
  listingID: string;
  itemID: string;
  reference: string;
  title: string;
  state: string;
  startingPriceMinor: number;
  reservePriceMinor: number | null;
  currentBidMinor: number | null;
  bidCount: number;
  startsAt: string;
  endsAt: string;
  extensionCount: number;
  soldPriceMinor: number | null;
  cancellationReason: string | null;
};

export type ReadyItem = { itemID: string; reference: string; title: string; sellerMinimumPriceMinor: number | null };

export type CreateAuction = {
  itemID: string;
  startingPriceMinor: number;
  reservePriceMinor: number | null;
  bidIncrementMinor: number;
  startsAt: string;
  endsAt: string;
  softCloseSeconds: number | null;
  softCloseExtensionSeconds: number | null;
};

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly decisionRef?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = currentToken();
  const response = await fetch(`${apiBase()}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  });

  if (!response.ok) {
    let detail = response.statusText;
    let decisionRef: string | undefined;

    try {
      const problem = await response.json();
      detail = problem.detail ?? detail;
      decisionRef = problem.decisionRef ?? undefined;
    } catch {
      // not a problem+json body, keep the status text
    }

    throw new ApiError(detail, response.status, decisionRef);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return response.json() as Promise<T>;
}

function post(body?: unknown): RequestInit {
  return { method: "POST", body: body === undefined ? undefined : JSON.stringify(body) };
}

function toQueryString(params: Record<string, unknown>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") {
      search.set(key, String(value));
    }
  }
  const qs = search.toString();
  return qs ? `?${qs}` : "";
}

export const api = {
  auth: {
    // SCR-PUB-014, buyers sign in with an emailed PIN
    buyerPin: (email: string) => request<PinChallenge>("/api/auth/buyer/pin", post({ email })),

    buyerVerify: (challenge: string, pin: string) =>
      request<SignInResponse>("/api/auth/buyer/verify", post({ challenge, pin })),

    login: (email: string, password: string, kind: "shop" | "admin", shopReference?: string) =>
      request<SignInResponse>("/api/auth/login", post({ email, password, kind, shopReference })),

    me: () => request<SignedInUser>("/api/auth/me", { cache: "no-store" }),
  },

  register: {
    start: (email: string) => request<PinChallenge>("/api/register", post({ email })),

    verify: (challenge: string, pin: string) => request<SignInResponse>("/api/register/verify", post({ challenge, pin })),

    state: () => request<RegistrationState>("/api/register", { cache: "no-store" }),

    personal: (body: {
      fullName: string;
      mobile: string;
      identificationType: string;
      identificationNumber: string;
      dateOfBirth: string;
    }) => request<void>("/api/register/personal", { method: "PUT", body: JSON.stringify(body) }),

    deliveryOptions: () => request<DeliveryOption[]>("/api/register/delivery-options"),

    address: (body: Address & { shippingPreferences: ShippingPreference[]; outbidAlerts: boolean }) =>
      request<void>("/api/register/address", { method: "PUT", body: JSON.stringify(body) }),

    legal: () => request<LegalDocument[]>("/api/register/legal", { cache: "no-store" }),

    accept: (versionIDs: string[]) => request<void>("/api/register/accept", post({ versionIDs })),
  },

  listings: {
    detail: (listingId: string) =>
      request<ListingDetail>(`/api/marketplace/listings/${listingId}`, { cache: "no-store" }),

    purchaseDefaults: (listingId: string) =>
      request<PurchaseDefaults[]>(`/api/listings/${listingId}/purchase-defaults`, { cache: "no-store" }),

    buy: (
      listingId: string,
      body: {
        commitmentVersionID: string;
        deliveryMethodID: string;
        pickupPointID?: string | null;
        address?: Address | null;
        idempotencyKey: string;
      },
    ) => request<PurchaseResult>(`/api/listings/${listingId}/buy`, post(body)),

    bid: (listingId: string, body: { commitmentVersionID: string; amountMinor: number; idempotencyKey: string }) =>
      request<BidResult>(`/api/listings/${listingId}/bids`, post(body)),
  },

  shop: {
    users: () => request<ShopUser[]>("/api/shop/users", { cache: "no-store" }),

    permissions: () => request<Permission[]>("/api/shop/users/permissions"),

    invite: (body: { email: string; fullName: string; permissions: string[] }) =>
      request<{ shopUserID: string; invitationLink: string }>("/api/shop/users", post(body)),

    setPermissions: (userId: string, permissions: string[]) =>
      request<void>(`/api/shop/users/${userId}/permissions`, { method: "PUT", body: JSON.stringify({ permissions }) }),

    disable: (userId: string) => request<void>(`/api/shop/users/${userId}/disable`, post()),

    enable: (userId: string) => request<void>(`/api/shop/users/${userId}/enable`, post()),

    acceptInvitation: (token: string, password: string) =>
      request<void>("/api/shop/invitations/accept", post({ token, password })),

    auctions: () => request<ShopAuction[]>("/api/shop/auctions", { cache: "no-store" }),

    readyItems: () => request<ReadyItem[]>("/api/shop/auctions/ready-items", { cache: "no-store" }),

    createAuction: (body: CreateAuction) => request<string>("/api/shop/auctions", post(body)),

    cancelAuction: (listingId: string, reason: string, itemMissingOrDamaged: boolean) =>
      request<void>(`/api/shop/auctions/${listingId}/cancel`, post({ reason, itemMissingOrDamaged })),
  },

  marketplace: {
    browse: (query: MarketplaceQuery = {}) =>
      request<PagedResult<MarketplaceItem>>(
        `/api/marketplace/items${toQueryString(query)}`,
        { cache: "no-store" },
      ),

    getListing: (listingId: string) =>
      request<MarketplaceItem>(`/api/marketplace/items/${listingId}`),

    shop: (shopId: string) => request<ShopProfile>(`/api/marketplace/shops/${shopId}`),

    storefront: (shopId: string, page = 1, pageSize = 10) =>
      request<PagedResult<MarketplaceItem>>(
        `/api/marketplace/shops/${shopId}/items${toQueryString({ page, pageSize })}`,
      ),

    areaCountries: () =>
      request<ClassificationOption[]>("/api/marketplace/classifications/area-countries"),

    types: () => request<ClassificationOption[]>("/api/marketplace/classifications/types"),

    subtypes: (typeId: string) =>
      request<ClassificationOption[]>(
        `/api/marketplace/classifications/types/${typeId}/subtypes`,
      ),

    themes: () => request<ClassificationOption[]>("/api/marketplace/classifications/themes"),
  },

  // buyers only, the API works out which buyer from the token
  account: {
    saved: (search = "", page = 1, pageSize = 10) =>
      request<PagedResult<BuyerListItem>>(`/api/account/saved${toQueryString({ search, page, pageSize })}`, { cache: "no-store" }),

    isSaved: (listingId: string) => request<{ saved: boolean }>(`/api/account/saved/${listingId}`, { cache: "no-store" }),

    save: (listingId: string) => request<void>(`/api/account/saved/${listingId}`, { method: "PUT" }),

    removeSaved: (listingId: string) => request<void>(`/api/account/saved/${listingId}`, { method: "DELETE" }),

    recent: (page = 1, pageSize = 10) =>
      request<PagedResult<BuyerListItem>>(`/api/account/recent${toQueryString({ page, pageSize })}`, { cache: "no-store" }),

    viewed: (listingId: string) => request<void>(`/api/account/recent/${listingId}`, { method: "PUT" }),

    removeRecent: (listingId: string) => request<void>(`/api/account/recent/${listingId}`, { method: "DELETE" }),
  },

  support: {
    categories: () => request<SupportCategory[]>("/api/support/categories"),

    submit: (body: {
      category: string;
      subject: string;
      relatedReference?: string;
      message: string;
      contactName?: string;
      contactEmail?: string;
    }) => request<SupportReceipt>("/api/support", post(body)),
  },

  // platform admin only
  admin: {
    dashboard: () => request<AdminDashboard>("/api/admin/dashboard", { cache: "no-store" }),

    shops: (query: AdminShopQuery = {}) =>
      request<PagedResult<AdminShop>>(`/api/admin/shops${toQueryString(query)}`, {
        cache: "no-store",
      }),

    shop: (shopId: string) =>
      request<AdminShop>(`/api/admin/shops/${shopId}`, { cache: "no-store" }),
  },
};

// amounts come back in cents
export function formatMoney(minor: number | null | undefined, symbol = "R"): string {
  if (minor === null || minor === undefined) {
    return "—";
  }
  return `${symbol} ${(minor / 100).toLocaleString("en-ZA", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

export function formatTimeLeft(endsAt: string | null): string | null {
  if (!endsAt) {
    return null;
  }

  const remaining = new Date(endsAt).getTime() - Date.now();
  if (remaining <= 0) {
    return "Closed";
  }

  const days = Math.floor(remaining / 86_400_000);
  const hours = Math.floor((remaining % 86_400_000) / 3_600_000);
  const minutes = Math.floor((remaining % 3_600_000) / 60_000);

  if (days > 0) return `${days}d ${hours}h left`;
  if (hours > 0) return `${hours}h ${minutes}m left`;
  return `${minutes}m left`;
}

export function errorText(e: unknown, fallback = "Something went wrong. Please try again."): string {
  return e instanceof ApiError ? e.message : fallback;
}

// one per click, so a double submit is one purchase or one bid
export function newIdempotencyKey(): string {
  return crypto.randomUUID();
}
