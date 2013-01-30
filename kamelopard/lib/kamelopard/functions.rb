# vim:ts=4:sw=4:et:smartindent:nowrap
def fly_to(p, d = 0, r = 100, m = nil)
    m = Kamelopard::Document.instance.flyto_mode if m.nil?
    Kamelopard::FlyTo.new p, :range => r, :duration => d, :mode => m
end

def get_document()
    Kamelopard::Document.instance
end

def set_flyto_mode_to(a)
    Kamelopard::Document.instance.flyto_mode = a
end

def toggle_balloon_for(p, v, options = {})
    au = Kamelopard::AnimatedUpdate.new [], options
    if ! p.kind_of? Kamelopard::Placemark and ! p.kind_of? Kamelopard::ScreenOverlay then
        raise "Can't show balloons for things that aren't Placemarks or ScreenOverlays"
    end
    a = XML::Node.new 'Change'
    # XXX This can probably be more robust, based on just the class's name
    if p.kind_of? Kamelopard::Placemark then
        b = XML::Node.new 'Placemark'
    else
        b = XML::Node.new 'ScreenOverlay'
    end
    b.attributes['targetId'] = p.kml_id
    c = XML::Node.new 'gx:balloonVisibility'
    c << XML::Node.new_text(v.to_s)
    b << c
    a << b
    au << a
end

def hide_balloon_for(p, options = {})
    toggle_balloon_for(p, 0, options)
end

def show_balloon_for(p, options = {})
    toggle_balloon_for(p, 1, options)
end

def fade_balloon_for(p, v, options = {})
    au = Kamelopard::AnimatedUpdate.new [], options
    if ! p.is_a? Kamelopard::Placemark then
        raise "Can't show balloons for things that aren't placemarks"
    end
    a = XML::Node.new 'Change'
    b = XML::Node.new 'Placemark'
    b.attributes['targetId'] = p.kml_id
    c = XML::Node.new 'color'
    c << XML::Node.new_text(v.to_s)
    b << c
    a << b
    au << a
end

def fade_out_balloon_for(p, options = {})
    fade_balloon_for(p, '00ffffff', options)
end

def fade_in_balloon_for(p, options = {})
    fade_balloon_for(p, 'ffffffff', options)
end

def point(lo, la, alt=0, mode=nil, extrude = false)
    m = ( mode.nil? ? :clampToGround : mode )
    Kamelopard::Point.new(lo, la, alt, :altitudeMode => m, :extrude => extrude)
end

def placemark(name = nil, options = {})
    Kamelopard::Placemark.new name, options
end

# Returns the KML that makes up the current Kamelopard::Document, as a string.
def get_kml
    Kamelopard::Document.instance.get_kml_document
end

def get_kml_string
    get_kml.to_s
end

def pause(p)
    Kamelopard::Wait.new p
end

def get_tour()
    Kamelopard::Document.instance.tour
end

def name_tour(a)
    Kamelopard::Document.instance.tour.name = a
end

def get_folder()
    Kamelopard::Document.instance.folders.last
end

def folder(name)
    Kamelopard::Folder.new(name)
end

def name_folder(a)
    Kamelopard::Document.instance.folder.name = a
    return Kamelopard::Document.instance.folder
end

def name_document(a)
    Kamelopard::Document.instance.name = a
    return Kamelopard::Document.instance
end

def zoom_out(dist = 1000, dur = 0, mode = nil)
    l = Kamelopard::Document.instance.tour.last_abs_view
    raise "No current position to zoom out from\n" if l.nil?
    l.range += dist
    Kamelopard::FlyTo.new(l, nil, dur, mode)
end

# Creates a list of FlyTo elements to orbit and look at a given point (center),
# at a given range (in meters), starting and ending at given angles (in
# degrees) from the center, where 0 and 360 (and -360, and 720, and -980, etc.)
# are north. To orbit clockwise, make startHeading less than endHeading.
# Otherwise, it will orbit counter-clockwise. To orbit multiple times, add or
# subtract 360 from the endHeading. The tilt argument matches the KML LookAt
# tilt argument
def orbit(center, range = 100, tilt = 0, startHeading = 0, endHeading = 360)
    fly_to Kamelopard::LookAt.new(center, startHeading, tilt, range), 2, nil

    # We want at least 5 points (arbitrarily chosen value), plus at least 5 for
    # each full revolution

    # When I tried this all in one step, ruby told me 360 / 10 = 1805. I'm sure
    # there's some reason why this is a feature and not a bug, but I'd rather
    # not look it up right now.
    num = (endHeading - startHeading).abs
    den = ((endHeading - startHeading) / 360.0).to_i.abs * 5 + 5
    step = num / den
    step = 1 if step < 1
    step = step * -1 if startHeading > endHeading

    lastval = startHeading
    startHeading.step(endHeading, step) do |theta|
        lastval = theta
        fly_to Kamelopard::LookAt.new(center, theta, tilt, range), 2, nil, 'smooth'
    end
    if lastval != endHeading then
        fly_to Kamelopard::LookAt.new(center, endHeading, tilt, range), 2, nil, 'smooth'
    end
end

def sound_cue(href, ds = nil)
    Kamelopard::SoundCue.new href, ds
end

# XXX This implementation of orbit is trying to do things the hard way, but the code might be useful for other situations where the hard way is the only possible one
# def orbit(center, range = 100, startHeading = 0, endHeading = 360)
#     p = ThreeDPointList.new()
# 
#     # Figure out how far we're going, and d
#     dist = endHeading - startHeading
# 
#     # We want at least 5 points (arbitrarily chosen value), plus at least 5 for each full revolution
#     step = (endHeading - startHeading) / ((endHeading - startHeading) / 360.0).to_i * 5 + 5
#     startHeading.step(endHeading, step) do |theta|
#         p << KMLPoint.new(
#             center.longitude + Math.cos(theta), 
#             center.latitude + Math.sin(theta), 
#             center.altitude, center.altitudeMode)
#     end
#     p << KMLPoint.new(
#         center.longitude + Math.cos(endHeading), 
#         center.latitude + Math.sin(endHeading), 
#         center.altitude, center.altitudeMode)
# 
#     p.interpolate.each do |a|
#         fly_to 
#     end
# end

def set_prefix_to(a)
    Kamelopard.id_prefix = a
end

def write_kml_to(file = 'doc.kml')
    File.open(file, 'w') do |f| f.write get_kml.to_s end
    #File.open(file, 'w') do |f| f.write get_kml.to_s.gsub(/balloonVis/, 'gx:balloonVis') end
end

def fade_overlay(ov, show, options = {})
    color = '00ffffff'
    color = 'ffffffff' if show
    if ov.is_a? String then
        id = ov  
    else
        id = ov.kml_id
    end

    a = XML::Node.new 'Change'
    b = XML::Node.new 'ScreenOverlay'
    b.attributes['targetId'] = id
    c = XML::Node.new 'color'
    c << XML::Node.new_text(color)
    b << c
    a << b
    k = Kamelopard::AnimatedUpdate.new [a], options 
end

module TelemetryProcessor
    Pi = 3.1415926535

    def TelemetryProcessor.get_heading(p)
        x1, y1, x2, y2 = [ p[1][0], p[1][1], p[2][0], p[2][1] ]

        h = Math.atan((x2-x1) / (y2-y1)) * 180 / Pi
        h = h + 180.0 if y2 < y1
        h
    end

    def TelemetryProcessor.get_dist2(x1, y1, x2, y2)
        Math.sqrt( (x2 - x1)**2 + (y2 - y1)**2).abs
    end

    def TelemetryProcessor.get_dist3(x1, y1, z1, x2, y2, z2)
        Math.sqrt( (x2 - x1)**2 + (y2 - y1)**2 + (z2 - z1)**2 ).abs
    end

    def TelemetryProcessor.get_tilt(p)
        x1, y1, z1, x2, y2, z2 = [ p[1][0], p[1][1], p[1][2], p[2][0], p[2][1], p[2][2] ]
        smoothing_factor = 10.0
        dist = get_dist3(x1, y1, z1, x2, y2, z2)
        dist = dist + 1
                # + 1 to avoid setting dist to 0, and having div-by-0 errors later
        t = Math.atan((z2 - z1) / dist) * 180 / Pi / @@options[:exaggerate]
                # the / 2.0 is just because it looked nicer that way
        90.0 + t
    end

        # roll = get_roll(last_last_lon, last_last_lat, last_lon, last_lat, lon, lat)
    def TelemetryProcessor.get_roll(p)
        x1, y1, x2, y2, x3, y3 = [ p[0][0], p[0][1], p[1][0], p[1][1], p[2][0], p[2][1] ]
        return 0 if x1.nil? or x2.nil?

        # Measure roll based on angle between P1 -> P2 and P2 -> P3. To be really
        # exact I ought to take into account altitude as well, but ... I don't want
        # to

        # Set x2, y2 as the origin
        xn1 = x1 - x2
        xn3 = x3 - x2
        yn1 = y1 - y2
        yn3 = y3 - y2
        
        # Use dot product to get the angle between the two segments
        angle = Math.acos( ((xn1 * xn3) + (yn1 * yn3)) / (get_dist2(0, 0, xn1, yn1).abs * get_dist2(0, 0, xn3, yn3).abs) ) * 180 / Pi

#    angle = angle > 90 ? 90 : angle
        @@options[:exaggerate] * (angle - 180)
    end

    def TelemetryProcessor.fix_coord(a)
        a = a - 360 if a > 180
        a = a + 360 if a < -180
        a
    end

    def TelemetryProcessor.add_flyto(p)
        # p is an array of three points, where p[0] is the earliest. Each point is itself an array of [longitude, latitude, altitude].
        p2 = TelemetryProcessor::normalize_points p
        p = p2
        heading = get_heading p
        tilt = get_tilt p
        # roll = get_roll(last_last_lon, last_last_lat, last_lon, last_lat, lon, lat)
        roll = get_roll p
        #p = Kamelopard::Point.new last_lon, last_lat, last_alt, { :altitudeMode => :absolute }
        point = Kamelopard::Point.new p[1][0], p[1][1], p[1][2], { :altitudeMode => :absolute }
        c = Kamelopard::Camera.new point, { :heading => heading, :tilt => tilt, :roll => roll, :altitudeMode => :absolute }
        f = Kamelopard::FlyTo.new c, { :duration => @@options[:pause], :mode => :smooth }
        f.comment = "#{p[1][0]} #{p[1][1]} #{p[1][2]} to #{p[2][0]} #{p[2][1]} #{p[2][2]}"
    end

    def TelemetryProcessor.options=(a)
        @@options = a
    end

    def TelemetryProcessor.normalize_points(p)
        # The whole point here is to prevent problems when you cross the poles or the dateline
        # This could have serious problems if points are really far apart, like
        # hundreds of degrees. This seems unlikely.
        lons = ((0..2).collect { |i| p[i][0] })
        lats = ((0..2).collect { |i| p[i][1] })

        lon_min, lon_max = lons.minmax
        lat_min, lat_max = lats.minmax

        if (lon_max - lon_min).abs > 200 then
            (0..2).each do |i|
                lons[i] += 360.0 if p[i][0] < 0
            end
        end

        if (lat_max - lat_min).abs > 200 then
            (0..2).each do |i|
                lats[i] += 360.0 if p[i][1] < 0
            end
        end

        return [
            [ lons[0], lats[0], p[0][2] ],
            [ lons[1], lats[1], p[1][2] ],
            [ lons[2], lats[2], p[2][2] ],
        ]
    end
end

def tour_from_points(points, options = {})
    options.merge!({
        :pause => 1,
        :exaggerate => 1
    }) { |key, old, new| old }
    TelemetryProcessor.options = options
    (0..(points.size-3)).each do |i|
        TelemetryProcessor::add_flyto points[i,3]
    end
end

def make_view_from(options = {})
    o = {}
    o.merge! options
    options.each do |k, v| o[k.to_sym] = v unless k.kind_of? Symbol
    end

    # Set defaults
    [
        [ :altitude, 0 ],
        [ :altitudeMode, :relativeToGround ],
        [ :latitude, 0 ],
        [ :longitude, 0 ],
        [ :tilt, 0 ],
        [ :heading, 0 ],
    ].each do |a|
        o[a[0]] = a[1] unless o.has_key? a[0]
    end

    p = point o[:longitude], o[:latitude], o[:altitude], o[:altitudeMode]

    if o.has_key? :roll then
        view = Kamelopard::Camera.new p
    else
        view = Kamelopard::LookAt.new p
    end

    [ :altitudeMode, :tilt, :heading, :timestamp, :timespan, :timestamp, :range, :roll, :viewerOptions ].each do |a|
        view.method("#{a.to_s}=").call(o[a]) if o.has_key? a
    end

    view
end

def screenoverlay(options = {})
    Kamelopard::ScreenOverlay.new options
end

def xy(x = 0.5, y = 0.5, xt = :fraction, yt = :fraction)
    Kamelopard::XY.new x, y, xt, yt
end

def iconstyle(href = nil, options = {})
    Kamelopard::IconStyle.new href, options
end

def labelstyle(scale = 1, options = {})
    Kamelopard::LabelStyle.new scale, options
end

def balloonstyle(text, options = {})
    Kamelopard::BalloonStyle.new text, options
end

def style(options = {})
    Kamelopard::Style.new options
end

def look_at(point = nil, options = {})
    Kamelopard::LookAt.new point, options
end

def camera(point = nil, options = {})
    Kamelopard::Camera.new point, options
end

def fly_to(view = nil, options = {})
    Kamelopard::FlyTo.new view, options
end

# k = an XML::Document containing KML
# Pulls the Placemarks from the KML document d and yields each in turn to the caller
def each_placemark(d)
    i = 0
    d.find('//kml:Placemark').each do |p|
        all_values = {}

        # These fields are part of the abstractview
        view_fields = %w{ latitude longitude heading range tilt roll altitude altitudeMode gx:altitudeMode }
        # These are other field I'm interested in
        other_fields = %w{ description name }
        all_fields = view_fields.clone
        all_fields.concat(other_fields.clone)
        all_fields.each do |k|
            if k == 'gx:altitudeMode' then
                ix = k
                next unless p.find_first('kml:altitudeMode').nil?
            else
                ix = "kml:#{k}"
            end
            r = k == "gx:altitudeMode" ? :altitudeMode : k.to_sym 
            tmp = p.find_first("descendant::#{ix}")
            next if tmp.nil?
            all_values[k == "gx:altitudeMode" ? :altitudeMode : k.to_sym ] = tmp.content
        end
        view_values = {}
        view_fields.each do |v| view_values[v.to_sym] = all_values[v.to_sym].clone if all_values.has_key? v.to_sym end
        yield make_view_from(view_values), all_values
    end
end

def make_tour_index(erb = nil, options = {})
    get_document.make_tour_index(erb, options)
end

def show_hide_balloon(p, wait, options = {})
    show_balloon_for p, options
    pause wait
    hide_balloon_for p, options
end

def cdata(text)
    XML::Node.new_cdata text.to_s
end
