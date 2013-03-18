# vim:ts=4:sw=4:et:smartindent:nowrap

# Handles creation of paths based on functions

module Kamelopard

    def make_function_path(duration = 1, steps = 10, options = {})

        def val(a, b)
            if a.kind_of? Function1D then
                return a.get_value(b)
            else
                return a
            end
        end

        i = 0
        while (i < duration)
  # Given a hash of values, this creates an AbstractView object. Possible
  # values in the hash are :latitude, :longitude, :altitude, :altitudeMode,
  # :tilt, :heading, :roll, and :range. If the hash specifies :roll, a Camera
  # object will result; otherwise, a LookAt object will result. Specifying both
  # :roll and :range will still result in a Camera object, and the :range
  # option will be ignored. :roll and :range have no default; all other values
  # default to 0 except :altitudeMode, which defaults to :relativeToGround
  # def make_view_from(options = {})
            opts = {
                :latitude => val(options[:latitude], i),
                :longitude => val(options[:longitude], i),
                :altitude => val(options[:altitude], i),
                :heading => val(options[:heading], i),
                :tilt => val(options[:tilt], i),
                :roll => val(options[:roll], i),
            }

            v = make_view_from(opts)
            get_folder << placemark(i.to_s, :geometry => point(v.longitude, v.latitude))
            fly_to v, :duration => (i == 0 ? 0 : 2) , :mode => :smooth
            i = i + duration.to_f / steps.to_f
        end
    end

end
