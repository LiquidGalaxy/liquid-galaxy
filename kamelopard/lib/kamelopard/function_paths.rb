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
    #     Any option suitable for the make_view_from() function
    #       These can be constant numbers, Proc objects, or Function1D objects.
    #       The latter two will be called once for each point in the series.
    #       Proc objects will be passed the number of the point they're
    #       calculating, starting with 0, and the current value of the hash
    #       created for this point. "duration" represents the time in seconds
    #       spent flying from the last point to this one.
    #     callback
    #       This Proc object, if defined, will be called after the other hash
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
    #     multidim
    #       An array of hashes. Each array element is an array, containing two
    #       values. The first is associated with a FunctionMultiDim class
    #       representing a multidimensional function. The second is an array of
    #       symbols and nils. Valid symbols include any of the possible
    #       make_function_path options, except :multidim. At execution, the
    #       FunctionMultiDim will be evaluated, returning an array of values.
    #       The symbols in the :vals array will be assigned the returned value
    #       corresponding to their position in the :vals array. For instance,
    #       assume the following :multidim argument
    #          [ { :func => myFunc, :vals = [:latitude, :longitude, nil, :altitude]} ]
    #       When myFunc is evaluated, assume it returns [1, 2, 3, 4, 5]. Thus,
    #       :latitude will be 1, :longitude 2, and so on. Because :vals[2] is
    #       nil, the corresponding element in the results of myFunc will be
    #       ignored. Also, given that :vals contains four values whereas myFunc
    #       returned 5, the unallocated final myFunc value will also be
    #       ignored.
    #    NOTE ON PROCESSING ORDER
    #       Individually specified hash options are processed first, followed by
    #       :multidim. So hash options included directly as
    #       well as in a :multidim :vals array will take the value from
    #       :multidim. make_function_path yields to code blocks last, after all
    #       other assignment.
    def make_function_path(points = 10, options = {})

        def val(a, b, c) # :nodoc:
            if a.kind_of? Function then
                return a.get_value(c)
            elsif a.kind_of? Proc then
                return a.call(b, a)
            else
                return a
            end
        end

        views = []
        placemarks = []

        callback_value = nil
        i = 0
        while (i <= points)
            p = i.to_f / points.to_f
            hash = {}
            [ :latitude, :longitude, :altitude, :heading,
              :tilt, :altitudeMode, :extrude, :when,
              :roll, :range, :pause, :begin, :end].each do |k|
                if options.has_key? k then
                    hash[k] = val(options[k], i, p)
                end
            end

            hash[:show_placemarks] = options[:show_placemarks] if options.has_key? :show_placemarks
            #hash[:roll] = val(options[:roll], i, p) if options.has_key? :roll
            #hash[:range] = val(options[:range], i, p) if options.has_key? :range
            #hash[:pause] = val(options[:pause], i, p) if options.has_key? :pause

            if options.has_key? :duration
                duration = val(options[:duration], i, p)
            else
                duration = (i == 0 ? 0 : 2)
            end
            hash[:duration] = duration

            if options.has_key? :multidim then
                options[:multidim].each do |md|
                    r = val(md[0], i, p)
                    md[1].each_index do |ind|
                        hash[md[1][ind]] = r[0, ind] unless md[1][ind].nil?
                    end
                end
            end

            hash[:callback_value] = callback_value unless callback_value.nil?

            begin
                tmp = yield(i, hash)
                hash = tmp unless tmp.nil?
            rescue LocalJumpError
                # Don't do anything; there's no block to yield to
            end
            #hash = options[:callback].call(i, hash) if options.has_key? :callback
            callback_value = hash[:callback_value] if hash.has_key? :callback_value

            v = make_view_from(hash)
            p = point(v.longitude, v.latitude, v.altitude, hash[:altitudeMode], hash[:extrude])
            # XXX Should I add the view's timestamp / timespan, if it exists, to the placemark?
            pl = placemark(i.to_s, :geometry => p)
            pl.abstractView = v
            get_folder << pl if hash.has_key? :show_placemarks
            fly_to v, :duration => duration , :mode => :smooth unless hash.has_key? :no_flyto
            views << v
            placemarks << pl

            pause hash[:pause] if hash.has_key? :pause

            i = i + 1
        end
        [views, placemarks]
    end

end

## Example
#make_function_path(10,
#    :latitude => Line.interpolate(38.8, 40.3),
#    :altitude => Line.interpolate(10000, 2000),
#    :heading => Line.interpolate(0, 90),
#    :tilt => Line.interpolate(40.0, 90),
#    :roll => 0,
#    :show_placemarks => 1,
#    :duration => Quadratic.interpolate(2.0, 4.0, 0.0, 1.0),
#) do |a, v|
#    puts "callback here"
#    if v.has_key? :callback_value then
#        v[:callback_value] += 1
#    else
#        v[:pause] = 0.01
#        v[:callback_value] = 1
#    end
#    puts v[:callback_value]
#    v
#end
