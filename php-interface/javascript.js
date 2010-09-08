/* Copyright 2010 Google Inc.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * @fileoverview Handles AJAX requests and display restrictions for the 
 * Liquid Galaxy touchscreen that is run via a webserver.
 */

// To prevent users from causing right menu windows showing up
// we disable the ability to right click using the example
// code provided by Reconn.us at the following URL
//  http://www.reconn.us/content/view/36/45/
var isNS = (navigator.appName == 'Netscape') ? 1 : 0;
if (navigator.appName == 'Netscape') {
  document.captureEvents(Event.MOUSEDOWN || Event.MOUSEUP);
}

function mischandler() {
  return false;
}

function mousehandler(e) {
  var myevent = (isNS) ? e : event;
  var eventbutton = (isNS) ? myevent.which : myevent.button;
  if ((eventbutton == 2) || (eventbutton == 3)) return false;
}

document.oncontextmenu = mischandler;
document.onmousedown = mousehandler;
document.onmouseup = mousehandler;

// To prevent users from causing images to start moving
// around as they're trying to interact with the touchscreen
// we disable image dragging using the example code provided
// by Redips at the following URL
// http://www.redips.net/firefox/disable-image-dragging/
window.onload = function (e) {
  var evt = e || window.event;
  var imgs;
  if (evt.preventDefault) {
    imgs = document.getElementsByTagName('img');
    for (var i = 0; i < imgs.length; i++) {
      imgs[i].onmousedown = disableDragging;
    }
  }
}

function disableDragging(e) {
  e.preventDefault();
}

function createRequest() {
  if (window.XMLHttpRequest) {
    var req = new XMLHttpRequest();
    return req;
  }
}

function submitRequest(url) {
  var req = createRequest();
  req.onreadystatechange = function() {
    if (req.readyState == 4) {
      if (req.status == 200) {
        document.getElementById('status').innerHTML = req.responseText;
      }
    }
  }
  req.open('GET', url, true);
  req.send(null);
}

function changePlanet(planet) {
  submitRequest('change.php?planet=' + planet);
  showAndHideStatus();
}

function changeQuery(query, name) {
  submitRequest('change.php?query=' + query + '&name=' + name);
  showAndHideStatus();
}

function showAndHideStatus() {
  var status = document.getElementById('status');
  status.style.opacity = 1;
  window.setTimeout('document.getElementById("status").style.opacity = 0;', 2000);
}

function setCaret() {
  var keyboardEntry = document.getElementById('keyboardEntry');
  keyboardEntry.focus();
}

function keyEntry(key) {
  var keyboardEntry = document.getElementById('keyboardEntry');
  keyboardEntry.value = keyboardEntry.value + key;
  setCaret();
}

function backspaceKey() {
  var keyboardEntry = document.getElementById('keyboardEntry');
  keyboardEntry.value =
    keyboardEntry.value.substr(0, keyboardEntry.value.length - 1);
  setCaret();
}

function clearKey() {
  var keyboardEntry = document.getElementById('keyboardEntry');
  keyboardEntry.value = '';
  setCaret();
}

function searchKey() {
  var keyboardEntry = document.getElementById('keyboardEntry');
  changeQuery('search=' + keyboardEntry.value, keyboardEntry.value);
  setCaret();
}
