<?php
# Copyright 2010 Google Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if (isset($_REQUEST['planet']) and ($_REQUEST['planet'] != '')) { 
  $handle = @fopen("/tmp/query_php.txt", "w");
  if ($handle) {
    fwrite($handle, "planet=" . $_REQUEST['planet']);
  }
  exec('/lg/chown_tmp_query');
  echo "Going to " . ucwords($_REQUEST['planet']);
} elseif (isset($_REQUEST['query']) and ($_REQUEST['query'] == 'relaunch')) {
  exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-sudo-bg service lxdm restart');
  echo "Attempting relaunch";
} elseif (isset($_REQUEST['query']) and (preg_match('/^sview(.*)?/', $_REQUEST['query']))) {
  $action = split('-', $_REQUEST['query']);
  if (($action[0] == $_REQUEST['query']) and !isset($action[1])) {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/streetview');
    echo "Attempting to load StreetView";
  } elseif ($action[1] == 'fwd') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/streetview fwd');
    echo "StreetView " . $action[1];
  } elseif ($action[1] == 'rev') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/streetview rev');
    echo "StreetView  " . $action[1];
  } elseif ($action[1] == 'left') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/streetview left');
    echo "StreetView  " . $action[1];
  } elseif ($action[1] == 'right') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/streetview right');
    echo "StreetView  " . $action[1];
  } elseif ($action[1] == 'un') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/streetview unload');
    echo "StreetView  " . $action[1];
  } else {
    echo "Unknown command";
  } 
  unset($action);
} elseif (isset($_REQUEST['query']) and (preg_match('/^mpctl(.*)?/', $_REQUEST['query']))) {
  $action = split('-', $_REQUEST['query']);
  if (($action[0] == $_REQUEST['query']) and !isset($action[1])) {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/lg-run-bg /home/lg/bin/launchmplayer 3 /home/lg/media/videos/nature.mp4');
    echo "Attempting to launch MPlayer";
  } elseif ($action[1] == 'prev') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/mp-control pt_step -1');
    echo "MPlayer " . $action[1];
  } elseif ($action[1] == 'rev') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/mp-control master seek -15');
    echo "MPlayer " . $action[1];
  } elseif ($action[1] == 'fwd') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/mp-control master seek +15');
    echo "MPlayer " . $action[1];
  } elseif ($action[1] == 'next') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/mp-control pt_step +1');
    echo "MPlayer " . $action[1];
  } elseif ($action[1] == 'pause') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/mp-control pause');
    echo "MPlayer " . $action[1];
  } elseif ($action[1] == 'stop') {
    exec('/usr/bin/sudo -H -u lg /home/lg/bin/mp-control stop');
    echo "MPlayer " . $action[1];
  } else {
    echo "Unknown command";
  } 
  unset($action);
} elseif (isset($_REQUEST['query']) and ($_REQUEST['query'] != '') and isset($_REQUEST['name']) and ($_REQUEST['name'] != '')) {
  $handle = @fopen("/tmp/query_php.txt", "w");
  if ($handle) {
    fwrite($handle, $_REQUEST['query']);
  }
  exec('/lg/chown_tmp_query');
  echo "Going to " . $_REQUEST['name'];
} elseif (isset($_REQUEST['layer']) and ($_REQUEST['layer'] != '') and isset($_REQUEST['name']) and ($_REQUEST['name'] != '')) {

  # Do something awesome to add or remove "layer" from kml.txt.
  $layerfilename = "kmls.txt";
  $foundlayer = FALSE;

  # These flags require PHP 5.
  $layerarray = file($layerfilename, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

  foreach ($layerarray as $linenumber => $line) {
    # echo $linenumber . PHP_EOL . $line; #debug
    if ($line == $_REQUEST['layer']) {
      echo("Disabling layer " . $_REQUEST['name']);
      unset($layerarray[$linenumber]);
      $foundlayer = TRUE;
    }
  }
  unset($line);

  # If we didn't find the layer in the file, add it.
  if (! $foundlayer) {
    $layerarray[] = $_REQUEST['layer'];
    echo "Enabling layer " . $_REQUEST['name'];
  }

  # Write the array back to the file.
  # This raises some obvious concurrency concerns since there's no file locking.
  $handle = @fopen($layerfilename, "wb");
  if ($handle) {
    fwrite($handle, implode(PHP_EOL, $layerarray));
  }
  fclose($handle);
}
?>
