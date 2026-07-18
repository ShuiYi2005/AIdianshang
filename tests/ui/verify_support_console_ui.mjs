const response = await fetch("http://localhost:4173");
if (!response.ok) {
  throw new Error(`support console is unavailable: ${response.status}`);
}

const html = await response.text();
if (!html.includes('<div id="root"></div>') || !html.includes("/assets/")) {
  throw new Error("support console did not return the built application shell");
}

console.log("OK support console HTTP shell verified");
