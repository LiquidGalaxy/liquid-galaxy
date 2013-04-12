#--
# vim:ts=4:sw=4:et:smartindent:nowrap
#++
# Logic to create flyto paths from mathematical functions.

#--
#++
module Kamelopard

    # This function creates a hash, then uses that hash to create a point in a
    # tour, using make_view_from() among other things.
    # Arguments:
    #   points: The number of points in the series
    #   hash: Values used to create the hash, which creates the point in the
    #   series. Keys in this hash include:
    #     latitude, longitude, altitude, heading, tilt, roll, range, duration, altitudeMode, extrude
    #       These can be constant numbers, Proc objects, or Function1D objects.
    #       The latter two will be called once for each point in the series.
    #       Proc objects will be passed the number of the point they're
    #       calculating, starting with 0, and the current value of the hash
    #       created for this point. "duration" represents the time in seconds
    #       spent flying from the last point to this one.
    #     callback
    #       This Proc object, if defined, will be called after the above hash
    #       keys have been calculated. It gets passed the number of the point,
    #       and the current value of the hash for this point. It can modify and
    #       return that hash as needed.
    #     callback_value
    #       A placeholder the callback function can use. It can set it when
    #       it's called one time, and see that value when called the next time.
    #     pause
    #       The amount of time to pause after flying to this point, or nil for no pause
    #     show_placemarks
    #       If set, a placemark object will be created at this point
    #     no_flyto
    #       If set, on flyto objects will be created

    def make_function_path(points = 10, options = {})

        def val(a, b, c) # :nodoc:
            if a.kind_of? Function1D then
                return a.get_value(c)
            elsif a.kind_of? Proc then
                return a.call(b, a)
            else
                return a
            end
        end

        result_points = []

        callback_value = nil
        i = 0
        while (i <= points)
            p = i.to_f / points.to_f
            hash = {
                :latitude => val(options[:latitude], i, p),
                :longitude => val(options[:longitude], i, p),
                :altitude => val(options[:altitude], i, p),
                :heading => val(options[:heading], i, p),
                :tilt => val(options[:tilt], i, p),
                :altitudeMode => val(options[:altitudeMode], i, p),
                :extrude => val(options[:extrude], i, p),
            }

            hash[:show_placemarks] = options[:show_placemarks] if options.has_key? :show_placemarks
            hash[:roll] = val(options[:roll], i, p) if options.has_key? :roll
            hash[:range] = val(options[:range], i, p) if options.has_key? :range
            hash[:pause] = val(options[:pause], i, p) if options.has_key? :pause

            if hash.has_key? :duration
                duration = val(options[:duration], i, p)
            else
                duration = (i == 0 ? 0 : 2)
            end

            hash[:callback_value] = callback_value unless callback_value.nil?
            tmp = yield(i, hash)
            hash = tmp unless tmp.nil?
            #hash = options[:callback].call(i, hash) if options.has_key? :callback
            callback_value = hash[:callback_value] if hash.has_key? :callback_value

            v = make_view_from(hash)
            p = point(v.longitude, v.latitude, v.altitude, hash[:altitudeMode], hash[:extrude])
            get_folder << placemark(i.to_s, :geometry => p) if hash.has_key? :show_placemarks
            fly_to v, :duration => duration , :mode => :smooth unless hash.has_key? :no_flyto
            result_points << v

            pause hash[:pause] if hash.has_key? :pause

            i = i + 1
        end
        result_points
    end

end
