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

$queries = array('layers' => array(), 'earth' => array(), 'moon' => array(), 'mars' => array());
$delimiter = "@";
$handle = @fopen("queries.txt", "r");
if ($handle) {
  while (!feof($handle)) {
    $buffer = fgets($handle);
    if (substr_count($buffer, $delimiter) == 2) {
      list($planet, $name, $query) = explode($delimiter, $buffer);
      $queries[$planet][] = array(trim($name), trim($query));
    }
  }
  fclose($handle);
}

#LG server
$KML_SYS_PATH = '/var/www/kml/';
$KML_SERVER_BASE = 'http://lg1:81/kml/';

$FILE_FILTER = '*.km[l|z]';

$kml_files = array('earth' => array(), 'moon' => array(), 'mars' => array(), 'layers' => array());
foreach (array_keys($kml_files) as $planet) {
  $planet_kml_path = $KML_SYS_PATH . $planet . "/" . $FILE_FILTER;
  foreach (glob($planet_kml_path) as $file) {
    $basename = str_replace('_', ' ', explode('.', basename($file)));
    $kml_files[$planet][$basename[0]] = str_replace($KML_SYS_PATH, $KML_SERVER_BASE, $file);
  }
}

$kml_data_file = 'kmls.txt';

$existing_kml_url_list = array_values(getKmlListUrls($kml_data_file));

?>
<html>
  <head>
    <link rel="stylesheet" type="text/css" href="style.css" />
    <script type="text/javascript" src="javascript.js"></script>

    <script type="text/javascript">       
      function clearKmls() {
        showAndHideStatus();
        <?php  $i = 0; foreach (array_values($queries['layers']) as $layer) { ?>
          submitRequest('sync_touchscreen.php?touch_action=delete&touch_kml=<?php echo $layer[1]; ?>');
          document.getElementById('kml_<?php echo $i; ?>').className='kml_off';
        <?php ++$i; } ?>
        showAndHideStatus();
      }
    </script>

    <title>Liquid Galaxy</title>
  </head>
  <body onload="noneExpand('e_earth', 'e_layers', 'e_moon', 'e_mars', 'e_keyboard');">
    <div class="touchscreen">
      <div id="status"></div>
      <div class="earth">
        <div class="title" onclick="changePlanet('earth');  toggleExpand('e_earth', 'e_layers', 'e_moon', 'e_mars', 'e_keyboard');">Earth</div>
        <img onclick="changePlanet('earth');  toggleExpand('e_earth', 'e_layers', 'e_moon', 'e_mars', 'e_keyboard');" src="earth.png" />
        <div class="expand_inactive" id="e_earth">
          <?php foreach (array_values($queries['earth']) as $query) { ?>
            <div class="location" onclick="changeQuery('<?php echo $query[1]; ?>', '<?php echo $query[0]; ?>');"><?php echo $query[0]; ?></div>
          <?php } ?>
        </div>
      </div>
      <div class="moon">
        <div class="title" onclick="changePlanet('moon'); clearKmls(); toggleExpand('e_moon', 'e_earth', 'e_layers','e_mars', 'e_keyboard');">Moon</div>
        <img onclick="changePlanet('moon'); clearKmls(); toggleExpand('e_moon', 'e_earth', 'e_layers','e_mars', 'e_keyboard');" src="moon.png" />
        <div class="expand_inactive" id="e_moon">
          <?php foreach (array_values($queries['moon']) as $query) { ?>
            <div class="location" onclick="changeQuery('<?php echo $query[1]; ?>', '<?php echo $query[0]; ?>');"><?php echo $query[0]; ?></div>
          <?php } ?>
        </div>
      </div>
      <div class="mars">
        <div class="title" onclick="changePlanet('mars'); clearKmls(); toggleExpand('e_mars', 'e_earth', 'e_layers','e_moon', 'e_keyboard');">Mars</div>
        <img onclick="changePlanet('mars'); clearKmls(); toggleExpand('e_mars', 'e_earth', 'e_layers','e_moon', 'e_keyboard'); "  src="mars.png" />
        <div class="expand_inactive" id="e_mars">
          <?php foreach (array_values($queries['mars']) as $query) { ?>
            <div class="location" onclick="changeQuery('<?php echo $query[1]; ?>', '<?php echo $query[0]; ?>');"><?php echo $query[0]; ?></div>
          <?php } ?>
        </div>
      </div>
      <div class="layers">
        <div class="title" onclick="changePlanet('earth');  toggleExpand('e_layers', 'e_earth', 'e_mars','e_moon', 'e_keyboard');">Layers</div>
        <img onclick="changePlanet('earth'); toggleExpand('e_layers', 'e_earth', 'e_moon', 'e_mars', 'e_keyboard');" src="layers.png" />
        <div class="expand_inactive" id="e_layers">
          <?php $i = 0; foreach (array_values($queries['layers']) as $layer) { ?>
            <div id="kml_<?php echo $i; ?>" class="<?php echo (in_array($layer[1], $existing_kml_url_list)) ? "kml_on" : "kml_off"; ?>" onclick="toggleKml(this, '<?php echo $layer[1]; ?>');"><?php echo $layer[0]; ?></div>
          <?php ++$i; } ?>
        </div>
      </div>
      <div class="keyboard">
        <div class="title" onclick="toggleExpand('e_keyboard', 'e_earth', 'e_mars','e_moon', 'e_layers');">&nbsp;</div>
        <img onclick="toggleExpand('e_keyboard', 'e_earth', 'e_mars','e_moon', 'e_layers');" src="keyboard.png" />
        <div class="expand_inactive" id="e_keyboard">
          <div class="keyboardRow1">
            <input class="keyboardEntry" id="keyboardEntry" name="keyboardEntry" type="text" value="" onkeypress="enterKeySubmit(event);" />
            <div class="keyboardKey keyboardKeyClear" onclick='clearKey();'>Clear</div>
            <div class="keyboardKey keyboardKeySearch" onclick='searchKey();'>Search</div>
          </div>
          <div class="keyboardRow2">
            <?php foreach (array('1','2','3','4','5','6','7','8','9','0') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
            <div class="keyboardKey keyboardKeyBackspace" onclick='backspaceKey();'>Bksp</div>
          </div>
          <div class="keyboardRow3">
            <?php foreach (array('Q','W','E','R','T','Y','U','I','O','P') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
          </div>
          <div class="keyboardRow4">
            <?php foreach (array('A','S','D','F','G','H','J','K','L') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
          </div>
          <div class="keyboardRow5">
            <?php foreach (array('Z','X','C','V','B','N','M',',','.') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
          </div>
          <div class="keyboardRow6">
            <div class="keyboardKey keyboardKeySpace" onclick='keyEntry(" ");'></div>
          </div>
        </div>
      </div>
      <div class="welcome" onclick="noneExpand('e_earth', 'e_layers', 'e_moon', 'e_mars', 'e_keyboard');">
        Welcome to the Liquid Galaxy by Google
      </div>
      <!--//
      <div class="ctlpanel">
        <div class="appctl">
          <div class="title" onclick="changeQuery('sview', 'StreetView');">StreetView</div>
          <img onclick="changeQuery('sview', 'StreetView');" src="pegman.png" />
          <div class="ctlbutton" onclick="changeQuery('sview-left', 'SV LEFT');">LEFT</div>
          <div class="ctlbutton" onclick="changeQuery('sview-rev', 'SV REV');">REV</div>
          <div class="ctlbutton" onclick="changeQuery('sview-fwd', 'SV FWD');">FWD</div>
          <div class="ctlbutton" onclick="changeQuery('sview-right', 'SV RIGHT');">RIGHT</div>
          <div class="ctlbutton" onclick="changeQuery('sview-un', 'SV UNLOAD');">Unload</div>
        </div>
        <div class="appctl">
          <div class="title" onclick="changeQuery('mpctl-launch', 'MPlayer');">MPlayer</div>
          <img onclick="changeQuery('mpctl', 'MPlayer');" src="mplayer.png" />
          <div class="ctlbutton" onclick="changeQuery('mpctl-prev', 'MP PREV');">PREV</div>
          <div class="ctlbutton" onclick="changeQuery('mpctl-rev', 'MP REV');">REV</div>
          <div class="ctlbutton" onclick="changeQuery('mpctl-fwd', 'MP FWD');">FWD</div>
          <div class="ctlbutton" onclick="changeQuery('mpctl-next', 'MP NEXT');">NEXT</div>
          <div class="ctlbutton" onclick="changeQuery('mpctl-pause', 'MP PAUSE');">PAUSE</div>
          <div class="ctlbutton" onclick="changeQuery('mpctl-stop', 'MP STOP');">STOP</div>
        </div>
      </div>
      //-->
      <div class="relaunch">
        <div class="location" onclick="changeQuery('relaunch', 'Relaunch');">Relaunch</div>
      </div>
    </div>
  </body>
</html>
