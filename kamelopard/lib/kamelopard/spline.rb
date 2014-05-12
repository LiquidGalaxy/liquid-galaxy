# vim:ts=4:sw=4:et:smartindent:nowrap
require 'bundler/setup'
require 'matrix'

# Basic support for splines
module Kamelopard
    module Functions
        class SplineFunction < FunctionMultiDim
            attr_reader :control_points, :total_dur, :tension

            def initialize(ndims, tension = 0.5)
                @ndims = ndims
                @control_points = []
                @total_dur = 0
                @tension = tension
                super()
            end

            # Adds a new control point. :dur is a way of indicating the
            # duration of the journey from the last point to this one, and is
            # ignored for the first control point in the spline. Values for
            # :dur are in whatever units the user wants; a spline with three
            # control points with durations of 0, 10, and 20 will be identical
            # to one with durations of 0, 1, and 2.
            def add_control_point(point, dur)
                @total_dur = @total_dur + dur if @control_points.size > 0
                @control_points << [ point, dur ]
            end

            def run_function(x)
                # X will be between 0 and 1
                # Find which control points I should am using for the point in
                # question

                dur = 0
                last_dur = 0
                cur_i = 0
                u = 0
                @control_points.each_index do |i|
                    next if i == 0
                    cur_i = i
                    last_dur = dur
                    if 1.0 * (dur + @control_points[i][1]) / @total_dur >= x then
                        # I've found the correct two control points: cp[i-1] and cp[i]
                        # u is the point on the interval between the two control points
                        # that we're interested in. 0 would be the first control point,
                        # and 1 the second
                        u = (x * @total_dur - dur) / @control_points[i][1]
                        break
                    end
                    dur = dur + @control_points[i][1]
                end

                # http://www.cs.cmu.edu/~462/projects/assn2/assn2/catmullRom.pdf

                # cp = control points. cur_i will be at least 1
                # I need two control points on either side of this part of the
                # spline. If they don't exist, duplicate the endpoints of the
                # control points.
                cp1 = @control_points[cur_i-1][0]
                cp2 = @control_points[cur_i][0]
                if cur_i == 1 then
                    cpt1 = cp1
                else
                    cpt1 = @control_points[cur_i-2][0]
                end
                if cur_i >= @control_points.size - 1 then
                    cpt2 = cp2
                else
                    cpt2 = @control_points[cur_i+1][0]
                end

                # Can't just say Matrix[cp], because that adds an extra
                # dimension to the matrix, somehow.
                cps = Matrix[cpt1, cp1, cp2, cpt2]

                t = @tension
                h = Matrix[
                    [ 0, 1, 0, 0 ],
                    [ -t, 0, t, 0 ],
                    [ 2*t, t-3, 3-2*t, -t ],
                    [ -t, 2-t, t-2, t]
                ]

                p = Matrix[[1, u, u**2, u**3]] * h * cps
                return p.row(0)
            end
        end   ## End of SplineFunction class

        ## Spline that takes Points as control points
        class PointSplineFunction < SplineFunction
            def initialize(tension = 0.5)
                @fields = [:longitude, :latitude, :altitude]
                super(@fields.length, tension)
            end

            def add_control_point(point, dur)
                super((
                    @fields.collect { |f|
                        begin
                            point.method(f).call
                        rescue
                            0
                        end
                     }), dur)
            end

            def run_function(x)
                res = super(x)
                return point(h[0], h[1], h[2], @first_control_point.altitudeMode)
            end
        end

        ## Spline that takes LookAts or Cameras as control points
        class ViewSplineFunction < SplineFunction
            attr_reader :viewtype, :first_control_point

            def initialize(tension = 0.5)
                @first_control_point = nil
                @fields = [:latitude, :longitude, :altitude, :heading, :tilt, :roll, :range]
                super(@fields.length, tension)
            end

            def add_control_point(point, dur)
                raise "Control points for ViewSplines must be AbstractViews" unless point.kind_of? AbstractView
                if @first_control_point.nil?
                    @first_control_point = point
                elsif point.kind_of? @first_control_point.class
                else
                    raise "Control points for ViewSplines must be the same class type (#{@first_control_point.class} vs #{point.class})"
                end

                super((
                    @fields.collect { |f|
                        begin
                            point.method(f).call
                        rescue
                            0
                        end
                     }), dur)
            end

            def run_function(x)
                res = super(x)
                h = {}
                @fields.each_index do |i|
                    h[@fields[i]] = res[i]
                end

                if @first_control_point.is_a? Kamelopard::LookAt
                    h.delete :roll
                elsif @first_control_point.is_a? Kamelopard::Camera
                    h.delete :range
                else
                    raise "Unknown control point type #{@first_control_point.class.name}. ViewSplines only support LookAts and Cameras"
                end

                return make_view_from h
            end
        end  ## end of ViewSpline class
    end   ## End of Function module
end   ## End of Kamelopard module
