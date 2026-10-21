// Where the PHILMART API lives. Change this on the server after deploying,
// no rebuild needed. Leave it empty to use the address the site was built with.
window.PHILMART_API_URL = "";

// Send visitors on http:// to the https:// address (the host's Force HTTPS
// setting does not cover this Node site). Local runs are left alone.
if (location.protocol === "http:" && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") {
  location.replace("https:" + location.href.slice(5));
}
