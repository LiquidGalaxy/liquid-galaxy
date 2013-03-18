# vim:ts=4:sw=4:et:smartindent:nowrap

# Classes to manage functions

module Kamelopard
    module Functions
        # Abstract class representing a one-dimensional function
        class Function1D
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
                raise "Can only compose another one-dimensional function" unless f.kind_of? Function1D or f.nil?
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
            #    raise "Can only append another one-dimensional function" unless f.kind_of? Function1D or f.nil?
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
                # Creates a new Function1D object between points A and B
                raise "Override this method before calling it, please"
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
        end

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
                p xm
                p ym
                m = ym * xm.inverse
                p m
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
    end
end 
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
