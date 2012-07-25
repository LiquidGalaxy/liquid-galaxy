<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
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

/*
Functions for generating NLCs to update slave lg machines
*/

function getSyncLists($client_kmls, $kml_data_file) {
  $new_kml_list = getKmlListUrls($kml_data_file);
  $add_list = array_diff_key($new_kml_list, $client_kmls);
  $delete_list = array_diff_key($client_kmls, $new_kml_list);
  $keep_list = array_intersect_key($client_kmls, $new_kml_list);
  return array( $add_list, $delete_list, $keep_list);
}


function createNLList($url_list) {
  $output = '';
  if (count($url_list) > 0) {
    $output .= '<Create><Document targetId="master">';
    foreach ($url_list as $md5 => $url) {
      $nl = '
          <NetworkLink id="%1$s">
            <name>%2$s</name>
            <Link><href>%3$s</href></Link>
          </NetworkLink>';
      $output .= sprintf($nl, $md5, basename($url), $url);
    }
    $output .= "\n    </Document></Create>";
  }
  return $output;
}


function deleteNLList($url_list) {
  $output = '';
  if (count($url_list) > 0) {
    $output .= '<Delete>';
    foreach ($url_list as $md5 => $url) {
      $nl = '
          <NetworkLink targetId="%1$s" />';
      $output .= sprintf($nl, $md5);
    }
    $output .= "\n    </Delete>";
  }
  return $output;
}
 

function makeNLCUpdate($add_urls, $del_urls, $keep_urls, $timestamp, $timeout = -1) {
  $add_nls = createNLList($add_urls);
  $del_nls = deleteNLList($del_urls, 'Delete');
  
  $md5_list = array_keys(array_merge($keep_urls, $add_urls));
  $md5_list = implode(',', $md5_list);
  
  global $master_kml;
  
  $kml = "
<NetworkLinkControl>
  <minRefreshPeriod>1</minRefreshPeriod>
  <maxSessionLength>-1</maxSessionLength>
  <cookie><![CDATA[t=%s&client_kmls=%s]]></cookie> 
  <Update>
    <targetHref>%s</targetHref>
    %s
    %s
  </Update>        
</NetworkLinkControl>\n";

  return sprintf($kml, $timestamp, $md5_list, $master_kml, $add_nls, $del_nls);
}


function outputKML($data) {
  echo $data;
}


function createNLC($kml_data_file, $connection_timeout = 60){
  $client_timestamp = getOrDefault('t', 0);
  $client_kmls = getOrDefault('client_kmls', '');
  if ($client_kmls != '') {
    $client_kml_list = array_fill_keys(explode(',', $client_kmls), '');
  }
  else {
    $client_kml_list = array();
  }

  #keep connection alive for $connection_timeout seconds
  $start = microtime(true);
  set_time_limit($connection_timeout + 1);
  $new_data = False;
  for ($i = 0; $i < $connection_timeout; $i += 1) {
    clearstatcache();
    $file_mod = filemtime($kml_data_file);
    echo "<!--" . $file_mod . "-->\n";
    if ($file_mod > $client_timestamp) {
      $add_del_keep = getSyncLists($client_kml_list, $kml_data_file);
      $kml = makeNLCUpdate($add_del_keep[0], $add_del_keep[1], $add_del_keep[2], $file_mod, $connection_timeout); 
      outputKML($kml);
      $new_data = True;
      echo "</kml>";
      exit(0);
      #need to break the loop. 
      $i = $connection_timeout;
    }
    time_sleep_until($start + $i + 1);
  }
  #Make sure to provide the cookie if no changes detected. Else NL loses cookie and dup. features

  if (!$new_data) {
    $kml = "
  <NetworkLinkControl>
    <minRefreshPeriod>1</minRefreshPeriod>
    <maxSessionLength>-1</maxSessionLength>
    <cookie><![CDATA[t=%s&client_kmls=%s]]></cookie> 
  </NetworkLinkControl>\n";
    echo sprintf($kml, $client_timestamp, $client_kmls);
  }

}


### Allow arbitrary kml list to be selected by tag
$kml_tag = preg_replace( '/[^a-zA-Z0-9-_]/', '', getOrDefault('tag', '') );
$kml_tag_separator = (!empty( $kml_tag )) ? '-' : '';
$kml_data_file = "kmls" . $kml_tag_separator . $kml_tag . ".txt";

$CONNECT_TIMEOUT = 3;

#LG server
$master_kml = 'http://lg1:81/kml/master.kml';


if (!file_exists($kml_data_file)) {
  echo "missing file: $kml_data_file";
  exit(1);
}

#If timestamp and kml md5s present, create NLC
createNLC($kml_data_file, 10);

?></kml>
