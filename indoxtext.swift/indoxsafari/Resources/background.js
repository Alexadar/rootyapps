let port = browser.runtime.connectNative('application.id');

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  switch (request.command) {
    case 'DoSumm':
      browser.runtime.sendNativeMessage(
        'application.id',
        {
          task: 'DoSumm',
          data: request.data.innerHtml,
        },
        function (message) {
          console.log('Received native port message:');
          console.log(message);
          sendResponse(message);
        },
      );
      break;
    case 'DoCancel':
      browser.runtime.sendNativeMessage(
        'application.id',
        {
          task: 'DoCancel',
          data: '',
        },
        function (message) {
          console.log('Received native port message:');
          console.log(message);
          sendResponse(message);
        },
      );
      break;
    case 'GetStatus':
      browser.runtime.sendNativeMessage(
        'application.id',
        {
          task: 'GetStatus',
          data: {},
        },
        function (message) {
          console.log('Received native port message:');
          console.log(message);
          sendResponse(message);
        },
      );
      break;
    default:
      sendResponse({});
      break;
  }
  return true;
});
