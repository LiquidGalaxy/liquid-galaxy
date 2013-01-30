# vim:ts=4:sw=4:et:smartindent:nowrap
require 'matrix'
#require 'kamelopard_classes'

# XXX Right now I'm changing this to handle one-dimensional lists of numbers,
# that can be added together. We'll probably want a way to add points, or other
# numeric sets, to a set of pointlists easily. So for instance we can have
# lists for altitude, longitude, and latitude, and add a single point to them
# in one easy command.

module Kamelopard
    class NumberList
        # Contains a list of numbers

        def initialize(init = [])
            raise "Constructor argument needs to be an array" unless init.kind_of? Array
            @points = init
        end

        def size
            return @points.size
        end

        def <<(a)
            @points << a
        end

        def last
            @points.last
        end

        def [](i)
            @points[i]
        end

        def each(&blk)
            @points.each(&blk)
        end
    end

    def Kamelopard.lists_at(lists, i)
        # The modulus ensures lists will repeat if they're not the same size
        lists.collect { |l| l[i % l.size] }
    end

    def Kamelopard.interpolate(lists = [], resolution = [10])
        # Ruby implementation of Catmull-Rom splines (http://www.cubic.org/docs/hermite.htm)
        # Return NDPointList interpolating a path along all points in this list

        size = lists.collect { |l| l.size }.max
        STDERR.puts size

        h = Matrix[
            [ 2,  -2,   1,   1 ],
            [-3,   3,  -2,  -1 ],
            [ 0,   0,   1,   0 ],
            [ 1,   0,   0,   0 ],
        ]

        # XXX This needs to be fixed
        result = []

        idx = 0
        resolution = [resolution] if ! resolution.respond_to? :[]

        # Calculate spline between every two points
        (0..(size-2)).each do |i|
            p1 = lists_at(lists, i)
            p2 = lists_at(lists, i+1)
            
            # Get surrounding points for calculating tangents
            if i <= 0 then pt1 = p1 else pt1 = lists_at(lists, i-1) end
            if i >= size - 2 then pt2 = p2 else pt2 = lists_at(lists, i+2) end

            # Build tangent points into matrices to calculate tangents.
            t1 = 0.5 * ( Matrix[p2]  - Matrix[pt1] )
            t2 = 0.5 * ( Matrix[pt2] - Matrix[p1] )

            # Build matrix of Hermite parameters
            c = Matrix[p1, p2, t1.row(0), t2.row(0)]

            # Make a set of points
            point_count = (resolution[idx] * 1.0 / size).to_i
            STDERR.puts point_count
            (0..point_count).each do |t|
                r = t/10.0
                s = Matrix[[r**3, r**2, r, 1]]
                tmp = s * h
                p = tmp * c
                result << p.row(0).to_a
            end
            idx += 1
            idx = 0 if idx >= resolution.size
        end
        result
    end
end

#a = Kamelopard::NumberList.new [1, 2, 3]
#b = Kamelopard::NumberList.new [5, 6, 10]
#
#i = 0
#Kamelopard.interpolate([a, b], [100]).each do |f|
#    i += 1
#    puts "#{i}\t#{f.inspect}"
#end
