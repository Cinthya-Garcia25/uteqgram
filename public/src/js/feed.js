var shareImageButton = document.querySelector('#share-image-button');
var createPostArea = document.querySelector('#create-post');
var closeCreatePostModalButton = document.querySelector('#close-create-post-modal-btn');
var sharedMomentsArea = document.querySelector('#shared-moments');
var form = document.querySelector('form');
var titleInput = document.querySelector('#title');
var locationInput = document.querySelector('#location');

function openCreatePostModal() {
createPostArea.style.transform = 'translateY(0)';
if (deferredPrompt) {
deferredPrompt.prompt();

deferredPrompt.userChoice.then(function(choiceResult) {
console.log(choiceResult.outcome);

if (choiceResult.outcome === 'dismissed') {
console.log('User cancelled installation');
} else {
console.log('User added to home screen');
}
});

deferredPrompt = null;
}
}

function closeCreatePostModal() {
createPostArea.style.transform = 'translateY(100vh)';
}

shareImageButton.addEventListener('click', openCreatePostModal);

closeCreatePostModalButton.addEventListener('click', closeCreatePostModal);

function clearCards() {
while(sharedMomentsArea.hasChildNodes()) {
sharedMomentsArea.removeChild(sharedMomentsArea.lastChild);
}
}

function createCard(data) {
var cardWrapper = document.createElement('div');
cardWrapper.className = 'shared-moment-card mdl-card mdl-shadow--2dp';
var cardTitle = document.createElement('div');
cardTitle.className = 'mdl-card__title';
cardTitle.style.backgroundImage = 'url(' + (data.image || 'https://firebasestorage.googleapis.com/v0/b/uteqgram-2ea69.firebasestorage.app/o/sf-boat.jpg?alt=media&token=fad57b66-3de0-448a-9cd1-7767c02b1155') + ')';
cardTitle.style.backgroundSize = 'cover';
cardTitle.style.height = '180px';
cardWrapper.appendChild(cardTitle);
var cardTitleTextElement = document.createElement('h2');
cardTitleTextElement.style.color = 'white';
cardTitleTextElement.className = 'mdl-card__title-text';
cardTitleTextElement.textContent = data.title;
cardTitle.appendChild(cardTitleTextElement);
var cardSupportingText = document.createElement('div');
cardSupportingText.className = 'mdl-card__supporting-text';
cardSupportingText.textContent = data.location;
cardSupportingText.style.textAlign = 'center';
cardWrapper.appendChild(cardSupportingText);
componentHandler.upgradeElement(cardWrapper);
sharedMomentsArea.appendChild(cardWrapper);
}

function updateUI(data) {
clearCards();
for (var i = 0; i < data.length; i++) {
createCard(data[i]);
}
}

var url = postsUrl + '.json';
var networkDataReceived = false;

function loadPosts() {
  return fetch(url)
    .then(function(response) {
      if (!response.ok) {
        throw new Error('Could not load posts: ' + response.status);
      }
      return response.json();
    })
    .then(function(data) {
      networkDataReceived = true;
      updateUI(Object.values(data || {}));
    })
    .catch(function(error) {
      console.log('Could not refresh posts', error);
    });
}

loadPosts();

if ('caches' in window) {
caches.match(url)
.then(function(response) {
if (response) {
return response.json();
}
})
.then(function(data) {
console.log('From cache', data);
if (!networkDataReceived && data) {
var dataArray = [];
for (var key in data) {
dataArray.push(data[key]);
}
updateUI(dataArray);
}
});
}

if ('indexedDB' in window) {
readAllData('posts')
.then(function(data) {
console.log('From cache', data);
if (!networkDataReceived) {
console.log('From cache', data);
updateUI(data);
}
});
}

function showPostStatus(message) {
  var snackbar = document.querySelector('#confirmation-toast');
  snackbar.MaterialSnackbar.showSnackbar({ message: message });
}

function syncPostsInPage() {
  if (!navigator.onLine) {
    return;
  }

  syncPendingPosts()
    .then(function(count) {
      if (count > 0) {
        return loadPosts();
      }
    })
    .catch(function(error) {
      console.log('Posts remain queued for retry', error);
    });
}

window.addEventListener('online', syncPostsInPage);
window.addEventListener('pageshow', syncPostsInPage);
document.addEventListener('visibilitychange', function() {
  if (document.visibilityState === 'visible') {
    syncPostsInPage();
  }
});

form.addEventListener('submit', function(event) {
  event.preventDefault();
  if (titleInput.value.trim() === '' || locationInput.value.trim() === '') {
    alert('Please enter valid data!');
    return;
  }

  var post = {
    id: new Date().toISOString() + '-' + crypto.getRandomValues(new Uint32Array(1))[0],
    title: titleInput.value,
    location: locationInput.value,
    image: 'https://firebasestorage.googleapis.com/v0/b/uteqgram-2ea69.firebasestorage.app/o/sf-boat.jpg?alt=media&token=fad57b66-3de0-448a-9cd1-7767c02b1155'
  };

  writeData('sync-posts', post).then(function() {
    closeCreatePostModal();
    showPostStatus('Publicación guardada para sincronizar.');
    syncPostsInPage();

    if ('serviceWorker' in navigator && 'SyncManager' in window) {
      navigator.serviceWorker.ready
        .then(function(registration) {
          return registration.sync.register('sync-new-posts');
        })
        .catch(function(error) {
          console.log('Could not register background sync', error);
        });
    }
  }, function(error) {
    console.error('Could not save post locally', error);
    showPostStatus('No se pudo guardar la publicación.');
  });
});
