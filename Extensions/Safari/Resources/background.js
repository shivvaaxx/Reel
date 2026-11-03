// Sends links to Reel through the extension's native handler (no "open Reel?" prompts).

function sendToReel(url) {
    if (!url || !/^https?:\/\//i.test(url)) return;
    browser.runtime.sendNativeMessage("com.shiva.reel", { url: url });
}

browser.action.onClicked.addListener((tab) => {
    sendToReel(tab.url);
});

browser.runtime.onInstalled.addListener(() => {
    browser.contextMenus.create({
        id: "reel-download-link",
        title: "Download Link with Reel",
        contexts: ["link"]
    });
    browser.contextMenus.create({
        id: "reel-download-page",
        title: "Download Page with Reel",
        contexts: ["page", "video"]
    });
});

browser.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId === "reel-download-link") {
        sendToReel(info.linkUrl);
    } else if (info.menuItemId === "reel-download-page") {
        sendToReel(info.pageUrl || (tab && tab.url));
    }
});
