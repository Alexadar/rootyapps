browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("Received request: ", request);

    if (request.command) {
        browser.runtime.sendNativeMessage("oleksandr.aisixteen.indoxtext-safari", request)
            .then(response => {
                console.log("Received response: ", response);
                sendResponse(response);
            })
            .catch(error => {
                console.error("Error: ", error);
                sendResponse({ error: error.message });
            });
        
        return true; // Will respond asynchronously
    }
});
