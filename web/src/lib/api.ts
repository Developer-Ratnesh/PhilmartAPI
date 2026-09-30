const BASE_URL = process.env.NEXT_PUBLIC_API_URL ?? "https://localhost:7143";

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
  const response = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
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
  marketplace: {
    browse: (query: MarketplaceQuery = {}) =>
      request<PagedResult<MarketplaceItem>>(
        `/api/marketplace/items${toQueryString(query)}`,
        { cache: "no-store" },
      ),

    getListing: (listingId: string) =>
      request<MarketplaceItem>(`/api/marketplace/items/${listingId}`),

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
};

// amounts come back in cents
export function formatMoney(minor: number | null | undefined, symbol = "R"): string {
  if (minor === null || minor === undefined) {
    return "—";
  }
  return `${symbol} ${(minor / 100).toLocaleString("en-ZA", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
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
