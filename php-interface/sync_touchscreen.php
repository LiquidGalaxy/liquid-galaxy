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


include "sync_inc.php";


function writeKmlListFile($kml_data_file, $kml_list) {
  $handle = @fopen($kml_data_file, "w");
  if ($handle) {
    foreach ($kml_list as $md5 => $kml_url) {
      fwrite($handle, $kml_url . "\n");
    }
    echo "Loading KMLs";
  }
}


function syncTouchscreenChoices($kml_data_file){
  $touch_kml = trim(getOrDefault('touch_kml', ''));
  $touch_action = getOrDefault('touch_action', '');
  $kml_url_list = getKmlListUrls($kml_data_file);
  
  # If delete action, remove element from array
  if ($touch_action == 'delete' && in_array($touch_kml, $kml_url_list)) {
    $index = array_search($touch_kml, $kml_url_list);
    unset($kml_url_list[$index]);
    writeKmlListFile($kml_data_file, $kml_url_list); 
  }
  # If add action, and url is new, add element to array
  else if ($touch_action == 'add'  && !in_array($touch_kml, $kml_url_list)) {
    $kml_url_list[md5($touch_kml)] = $touch_kml;
    writeKmlListFile($kml_data_file, $kml_url_list); 
  }
}


$kml_data_file = 'kmls.txt';

if (!file_exists($kml_data_file)) {
  echo "missing file: $kml_data_file";
  exit(1);
}

if (isset($_REQUEST['touch_kml']) || isset($_REQUEST['touch_action'])) {
  syncTouchscreenChoices($kml_data_file);
}

?>
