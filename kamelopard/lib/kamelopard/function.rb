#--
# vim:ts=4:sw=4:et:smartindent:nowrap
#++
# Describes functions that can be calculated to create flight paths

require 'bundler/setup'
require 'matrix'

#--
#++
module Kamelopard
    
    # Classes to manage functions, which can be interpolated into flight paths
    # and other things
    module Functions

        # Abstract class representing a one-dimensional function
        class Function
            # min and max describe the function's domain. Values passed to
            # get_value will only range from 0 to 1; the actual value
            # calculated will be mapped to a percentage of that domain.
            attr_reader :min, :max, :start, :end
            
            # Another function this one is composed with, or appended to the end of this one
            attr_reader :compose, :append

            attr_accessor :verbose

            def initialize(min = 0, max = 1)
                @min = min
                @max = max
                @verbose = false
            end

            def max=(m)
                raise "Cannot have a nil domain maximum" if m.nil?
                @max = m
            end

            def min=(m)
                raise "Cannot have a nil domain minimum" if m.nil?
                @min = m
            end

            def compose=(f)
                raise "Can only compose another function" unless f.kind_of? Function or f.nil?
                @compose = f
            end

            def get_value(x)
                raise "Value #{x} must be between 0 and 1" if (x.to_f > 1 or x.to_f < 0)
                val = x * (max - min) + min
                if @compose.nil? then
                    return run_function(val)
                else
                    return run_function(@compose.get_value(val))
                end
            end

            #def append(f)
            #    raise "Can only append another one-dimensional function" unless f.kind_of? Function or f.nil?
            #    print STDERR "WARNING: append() isn't actually implemented" unless f.nil?
            #    # XXX
            #    # Gotta implement this. The idea is to have one function for the first
            #    # part of a domain, and another for the next. The domain of the second
            #    # function will begin with the end of the last function.
            #    # Perhaps allow two methods. One just appends the two; the second
            #    # smooths things somewhat by adding to the result of the second the
            #    # value of the first at the end of its domain.
            #    @append = f
            #end

            def run_function(x)
                raise "Override this method before calling it, please"
            end

            def self.interpolate(a, b)
                # Creates a new Function object between points A and B
                raise "Override this method before calling it, please"
            end
        end   ## End of Function class

        # get_value and run_function return a single scalar value 
        class Function1D < Function
            def compose=(f)
                raise "Can only compose another one-dimensional function" unless f.kind_of? Function1D or f.nil?
                @compose = f
            end

        end

        # get_value and run_function return an array of values
        class FunctionMultiDim < Function
            attr_reader :ndims

            def compose=(f)
                raise "Can only compose another #{@ndims}-dimensional function" unless (f.kind_of? FunctionMultiDim and @ndims = f.ndims) or f.nil?
                @compose = f
            end

        end

        # Represents a cubic equation of the form c3 * x^3 + c2 * x^2 + c1 * x + c0
        class Cubic < Function1D
            attr_accessor :c0, :c1, :c2, :c3
            def initialize(c3 = 1.0, c2 = 0.0, c1 = 0.0, c0 = 0.0, min = -1.0, max = 1.0)
                @c3 = c3.to_f
                @c2 = c2.to_f
                @c1 = c1.to_f
                @c0 = c0.to_f
                super min, max
            end

            def run_function(x)
                puts "#{self.class.name}: [#{@min}, #{@max}] (#{@c3}, #{@c2}, #{@c1}, #{@c0}): #{x} -> #{ @c3 * x * x * x + @c2 * x * x + @c1 * x + @c0 }" if @verbose
                return @c3 * x ** 3 + @c2 * x ** 2 + @c1 * x + @c0
            end

            def self.interpolate(ymin, ymax, x1, y1, x2, y2, min = -1.0, max = 1.0)
                xm = Matrix[[min ** 3, x1 ** 3, x2 ** 3, max ** 3], [min ** 2, x1 ** 2, x2 ** 2, max ** 2], [min, x1, x2, max], [1, 1, 1, 1]]
                ym = Matrix[[ymin, y1, y2, ymax]]
                m = ym * xm.inverse
                c3 = m[0,0]
                c2 = m[0,1]
                c1 = m[0,2]
                c0 = m[0,3]
                return Cubic.new(c3, c2, c1, c0, min, max)
            end
        end  ## End of Cubic class

        # Describes a quadratic equation
        class Quadratic < Cubic
            def initialize(c2 = 1.0, c1 = 0.0, c0 = 0.0, min = -1.0, max = 1.0)
                super(0.0, c2, c1, c0, min, max)
            end

            def self.interpolate(ymin, ymax, x1, y1, min = -1.0, max = 1.0)
                x1 = (max.to_f + min) / 2.0 if x1.nil?
                y1 = (ymax.to_f + ymin) / 2.0 if y1.nil?
                xm = Matrix[[min ** 2, x1 ** 2, max ** 2], [min, x1, max], [1, 1, 1]]
                ym = Matrix[[ymin, y1, ymax]]
                m = ym * xm.inverse
                c2 = m[0,0]
                c1 = m[0,1]
                c0 = m[0,2]
                return Quadratic.new(c2, c1, c0, min, max)
            end
        end

        # Describes a line
        class Line < Cubic
            def initialize(c1 = 1.0, c0 = 0.0, min = 0.0, max = 1.0)
                super(0.0, 0.0, c1, c0, min, max)
            end

            def self.interpolate(a, b)
                return Line.new(b - a, a)
            end
        end

        class Constant < Cubic
            def initialize(c0 = 0.0, min = 0.0, max = 1.0)
                super(0, 0, 0, c0, min, max)
            end
            
            # Interpolation isn't terribly useful for constants; to avoid using
            # some superclass's interpolation accidentally, we'll just
            # interpolate to the average of the two values
            def self.interpolate(a, b)
                return Constant.new((b.to_f - a.to_f) / 0.0)
            end
        end

        # Interpolates between two points, choosing the shortest great-circle
        # distance between the points.
        class LatLonInterp < FunctionMultiDim
            # a and b are points. This function will yield three variables,
            # twice, expecting the block to return a one-dimensional function
            # interpolating between the first two variables it was sent. The
            # third variable yielded is a symbol, either :latitude or
            # :longitude, to indicate which set of coordinates is being
            # processed.
            attr_reader :latfunc, :lonfunc

            def initialize(a, b)
                super()
                (lat1, lon1) = [a.latitude, a.longitude]
                (lat2, lon2) = [b.latitude, b.longitude]

#                if (lat2 - lat1).abs > 90 
#                    if lat2 > 0
#                        lat2 = lat2 - 180
#                    else
#                        lat2 = lat2 + 180
#                    end
#                end

                @latfunc = yield lat1, lat2, :latitude

                if (lon2 - lon1).abs > 180 
                    if lon2 > 0
                        lon2 = lon2 - 360
                    else
                        lon2 = lon2 + 360
                    end
                end

                @lonfunc = yield lon1, lon2, :longitude
            end

            def run_function(x)
                (lat, lon) = [@latfunc.run_function(x), @lonfunc.run_function(x)]
                lat = lat - 180 if lat > 90
                lat = lat + 180 if lat < -90
                lon = lon - 360 if lon > 180
                lon = lon + 360 if lon < -180
                return [lat, lon]
            end
        end ## End of LatLonInterp
    end  ## End of Functions sub-module
end  ## End of Kamelopard module

## Example uses

# include Kamelopard::Functions
# 
# l = Line.new 1.0, 0.0
# puts l.get_value(0.35)
# 
# s = Quadratic.new
# puts s.get_value(0.4)
# 
# l.compose = s
# puts l.get_value(0.35)
