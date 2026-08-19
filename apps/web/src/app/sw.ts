import { NetworkOnly, Serwist, type HTTPMethod, type PrecacheEntry, type RuntimeCaching } from "serwist";

declare const self: {
  location: Location;
  __SW_MANIFEST: PrecacheEntry[];
  skipWaiting(): Promise<void>;
  addEventListener(type: "message", listener: (event: MessageEvent) => void): void;
};

const apiMethods: HTTPMethod[] = ["DELETE", "GET", "HEAD", "PATCH", "POST", "PUT"];
const apiNetworkOnly: RuntimeCaching[] = apiMethods.map((method) => ({
  method,
  matcher: ({ url }) => url.origin === self.location.origin && url.pathname.startsWith("/api/"),
  handler: new NetworkOnly(),
}));

const serwist = new Serwist({
  precacheEntries: self.__SW_MANIFEST,
  runtimeCaching: apiNetworkOnly,
  skipWaiting: false,
  clientsClaim: true,
  navigationPreload: false,
});

serwist.addEventListeners();
self.addEventListener("message", (event) => {
  if ((event.data as { type?: string } | null)?.type === "SKIP_WAITING") void self.skipWaiting();
});
