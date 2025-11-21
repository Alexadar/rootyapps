'use strict';

var modalInjected = false;

function fallbackCopyTextToClipboard(text) {
  var textArea = document.createElement('textarea');
  textArea.value = text;

  // Avoid scrolling to bottom
  textArea.style.top = '0';
  textArea.style.left = '0';
  textArea.style.position = 'fixed';

  document.body.appendChild(textArea);
  textArea.focus();
  textArea.select();

  try {
    var successful = document.execCommand('copy');
    var msg = successful ? 'successful' : 'unsuccessful';
    console.log('Fallback: Copying text command was ' + msg);
  } catch (err) {
    console.error('Fallback: Oops, unable to copy', err);
  }

  document.body.removeChild(textArea);
}
function copyTextToClipboard(text) {
  if (!navigator.clipboard) {
    fallbackCopyTextToClipboard(text);
    return;
  }
  navigator.clipboard.writeText(text).then(
    function () {
      console.log('Async: Copying to clipboard was successful!');
    },
    function (err) {
      console.error('Async: Could not copy text: ', err);
    },
  );
}

function handleResponse(response) {
  if (response) {
    console.log(
      `background script sent a response: ${JSON.stringify(response)}`,
    );
    if (!modalInjected) {
      console.log('Injecting modal');
      document.body.innerHTML += `<div class="indox-modal" id="indox-summary-result-modal">
      <div class="indox-modal-bg"></div>
      <div class="indox-modal-container">
        <h1 id="indox-summary-result-header" class="indox-summary-result-header">Summarized text</h1>
        <div id="indox-summary-result-content" class="indox-summary-result-content"></div>
        <button class="indox-modal-close indox-modal-exit">Close</button>
        <div class="indox-modal-bottom-buttons">
            <button id="indox-modal-copycb" class="indox-modal-copycb">Copy to clipboard</button>
        </div>
      </div>
    </div>`;
      console.log('Injecting modal OK');
      modalInjected = true;
    }

    const synposysH = document.getElementById('indox-summary-result-content');
    const synposysCBCpy = document.getElementById('indox-modal-copycb');

    console.log('Received response: ', response);

    const modal = document.getElementById('indox-summary-result-modal');
    modal.classList.add('indox-modal-open');
    const exits = modal.querySelectorAll('.indox-modal-exit');
    exits.forEach(function (exit) {
      exit.addEventListener('click', function (event) {
        event.preventDefault();
        modal.classList.remove('indox-modal-open');
        synposysH.innerHTML = '';
      });
    });

    synposysH.innerHTML = response.synopsys;
    synposysCBCpy.onclick = function (event) {
      copyTextToClipboard(response.synopsys);
    };
  }
}

function handleError(error) {
  console.log(`Error: ${error}`);
}

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.command === 'DoSumm') {
    browser.runtime
      .sendMessage({
        command: 'DoSumm',
        data: {innerHtml: document.documentElement.innerHTML},
      })
      .then(handleResponse, handleError);
  }
});
