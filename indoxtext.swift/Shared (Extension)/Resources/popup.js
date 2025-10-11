const btnSumm = document.getElementById('btnSumm');
const btnCancel = document.getElementById('btnCancel');

function getActiveTab() {
  return browser.tabs.query({active: true, currentWindow: true});
}

function summarize() {
  console.log('Summarize button clicked');
  getActiveTab().then(tabs => {
    console.log('Active tabs:', tabs);
    if (tabs && tabs.length > 0) {
      console.log('Sending message to tab:', tabs[0].id);
      browser.tabs.sendMessage(tabs[0].id, {
        command: 'DoSumm',
      }).then(response => {
        console.log('Message sent successfully, response:', response);
      }).catch(error => {
        console.error('Error sending message:', error);
      });
    } else {
      console.error('No active tab found');
    }
  }).catch(error => {
    console.error('Error getting active tab:', error);
  });
}

function cancelSummarize() {
  browser.runtime
    .sendNativeMessage('oleksandr.aisixteen.indoxtext-safari', {
      command: 'DoCancel',
      data: {},
    })
    .then(handleResponse, handleError);
}

function beginSummMode() {
  document.getElementById('beginSumm').classList.remove('containerHidden');
  document.getElementById('progressSumm').classList.add('containerHidden');
}

function setPercentage(p) {
  document
    .getElementById('percentageVal')
    .setAttribute('style', 'width: ' + p + '%');
}

function progressSummMode() {
  document.getElementById('progressSummHeader').innerHTML = 'Summarizing';
  document.getElementById('beginSumm').classList.add('containerHidden');
  document.getElementById('progressSumm').classList.remove('containerHidden');
  setPercentage(0);
}

var isInProgress = null;

function handleResponse(message) {
  const statusVal = message.status;
  const percentageVal = message.percentage;
  const synopsis = message.synopsys;

  switch (statusVal) {
    case '0':
      btnSumm.disabled = false;
      btnCancel.disabled = true;
      if (isInProgress === true || isInProgress === null) {
        isInProgress = false;
        beginSummMode();

        // If we have a synopsis, send it to the content script
        if (synopsis) {
          getActiveTab().then(tabs => {
            if (tabs && tabs.length > 0) {
              browser.tabs.sendMessage(tabs[0].id, {
                command: 'ShowResult',
                synopsys: synopsis
              }).catch(error => {
                console.error('Error sending result to content script:', error);
              });
            }
          });
        }
      }
      break;
    case '1':
      btnSumm.disabled = true;
      btnCancel.disabled = false;
      if (isInProgress === false || isInProgress === null) {
        isInProgress = true;
        progressSummMode();
      }
      setPercentage(percentageVal);
      break;
    case '2':
      document.getElementById('progressSummHeader').innerHTML = 'Cancelling';
      btnSumm.disabled = true;
      btnCancel.disabled = true;
      break;
  }
}

function handleError(error) {
  console.error(error);
}

setInterval(function () {
  browser.runtime
    .sendNativeMessage('oleksandr.aisixteen.indoxtext-safari', {
      command: 'GetStatus',
      data: {},
    })
    .then(handleResponse, handleError);
}, 100);

btnSumm.addEventListener('click', summarize);
btnCancel.addEventListener('click', cancelSummarize);
