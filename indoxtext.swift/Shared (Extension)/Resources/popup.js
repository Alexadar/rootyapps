const btnSumm = document.getElementById('btnSumm');
const btnCancel = document.getElementById('btnCancel');

function getActiveTab() {
  return browser.tabs.query({active: true, currentWindow: true});
}

function summarize() {
  getActiveTab().then(tabs => {
    browser.tabs.sendMessage(tabs[0].id, {
      command: 'DoSumm',
    });
  });
}

function cancelSummarize() {
  browser.runtime
    .sendNativeMessage('application.id', {
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

  switch (statusVal) {
    case '0':
      btnSumm.disabled = false;
      btnCancel.disabled = true;
      if (isInProgress === true || isInProgress === null) {
        isInProgress = false;
        beginSummMode();
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
    .sendNativeMessage('application.id', {
      command: 'GetStatus',
      data: {},
    })
    .then(handleResponse, handleError);
}, 100);

btnSumm.addEventListener('click', summarize);
btnCancel.addEventListener('click', cancelSummarize);
