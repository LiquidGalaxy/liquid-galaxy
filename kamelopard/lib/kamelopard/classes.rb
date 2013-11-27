# encoding: utf-8
#--
# vim:ts=4:sw=4:et:smartindent:nowrap
#++
# Classes to manage various KML objects. See
# http://code.google.com/apis/kml/documentation/kmlreference.html for a
# description of KML

# Pretty much everything important is in this module
module Kamelopard
    require 'bundler/setup'
    require 'singleton'
    require 'xml'
    require 'yaml'
    require 'erb'
    require 'cgi'

    @@sequence = 0
    @@id_prefix = ''
    @@logger = nil

    # Valid log levels:
    # * :debug
    # * :info
    # * :notice
    # * :warn
    # * :error
    # * :fatal
    LogLevels = {
        :debug => 0,
        :info => 1,
        :notice => 2,
        :warn => 3,
        :error => 4,
        :fatal => 5
    }

    @@log_level = LogLevels[:notice]

    # Sets a logging callback function. This function should expect three
    # arguments. The first will be a log level (:debug, :info, :notice, :warn,
    # :error, or :fatal); the second will be a text string, categorizing the
    # log entries generally; and the third will be the log message itself
    def Kamelopard.set_logger(l)
        @@logger = l
    end

    # Sets the current logging level. Valid levels are defined in the LogLevels hash
    def Kamelopard.set_log_level(lev)
        raise "Unknown log level #{lev}" unless LogLevels.has_key? lev
        @@log_level = LogLevels[lev]
    end

    # Logs a message, provided a log level, a text string, and the log message.
    # See #Kamelopard.set_logger for details.
    def Kamelopard.log(level, mod, msg)
        raise "Unknown log level #{level} for error message #{msg}" unless LogLevels.has_key? level
        @@logger.call(level, mod, msg) unless @@logger.nil? or @@log_level > LogLevels[level]
    end

    def Kamelopard.get_next_id   # :nodoc:
        @@sequence += 1
        @@sequence
    end

    # Sets a prefix for all kml_id values generated from this time forth. Does
    # not change previously generated kml_ids
    def Kamelopard.id_prefix=(a)
        @@id_prefix = a
    end

    # Returns the current kml_id prefix value. See #Kamelopard.id_prefix=
    def Kamelopard.id_prefix
        @@id_prefix
    end

    #--
    # Intelligently adds elements to a KML object. Expects the KML object as the
    # first argument, an array as the second.  Each entry in the array is itself an
    # array, containing first an Object, and second either a string or a Proc
    # object. If the first Object is nil, nothing happens. If it's not nil, then:
    #   * if the second element is a string, add a new element to the KML. This
    #     string is the element name, and the stringified form of the first element
    #     is its text value
    #   * if the second element is a proc, call the proc, passing it the KML
    #     object, and let the Proc (presumably) add itself to the KML
    #++
    def Kamelopard.kml_array(e, m) # :nodoc:
        m.map do |a|
            if ! a[0].nil? then
                if a[1].kind_of? Proc then
                    a[1].call(e)
                elsif a[0].kind_of? XML::Node then
                    d = XML::Node.new(a[1])
                    d << a[0]
                    e << d
                else
                    t = XML::Node.new a[1]
                    t << a[0].to_s
                    e << t
                end
            end
        end
    end

    #--
    # Accepts XdX'X.X", XDXmX.XXs, XdXmX.XXs, or X.XXXX with either +/- or N/E/S/W
    #++
    def Kamelopard.convert_coord(a)    # :nodoc:
        a = a.to_s.upcase.strip.gsub(/\s+/, '')

        if a =~ /^[+-]?\d+(\.\d+)?$/ then
            # coord needs no transformation
            return a.to_f
        elsif a =~ /^[+-]?\d+\.\d+E?-?\d+/ then
            # Scientific notation
            return a.to_f
        end

        mult = 1
        if a =~ /^-/ then
            mult *= -1
        end
        a = a.sub /^\+|-/, ''
        a = a.strip

        if a =~ /[SW]$/ then
            mult *= -1
        end
        a = a.sub /[NESW]$/, ''
        a = a.strip

        if a =~ /^\d+D\d+M\d+(\.\d+)?S$/ then
            # coord is in dms
            p = a.split /[D"']/
            a = p[0].to_f + (p[2].to_f / 60.0 + p[1].to_f) / 60.0
        elsif a =~ /^\d+D\d+'\d+(\.\d+)?"$/ then
            # coord is in d'"
            p = a.split /[D"']/
            a = p[0].to_f + (p[2].to_f / 60.0 + p[1].to_f) / 60.0
        elsif m = (a =~ /^(\d+)°(\d+)'(\d+\.\d+)?"$/) then
            # coord is in °'"
            b = a
            a = $1.to_f + ($3.to_f / 60.0 + $2.to_f) / 60.0
        else
            raise "Couldn't determine coordinate format for #{a}"
        end

        # check that it's within range
        a = a.to_f * mult
        raise "Coordinate #{a} out of range" if a > 180 or a < -180
        return a.to_f
    end

    # Helper function for altitudeMode / gx:altitudeMode elements
    def Kamelopard.add_altitudeMode(mode, e) # :nodoc:
        return if mode.nil?
        if mode == :clampToGround or mode == :relativeToGround or mode == :absolute then
            t = XML::Node.new 'altitudeMode'
        else
            t = XML::Node.new 'gx:altitudeMode'
        end
        t << mode.to_s
        e << t
    end

    # Base class for all Kamelopard objects. Manages object ID and a single
    # comment string associated with the object. Object IDs are stored in the
    # kml_id attribute, and are prefixed with the value last passed to
    # Kamelopard.id_prefix=, if anything. Note that assigning this prefix will
    # *not* change the IDs of Kamelopard objects that are already
    # initialized... just ones initialized thereafter.
    class Object
        attr_accessor :kml_id
        attr_reader :comment

        # The master_only attribute determines whether this Object should be
        # included in slave mode KML files, or not. It defaults to false,
        # indicating the Object should be included in KML files of all types.
        # Set it to true to ensure it shows up only in slave mode.
        attr_reader :master_only

        # Abstract function, designed to take an XML node containing a KML
        # object of this type, and parse it into a Kamelopard object
        def self.parse(x)
            raise "Cannot parse a #{self.class.name}"
        end

        # This constructor looks for values in the options hash that match
        # class attributes, and sets those attributes to the values in the
        # hash. So a class with an attribute called :when can be set via the
        # constructor by including ":when => some-value" in the options
        # argument to the constructor.
        def initialize(options = {})
            @kml_id = "#{Kamelopard.id_prefix}#{self.class.name.gsub('Kamelopard::', '')}_#{ Kamelopard.get_next_id }"
            @master_only = false

            options.each do |k, v|
                method = "#{k}=".to_sym
                if self.respond_to? method then
                    self.method(method).call(v)
                else
                    raise "Warning: couldn't find attribute for options hash key #{k}"
                end
            end
        end

        def change(attributes, values)
            change = XML::Node.new 'Change'
            child = XML::Node.new self.class.name
            child.attributes[:targetId] = @kml_id
            change << child
            return change
        end

        # If this is a master-only object, this function gets called internally
        # in place of the object's original to_kml method
        def _alternate_to_kml(*a)
            if @master_only and ! DocumentHolder.instance.current_document.master_mode
                Kamelopard.log(:info, 'master/slave', "Because this object is master_only, and we're in slave mode, we're not including object #{self.inspect}")
                return ''
            end

            # XXX There must be a better way to do this, but I don't know what
            # it is. Running "@original_to_kml_method.call(a)" when the
            # original method expects multiple arguments interprets the
            # argument as an array, not as a list of arguments. This of course
            # makes sense, but I don't know how to get around it.
            case @original_to_kml_method.parameters.size
            when 0
                return @original_to_kml_method.call
            when 1
                # XXX This bothers me, and I'm unconvinced the calls to
                # functions with more than one parameter actually work. Why
                # should I have to pass a[0][0] here and just a[0], a[1], etc.
                # for larger numbers of parameters, if this were all correct?
                return @original_to_kml_method.call(a[0][0])
            when 2
                return @original_to_kml_method.call(a[0], a[1])
            when 3
                return @original_to_kml_method.call(a[0], a[1], a[2])
            else
                raise "Unsupported number of arguments (#{@original_to_kml_method.arity}) in to_kml function #{@original_to_kml_method}. This is a bug"
            end
        end

        # Changes whether this object is available in master style documents
        # only, or in slave documents as well.
        #
        # More specifically, this method replaces the object's to_kml method
        # with something that checks whether this object should be included in
        # the KML output, based on whether it's master-only or not, and whether
        # the document is in master or slave mode.
        def master_only=(a)
            # If this object is a master_only object, and we're printing in
            # slave mode, this object shouldn't be included at all (to_kml
            # should return an empty string)
            if a != @master_only
                @master_only = a
                if a then
                    @original_to_kml_method = public_method(:to_kml)
                    define_singleton_method :to_kml, lambda { |*a| self._alternate_to_kml(a) }
                else
                    define_singleton_method :to_kml, @original_to_kml_method
                end
            end
        end

        # This just makes the Ruby-ism question mark suffix work
        def master_only?
            return @master_only
        end

        # Adds an XML comment to this node. Handles HTML escaping the comment
        # if needed
        def comment=(cmnt)
            require 'cgi'
            @comment = CGI.escapeHTML(cmnt)
        end

        # Returns XML::Node containing this object's KML. Objects should
        # override this method
        def to_kml(elem)
            elem.attributes['id'] = @kml_id.to_s
            if not @comment.nil? and @comment != '' then
                c = XML::Node.new_comment " #{@comment} "
                elem << c
                return c
            end
        end

        # Generates a <Change> element suitable for changing the given field of
        # an object to the given value
        def change(field, value)
            c = XML::Node.new 'Change'
            o = XML::Node.new self.class.name.sub!(/Kamelopard::/, '')
            o.attributes['targetId'] = self.kml_id
            e = XML::Node.new field
            e.content = value.to_s
            o << e
            c << o
            c
        end
    end

    # Abstract base class for Point and several other classes
    class Geometry < Object
    end

    # Represents a Point in KML.
    class Point < Geometry
        attr_reader :longitude, :latitude
        attr_accessor :altitude, :altitudeMode, :extrude

        def initialize(longitude = nil, latitude = nil, altitude = nil, options = {})
            super options
            @longitude = Kamelopard.convert_coord(longitude) unless longitude.nil?
            @latitude = Kamelopard.convert_coord(latitude) unless latitude.nil?
            @altitude = altitude unless altitude.nil?
        end

        def longitude=(long)
            @longitude = Kamelopard.convert_coord(long)
        end

        def latitude=(lat)
            @latitude = Kamelopard.convert_coord(lat)
        end

        def to_s
            "Point (#{@longitude}, #{@latitude}, #{@altitude}, mode = #{@altitudeMode}, #{ @extrude == 1 ? 'extruded' : 'not extruded' })"
        end

        def to_kml(elem = nil, short = false)
            e = XML::Node.new 'Point'
            super(e)
            e.attributes['id'] = @kml_id
            c = XML::Node.new 'coordinates'
            c << "#{ @longitude }, #{ @latitude }, #{ @altitude }"
            e << c

            if not short then
                c = XML::Node.new 'extrude'
                c << ( @extrude ? 1 : 0 ).to_s
                e << c

                Kamelopard.add_altitudeMode(@altitudeMode, e)
            end

            elem << e unless elem.nil?
            e
        end
    end

    # Helper class for KML objects which need to know about several points at once
    module CoordinateList
        attr_reader :coordinates

        def coordinates=(a)
            if a.nil? then
                coordinates = []
            else
                add_element a
            end
        end

        def coordinates_to_kml(elem = nil)
            e = XML::Node.new 'coordinates'
            t = ''
            @coordinates.each do |a|
                t << "#{ a[0] },#{ a[1] }"
                t << ",#{ a[2] }" if a.size > 2
                t << ' '
            end
            e << t.chomp(' ')
            elem << e unless elem.nil?
            e
        end

        # Alias for add_element
        def <<(a)
            add_element a
        end

        # Adds one or more elements to this CoordinateList. The argument can be in any of several formats:
        # * An array of arrays of numeric objects, in the form [ longitude,
        #   latitude, altitude (optional) ]
        # * A Point, or some other object that response to latitude, longitude, and altitude methods
        # * An array of the above
        # * Another CoordinateList, to append to this on
        # Note that this will not accept a one-dimensional array of numbers to add
        # a single point. Instead, create a Point with those numbers, and pass
        # it to add_element
        #--
        # XXX The above stipulation is a weakness that needs fixing
        #++
        def add_element(a)
            if a.kind_of? Enumerable then
                # We've got some sort of array or list. It could be a list of
                # floats, to become one coordinate, or it could be several
                # coordinates
                t = a.to_a.first
                if t.kind_of? Enumerable then
                    # At this point we assume we've got an array of float-like
                    # objects. The second-level arrays need to have two or three
                    # entries -- long, lat, and (optionally) alt
                    a.each do |i|
                        if i.size < 2 then
                            raise "There aren't enough objects here to make a 2- or 3-element coordinate"
                        elsif i.size >= 3 then
                            @coordinates << [ i[0].to_f, i[1].to_f, i[2].to_f ]
                        else
                            @coordinates << [ i[0].to_f, i[1].to_f ]
                        end
                    end
                elsif t.respond_to? 'longitude' and
                    t.respond_to? 'latitude' and
                    t.respond_to? 'altitude' then
                    # This object can cough up a set of coordinates
                    a.each do |i|
                        @coordinates << [i.longitude, i.latitude, i.altitude]
                    end
                else
                    # I dunno what it is
                    raise "Kamelopard can't understand this object as a coordinate"
                end
            elsif a.kind_of? CoordinateList then
                # Append this coordinate list
                @coordinates << a.coordinates
            else
                # This is one element. It better know how to make latitude, longitude, etc.
                if a.respond_to? 'longitude' and
                    a.respond_to? 'latitude' and
                    a.respond_to? 'altitude' then
                    @coordinates << [a.longitude, a.latitude, a.altitude]
                else
                    raise "Kamelopard can't understand this object as a coordinate"
                end
            end
        end
    end

    # Corresponds to the KML LineString object
    class LineString < Geometry
        include CoordinateList
        attr_accessor :altitudeOffset, :extrude, :tessellate, :altitudeMode, :drawOrder, :longitude, :latitude, :altitude

        def initialize(coordinates = [], options = {})
            @coordinates = []
            super options
            self.coordinates=(coordinates) unless coordinates.nil?
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'LineString'
            super(k)
            Kamelopard.kml_array(k, [
                [@altitudeOffset, 'gx:altitudeOffset'],
                [@extrude, 'extrude'],
                [@tessellate, 'tessellate'],
                [@drawOrder, 'gx:drawOrder']
            ])
            coordinates_to_kml(k) unless @coordinates.nil?
            Kamelopard.add_altitudeMode @altitudeMode, k
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's LinearRing object
    class LinearRing < Geometry
        attr_accessor :altitudeOffset, :extrude, :tessellate, :altitudeMode
        include CoordinateList

        def initialize(coordinates = [], options = {})
            @tessellate = 0
            @extrude = 0
            @altitudeMode = :clampToGround
            @coordinates = []

            super options
            self.coordinates=(coordinates) unless coordinates.nil?
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'LinearRing'
            super(k)
            Kamelopard.kml_array(k, [
                [ @altitudeOffset, 'gx:altitudeOffset' ],
                [ @tessellate, 'tessellate' ],
                [ @extrude, 'extrude' ]
            ])
            Kamelopard.add_altitudeMode(@altitudeMode, k)
            coordinates_to_kml(k) unless @coordinates.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Abstract class corresponding to KML's AbstractView object
    class AbstractView < Object
        attr_accessor :timestamp, :timespan, :viewerOptions, :heading, :tilt,
        :roll, :range, :altitudeMode
        attr_reader :className, :point

        def initialize(className, point, options = {})
            raise "className argument must not be nil" if className.nil?

            @heading = 0
            @tilt = 0
            @roll = nil
            @range = nil
            @altitudeMode = :clampToGround
            @viewerOptions = {}

            super options

            @className = className
            self.point= point unless point.nil?
        end

        def point=(point)
            if point.nil? then
                @point = nil
            else
                if point.respond_to? :point then
                    a = point.point
                else
                    a = point
                end
                @point = Point.new a.longitude, a.latitude, a.altitude, :altitudeMode => a.altitudeMode, :extrude => a.extrude
            end
        end

        def longitude
            @point.nil? ? nil : @point.longitude
        end

        def latitude
            @point.nil? ? nil : @point.latitude
        end

        def altitude
            @point.nil? ? nil : @point.altitude
        end

        def longitude=(a)
            if @point.nil? then
                @point = Point.new(a, 0)
            else
                @point.longitude = a
            end
        end

        def latitude=(a)
            if @point.nil? then
                @point = Point.new(0, a)
            else
                @point.latitude = a
            end
        end

        def altitude=(a)
            if @point.nil? then
                @point = Point.new(0, 0, a)
            else
                @point.altitude = a
            end
        end

        def to_kml(elem = nil)
            t = XML::Node.new @className
            super(t)
            Kamelopard.kml_array(t, [
                [ @point.nil? ? nil : @point.longitude, 'longitude' ],
                [ @point.nil? ? nil : @point.latitude, 'latitude' ],
                [ @point.nil? ? nil : @point.altitude, 'altitude' ],
                [ @heading, 'heading' ],
                [ @tilt, 'tilt' ],
                [ @range, 'range' ],
                [ @roll, 'roll' ]
            ])
            Kamelopard.add_altitudeMode(@altitudeMode, t)
            if @viewerOptions.keys.length > 0 then
                vo = XML::Node.new 'gx:ViewerOptions'
                @viewerOptions.each do |k, v|
                    o = XML::Node.new 'gx:option'
                    o.attributes['name'] = k.to_s
                    o.attributes['enabled'] = v ? 'true' : 'false'
                    vo << o
                end
                t << vo
            end
            if not @timestamp.nil? then
                @timestamp.to_kml(t, 'gx')
            elsif not @timespan.nil? then
                @timespan.to_kml(t, 'gx')
            end
            elem << t unless elem.nil?
            t
        end

        def to_queries_txt(name = '', planet = 'earth')
            return "#{planet}@#{name}@flytoview=" + self.to_kml.to_s.gsub(/^\s+/, '').gsub("\n", '')
        end

        def [](a)
            return @viewerOptions[a]
        end

        def []=(a, b)
            if not b.kind_of? FalseClass and not b.kind_of? TrueClass then
                raise 'Option value must be boolean'
            end
            if a != :streetview and a != :historicalimagery and a != :sunlight then
                raise 'Option index must be :streetview, :historicalimagery, or :sunlight'
            end
            @viewerOptions[a] = b
        end
    end

    # Corresponds to KML's Camera object
    class Camera < AbstractView
        def initialize(point = nil, options = {})
            super('Camera', point, options)
            @roll = 0 if @roll.nil?
        end

        def range
            raise "The range element is part of LookAt objects, not Camera objects"
        end

        def range=(a)
            # The range element doesn't exist in Camera objects
        end
    end

    # Corresponds to KML's LookAt object
    class LookAt < AbstractView
        def initialize(point = nil, options = {})
            super('LookAt', point, options)
            @range = 0 if @range.nil?
        end

        def roll
            # The roll element doesn't exist in LookAt objects
            raise "The roll element is part of Camera objects, not LookAt objects"
        end

        def roll=(a)
            # The roll element doesn't exist in LookAt objects
            raise "The roll element is part of Camera objects, not LookAt objects"
        end
    end

    # Abstract class corresponding to KML's TimePrimitive object
    class TimePrimitive < Object
    end

    # Corresponds to KML's TimeStamp object. The @when attribute must be in a
    # format KML understands. Refer to the KML documentation to see which
    # formats are available.
    class TimeStamp < TimePrimitive
        attr_accessor :when
        def initialize(ts_when = nil, options = {})
            super options
            @when = ts_when unless ts_when.nil?
        end

        def to_kml(elem = nil, ns = nil)
            prefix = ''
            prefix = ns + ':' unless ns.nil?

            k = XML::Node.new "#{prefix}TimeStamp"
            super(k)
            w = XML::Node.new 'when'
            w << @when
            k << w
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's TimeSpan object. @begin and @end must be in a format KML
    # understands.
    class TimeSpan < TimePrimitive
    # XXX Evidence suggests this doesn't support unbounded intervals. Fix that, if it's true.
        attr_accessor :begin, :end
        def initialize(ts_begin = nil, ts_end = nil, options = {})
            super options
            @begin = ts_begin unless ts_begin.nil?
            @end = ts_end unless ts_end.nil?
        end

        def to_kml(elem = nil, ns = nil)
            prefix = ''
            prefix = ns + ':' unless ns.nil?

            k = XML::Node.new "#{prefix}TimeSpan"
            super(k)
            if not @begin.nil? then
                w = XML::Node.new 'begin'
                w << @begin
                k << w
            end
            if not @end.nil? then
                w = XML::Node.new 'end'
                w << @end
                k << w
            end
            elem << k unless elem.nil?
            k
        end
    end

    # Support class for Feature object
    module Snippet
        attr_accessor :snippet_text, :maxLines

        def snippet_to_kml(elem = nil)
            e = XML::Node.new 'Snippet'
            e.attributes['maxLines'] = @maxLines.to_s
            e << @snippet_text
            elem << e unless elem.nil?
            e
        end
    end

    # Corresponds to Data elements within ExtendedData
    class Data
        attr_accessor :name, :displayName, :value
        def initialize(name, value, displayName = nil)
            @name = name
            @displayName = displayName
            @value = value
        end

        def to_kml(elem = nil)
            v = XML::Node.new 'Data'
            v.attributes['name'] = @name
            Kamelopard.kml_array(v, [
                    [@value, 'value'],
                    [@displayName, 'displayName']
                ])
            elem << v unless elem.nil?
            v
        end
    end

    # Corresponds to KML's ExtendedData SchemaData objects
    class SchemaData
        attr_accessor :schemaUrl, :simpleData
        def initialize(schemaUrl, simpleData = {})
            @schemaUrl = schemaUrl
            raise "SchemaData's simpleData attribute should behave like a hash" unless simpleData.respond_to? :keys
            @simpleData = simpleData
        end

        def <<(a)
            @simpleData.merge a
        end

        def to_kml(elem = nil)
            s = XML::Node.new 'SchemaData'
            s.attributes['schemaUrl'] = @schemaUrl
            @simpleData.each do |k, v|
                sd = XML::Node.new 'SimpleData', v
                sd.attributes['name'] = k
                s << sd
            end
            elem << v unless elem.nil?
            v
        end
    end

    # Abstract class corresponding to KML's Feature object.
    #--
    # XXX Make this support alternate namespaces
    #++
    class Feature < Object
        attr_accessor :visibility, :open, :atom_author, :atom_link, :name,
            :phoneNumber, :abstractView, :styles, :timeprimitive, :styleUrl,
            :styleSelector, :region, :metadata
        attr_reader :addressDetails, :snippet, :extendedData, :description

        include Snippet

        def initialize (name = nil, options = {})
            @visibility = true
            @open = false
            @styles = []
            super options
            @name = name unless name.nil?
        end

        def description=(a)
            b = CGI.escapeHTML(a) if b.is_a? String
            if (! a.is_a? XML::Node) and b != a then
                @description = XML::Node.new_cdata a
            else
                @description = a
            end
        end

        def extendedData=(a)
            raise "extendedData attribute must respond to the 'each' method" unless a.respond_to? :each
            @extendedData = a
        end

        def styles=(a)
            if a.is_a? Array then
                @styles = a
            elsif @styles.nil? then
                @styles = []
            else
                @styles = [a]
            end
        end

        # Hides the object. Note that this governs only whether the object is
        # initially visible or invisible; to show or hide the feature
        # dynamically during a tour, use an AnimatedUpdate object
        def hide
            @visibility = false
        end

        # Shows the object. See note for hide() method
        def show
            @visibility = true
        end

        def timestamp
            @timeprimitive
        end

        def timespan
            @timeprimitive
        end

        def timestamp=(t)
            @timeprimitive = t
        end

        def timespan=(t)
            @timeprimitive = t
        end

        def addressDetails=(a)
            if a.nil? or a == '' then
                DocumentHolder.instance.current_document.uses_xal = false
            else
                DocumentHolder.instance.current_document.uses_xal = true
            end
            @addressDetails = a
        end

        # This function accepts either a StyleSelector object, or a string
        # containing the desired StyleSelector's @kml_id
        def styleUrl=(a)
            if a.is_a? String then
                @styleUrl = a
            elsif a.respond_to? :kml_id then
                @styleUrl = "##{ a.kml_id }"
            else
                @styleUrl = a.to_s
            end
        end

        def self.add_author(o, a)
            e = XML::Node.new 'atom:name'
            e << a.to_s
            f = XML::Node.new 'atom:author'
            f << e
            o << f
        end

        def to_kml(elem = nil)
            elem = XML::Node.new 'Feature' if elem.nil?
            super elem
            Kamelopard.kml_array(elem, [
                    [@name, 'name'],
                    [(@visibility.nil? || @visibility) ? 1 : 0, 'visibility'],
                    [(! @open.nil? && @open) ? 1 : 0, 'open'],
                    [@atom_author, lambda { |o| Feature.add_author(o, @atom_author) }],
                    [@atom_link, 'atom:link'],
                    [@address, 'address'],
                    [@addressDetails, 'xal:AddressDetails'],
                    [@phoneNumber, 'phoneNumber'],
                    [@description, 'description'],
                    [@styleUrl, 'styleUrl'],
                    [@styleSelector, lambda { |o| @styleSelector.to_kml(o) }],
                    [@metadata, 'Metadata' ]
                ])
            styles_to_kml(elem)
            snippet_to_kml(elem) unless @snippet_text.nil?
            extended_data_to_kml(elem) unless @extendedData.nil?
            @abstractView.to_kml(elem) unless @abstractView.nil?
            @timeprimitive.to_kml(elem) unless @timeprimitive.nil?
            @region.to_kml(elem) unless @region.nil?
            yield(elem) if block_given?
            elem
        end

        def extended_data_to_kml(elem)
            v = XML::Node.new 'ExtendedData'
            @extendedData.each do |f|
                v << f.to_kml
            end
            elem << v unless elem.nil?
            v
        end

        def styles_to_kml(elem)
            # XXX Remove this
            raise "done here" if elem.class == Array
            @styles.each do |a|
                a.to_kml(elem) # unless a.attached?
            end
        end
    end

    # Abstract class corresponding to KML's Container object.
    class Container < Feature
        def initialize(name = nil, options = {})
            @features = []
            super
        end

        def features=(a)
            if a.respond_to? :[] then
                @features = a
            else
                @features = [a]
            end
        end

        # Adds a new object to this container.
        def <<(a)
            @features << a
        end
    end

    # Corresponds to KML's Folder object.
    class Folder < Container
        attr_accessor :styles, :folders, :parent_folder

        def initialize(name = nil, options = {})
            @styles = []
            @folders = []
            super
            DocumentHolder.instance.current_document.folders << self
        end

        def styles=(a)
            if a.respond_to? :[] then
                @styles = a
            else
                @styles = [a]
            end
        end

        def folders=(a)
            if a.respond_to? :[] then
                @folders = a
            else
                @folders = [a]
            end
        end

        def to_kml(elem = nil)
            h = XML::Node.new 'Folder'
            super h
            @features.each do |a|
                a.to_kml(h)
            end
            @folders.each do |a|
                a.to_kml(h)
            end
            elem << h unless elem.nil?
            h
        end

        # Folders can have parent folders; returns true if this folder has one
        def has_parent?
            not @parent_folder.nil?
        end

        # Folders can have parent folders; sets this folder's parent
        def parent_folder=(a)
            @parent_folder = a
            a.folders << self
        end
    end

    def get_stack_trace   # :nodoc:
        k = ''
        caller.each do |a| k << "#{a}\n" end
        k
    end

    # Represents KML's Document class.
    class Document < Container
        attr_accessor :flyto_mode, :folders, :tours, :uses_xal, :vsr_actions

        # Is this KML destined for a master LG node, or a slave? True if this
        # is a master node. This defaults to true, so tours that don't need
        # this function, and tours for non-LG targets, work normally.
        attr_accessor :master_mode

        def initialize(name = '', options = {})
            @tours = []
            @folders = []
            @vsr_actions = []
            @master_mode = false
            Kamelopard.log(:info, 'Document', "Adding myself to the document holder")
            DocumentHolder.instance << self
            super
        end

        # Returns viewsyncrelay actions as a hash
        def get_actions
            {
                'actions' => @vsr_actions.collect { |a| a.to_hash }
            }
        end

        def get_actions_yaml
            get_actions.to_yaml
        end

        # Returns the current Tour object
        def tour
            Tour.new if @tours.length == 0
            @tours.last
        end

        # Returns the current Folder object
        def folder
            if @folders.size == 0 then
                Folder.new
            end
            @folders.last
        end

        # Makes a screenoverlay with a balloon containing links to the tours in this document
        # The erb argument contains ERB to populate the description. It can be left nil 
        # The options hash is passed to the ScreenOverlay constructor
        def make_tour_index(erb = nil, options = {})
            options[:name] ||= 'Tour index'

            options[:screenXY] ||= Kamelopard::XY.new(0.0, 1.0, :fraction, :fraction)
            options[:overlayXY] ||= Kamelopard::XY.new(0.0, 1.0, :fraction, :fraction)
            s = Kamelopard::ScreenOverlay.new options
            t = ERB.new( erb || %{
                <html>
                    <body>
                        <ul><% @tours.each do |t| %>
                            <li><a href="#<%= t.kml_id %>;flyto"><% if t.icon.nil? %><%= t.name %><% else %><img src="<%= t.icon %>" /><% end %></a></li>
                        <% end %></ul>
                    </body>
                </html>
            })

            s.description = XML::Node.new_cdata t.result(binding)
            s.balloonVisibility = 1

            balloon_au = [0, 1].collect do |v|
                au = Kamelopard::AnimatedUpdate.new [], :standalone => true
                a = XML::Node.new 'Change'
                b = XML::Node.new 'ScreenOverlay'
                b.attributes['targetId'] = s.kml_id
                c = XML::Node.new 'gx:balloonVisibility'
                c << XML::Node.new_text(v.to_s)
                b << c
                a << b
                au << a
                au
            end

            # Handle hiding and displaying the index
            @tours.each do |t|
                q = Wait.new(0.1, :standalone => true)
                t.playlist.unshift balloon_au[0]
                t.playlist.unshift q
                t.playlist << balloon_au[1]
                t.playlist << q
            end

            s
        end

        def get_kml_document
            k = XML::Document.new

#            # XXX Should this be add_namespace instead?
#            ns_arr = [
#                ['', 'http://www.opengis.net/kml/2.2'],
#                ['gx', 'http://www.google.com/kml/ext/2.2'],
#                ['kml', 'http://www.opengis.net/kml/2.2'],
#                ['atom', 'http://www.w3.org/2005/Atom'],
#                ['test', 'http://test.com']
#            ]
#            ns_arr.each do |a|
#                nm = 'xmlns'
#                nm = a[0] if a[0] != ''
#                k.context.register_namespace(nm, a[1])
#            end

            # XXX fix this
            #k << XML::XMLDecl.default
            k.root = XML::Node.new('kml')
            r = k.root
            if @uses_xal then
                r.attributes['xmlns:xal'] = "urn:oasis:names:tc:ciq:xsdschema:xAL:2.0"
            end
            # XXX Should this be add_namespace instead?
            r.attributes['xmlns'] = 'http://www.opengis.net/kml/2.2'
            r.attributes['xmlns:gx'] = 'http://www.google.com/kml/ext/2.2'
            r.attributes['xmlns:kml'] = 'http://www.opengis.net/kml/2.2'
            r.attributes['xmlns:atom'] = 'http://www.w3.org/2005/Atom'

            r << self.to_kml
            k
        end

        def to_kml
            d = XML::Node.new 'Document'
            super d

            # Print styles first
            #! These get printed out in the call to super, in Feature.to_kml()
            #@styles.map do |a| d << a.to_kml unless a.attached? end

            # then folders
            @folders.map do |a|
                a.to_kml(d) unless a.has_parent?
            end

            # then tours
            @tours.map do |a| a.to_kml(d) end

            d
        end
    end

    # Holds a set of Document objects, so we can work with multiple KML files
    # at once and keep track of them. It's important for Kamelopard's usability
    # to have the concept of a "current" document, so we don't have to specify
    # the document we're talking about each time we do something interesting.
    # This class supports that idea.
    class DocumentHolder
        include Singleton
        attr_accessor :document_index, :initialized
        attr_reader :documents

        def initialize(doc = nil)
            Kamelopard.log :debug, 'DocumentHolder', "document holder constructor"
            @documents = []
            @document_index = -1
            if ! doc.nil?
                Kamelopard.log :info, 'DocumentHolder', "Constructor called with a doc. Adding it."
                self.documents << doc
            end
            Kamelopard.log :debug, 'DocumentHolder', "document holder constructor finished"
        end

        def document_index
            return @document_index
        end

        def document_index=(a)
            @document_index = a
        end

        def delete_current_doc
            @documents.delete_at @document_index unless @document_index == -1
            if @documents.size > 0
                @document_index = @documents.size - 1
            else
                @document_index = -1
            end
        end

        def current_document
            # Automatically create a Document if we don't already have one
            if @documents.size <= 0
                Kamelopard.log :info, 'Document', "Doc doesn't exist... adding new one"
                Document.new
                @document_index = 0
            end
            return @documents[@document_index]
        end

        def <<(a)
            raise "Cannot add a non-Document object to a DocumentHolder" unless a.kind_of? Document
            @documents << a
            @document_index += 1
        end

        def set_current(a)
            raise "Must set current document to an existing Document object" unless a.kind_of? Document
            @document_index = @documents.index(a)
        end

        def [](a)
            return @documents[a]
        end

        def []=(i, v)
            raise "Cannot include a non-Document object in a DocumentHolder" unless v.kind_of? Document
            @documents[i] = v
        end

        def size
            return @documents.size
        end
    end

    # Corresponds to KML's ColorStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    class ColorStyle < Object
        attr_accessor :color
        attr_reader :colorMode

        def initialize(color = nil, options = {})
            super options
            @set_colorMode = false
            @color = color unless color.nil?
        end

        def validate_colorMode(a)
            raise "colorMode must be either \"normal\" or \"random\"" unless a == :normal or a == :random
        end

        def colorMode=(a)
            validate_colorMode a
            @set_colorMode = true
            @colorMode = a
        end

        def alpha
            @color[0,2]
        end

        def alpha=(a)
            @color[0,2] = a
        end

        def blue
            @color[2,2]
        end

        def blue=(a)
            @color[2,2] = a
        end

        def green
            @color[4,2]
        end

        def green=(a)
            @color[4,2] = a
        end

        def red
            @color[6,2]
        end

        def red=(a)
            @color[6,2] = a
        end

        def to_kml(elem = nil)
            k = elem.nil? ? XML::Node.new('ColorStyle') : elem
            super k
            e = XML::Node.new 'color'
            e << @color
            k << e
            if @set_colorMode then
                e = XML::Node.new 'colorMode'
                e << @colorMode
                k << e
            end
            k
        end
    end

    # Corresponds to KML's BalloonStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    class BalloonStyle < Object
        attr_accessor :bgColor, :text, :textColor, :displayMode

        # Note: color element order is aabbggrr
        def initialize(text = nil, options = {})
        #text = '', textColor = 'ff000000', bgColor = 'ffffffff', displayMode = :default)
            @bgColor = 'ffffffff'
            @textColor = 'ff000000'
            @displayMode = :default
            super options
            @text = text unless text.nil?
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'BalloonStyle'
            super k
            Kamelopard.kml_array(k, [
                [ @bgColor, 'bgColor' ],
                [ @text, 'text' ],
                [ @textColor, 'textColor' ],
                [ @displayMode, 'displayMode' ]
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Internal class used where KML requires X and Y values and units
    class XY
        attr_accessor :x, :y, :xunits, :yunits
        def initialize(x = 0.5, y = 0.5, xunits = :fraction, yunits = :fraction)
            @x = x
            @y = y
            @xunits = xunits
            @yunits = yunits
        end

        def to_kml(name, elem = nil)
            k = XML::Node.new name
            k.attributes['x'] = @x.to_s
            k.attributes['y'] = @y.to_s
            k.attributes['xunits'] = @xunits.to_s
            k.attributes['yunits'] = @yunits.to_s
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to the KML Icon object
    module Icon
       attr_accessor :href, :x, :y, :w, :h, :refreshMode, :refreshInterval, :viewRefreshMode, :viewRefreshTime, :viewBoundScale, :viewFormat, :httpQuery

        def href=(h)
            @icon_id = "#{Kamelopard.id_prefix}Icon_#{Kamelopard.get_next_id}" if @icon_id.nil?
            @href = h
        end

        def icon_to_kml(elem = nil)
            @icon_id = "#{Kamelopard.id_prefix}Icon_#{Kamelopard.get_next_id}" if @icon_id.nil?
            k = XML::Node.new 'Icon'
            k.attributes['id'] = @icon_id
            Kamelopard.kml_array(k, [
                [@href, 'href'],
                [@x, 'gx:x'],
                [@y, 'gx:y'],
                [@w, 'gx:w'],
                [@h, 'gx:h'],
                [@refreshMode, 'refreshMode'],
                [@refreshInterval, 'refreshInterval'],
                [@viewRefreshMode, 'viewRefreshMode'],
                [@viewRefreshTime, 'viewRefreshTime'],
                [@viewBoundScale, 'viewBoundScale'],
                [@viewFormat, 'viewFormat'],
                [@httpQuery, 'httpQuery'],
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's IconStyle object.
    class IconStyle < ColorStyle
        attr_accessor :scale, :heading, :hotspot

        include Icon

        def initialize(href = nil, options = {})
            @hotspot = XY.new(0.5, 0.5, :fraction, :fraction)
            super nil, options
            @href = href unless href.nil?
        end

        def hs_x=(a)
            @hotspot.x = a
        end

        def hs_y=(a)
            @hotspot.y = a
        end

        def hs_xunits=(a)
            @hotspot.xunits = a
        end

        def hs_yunits=(a)
            @hotspot.yunits = a
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'IconStyle'
            super(k)
            Kamelopard.kml_array( k, [
                [ @scale, 'scale' ],
                [ @heading, 'heading' ]
            ])
            if not @hotspot.nil? then
                h = XML::Node.new 'hotSpot'
                h.attributes['x'] = @hotspot.x.to_s
                h.attributes['y'] = @hotspot.y.to_s
                h.attributes['xunits'] = @hotspot.xunits.to_s
                h.attributes['yunits'] = @hotspot.yunits.to_s
                k << h
            end
            icon_to_kml(k)
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's LabelStyle object
    class LabelStyle < ColorStyle
        attr_accessor :scale

        def initialize(scale = 1, options = {})
            @scale = scale 
            super nil, options
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'LabelStyle'
            super k
            s = XML::Node.new 'scale'
            s << @scale.to_s
            k << s
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's LineStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    class LineStyle < ColorStyle
        attr_accessor :outerColor, :outerWidth, :physicalWidth, :width, :labelVisibility

        def initialize(options = {})
            @outerColor = 'ffffffff'
            @width = 1
            @outerWidth = 0
            @physicalWidth = 0
            @labelVisibility = 0

            super nil, options
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'LineStyle'
            super k
            Kamelopard.kml_array(k, [
                [ @width, 'width' ],
                [ @outerColor, 'gx:outerColor' ],
                [ @outerWidth, 'gx:outerWidth' ],
                [ @physicalWidth, 'gx:physicalWidth' ],
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's ListStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    #--
    # This doesn't descend from ColorStyle because I don't want the to_kml()
    # call to super() adding color and colorMode elements to the KML -- Google
    # Earth complains about 'em
    #++
    class ListStyle < Object
        attr_accessor :listItemType, :bgColor, :state, :href

        def initialize(options = {})
        #bgcolor = nil, state = nil, href = nil, listitemtype = nil)
            @state = :open
            @bgColor = 'ffffffff'
            super
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'ListStyle'

            super k
            Kamelopard.kml_array(k, [
                [@listItemType, 'listItemType'],
                [@bgColor, 'bgColor']
            ])
            if (! @state.nil? or ! @href.nil?) then
                i = XML::Node.new 'ItemIcon'
                Kamelopard.kml_array(i, [
                    [ @state, 'state' ],
                    [ @href, 'href' ]
                ])
                k << i
            end
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's PolyStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    class PolyStyle < ColorStyle
        attr_accessor :fill, :outline

        def initialize(options = {})
#fill = 1, outline = 1, color = 'ffffffff', colormode = :normal)
            @fill = 1
            @outline = 1
            super nil, options
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'PolyStyle'
            super k
            Kamelopard.kml_array( k, [
                [ @fill, 'fill' ],
                [ @outline, 'outline' ]
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Abstract class corresponding to KML's StyleSelector object.
    class StyleSelector < Object

        def initialize(options = {})
            super
            @attached = false
            DocumentHolder.instance.current_document.styles << self
        end

        def attached?
            @attached
        end

        def attach(obj)
            @attached = true
            obj.styles << self
        end

        def to_kml(elem = nil)
            elem = XML::Node.new 'StyleSelector' if elem.nil?
            super elem
            elem
        end
    end

    # Corresponds to KML's Style object. Attributes are expected to be IconStyle,
    # LabelStyle, LineStyle, PolyStyle, BalloonStyle, and ListStyle objects.
    class Style < StyleSelector
        attr_accessor :icon, :label, :line, :poly, :balloon, :list

        def to_kml(elem = nil)
            k = XML::Node.new 'Style'
            super k
            @icon.to_kml(k) unless @icon.nil?
            @label.to_kml(k) unless @label.nil?
            @line.to_kml(k) unless @line.nil?
            @poly.to_kml(k) unless @poly.nil?
            @balloon.to_kml(k) unless @balloon.nil?
            @list.to_kml(k) unless @list.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's StyleMap object.
    class StyleMap < StyleSelector
        # StyleMap manages pairs. The first entry in each pair is a string key, the
        # second is either a Style or a styleUrl. It will be assumed to be the
        # latter if its kind_of? method doesn't claim it's a Style object
        def initialize(pairs = {}, options = {})
            super options
            @pairs = pairs
        end

        # Adds a new Style to the StyleMap.
        def merge(a)
            @pairs.merge!(a)
        end

        def to_kml(elem = nil)
            t = XML::Node.new 'StyleMap'
            super t
            @pairs.each do |k, v|
                p = XML::Node.new 'Pair'
                key = XML::Node.new 'key'
                key << k.to_s
                p. << key
                if v.kind_of? Style then
                    v.to_kml(p)
                else
                    s = XML::Node.new 'styleUrl'
                    s << v.to_s
                    p << s
                end
                t << p
            end
            elem << t unless elem.nil?
            t
        end
    end

    # Corresponds to KML's Placemark objects. The geometry attribute requires a
    # descendant of Geometry
    class Placemark < Feature
        attr_accessor :name, :geometry, :balloonVisibility

        def initialize(name = nil, options = {})
            super
            @name = name unless name.nil?
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Placemark'
            super k
            @geometry.to_kml(k) unless @geometry.nil?
            if ! @balloonVisibility.nil? then
                 x = XML::Node.new 'gx:balloonVisibility'
                 x << ( @balloonVisibility ? 1 : 0 )
                 k << x
            end
            elem << k unless elem.nil?
            k
        end

        def to_s
            "Placemark id #{ @kml_id } named #{ @name }"
        end

        def longitude
            @geometry.longitude
        end

        def latitude
            @geometry.latitude
        end

        def altitude
            @geometry.altitude
        end

        def altitudeMode
            @geometry.altitudeMode
        end

        def point
            if @geometry.kind_of? Point then
                @geometry
            elsif @geometry.respond_to? :point then
                @geometry.point
            else
                raise "This placemark uses a non-point geometry, but the operation you're trying requires a point object"
            end
        end
    end

    # Abstract class corresponding to KML's gx:TourPrimitive object. Tours are made up
    # of descendants of these.
    # The :standalone option affects only initialization; there's no point in
    # doing anything with it after initialization. It determines whether the
    # TourPrimitive object is added to the current tour or not
    class TourPrimitive < Object
        attr_accessor :standalone

        def initialize(options = {})
            DocumentHolder.instance.current_document.tour << self unless options.has_key?(:standalone)
            super
        end
    end

    # Cooresponds to KML's gx:FlyTo object. The @view parameter needs to look like an
    # AbstractView object
    class FlyTo < TourPrimitive
        attr_accessor :duration, :mode, :view

        def initialize(view = nil, options = {})
            @duration = 0
            @mode = Kamelopard::DocumentHolder.instance.current_document.flyto_mode
            super options
            self.view= view unless view.nil?
        end

        def view=(view)
            if view.kind_of? AbstractView then
                @view = view
            elsif view.respond_to? :abstractView then
                @view = view.abstractView
            else
                @view = LookAt.new view
            end
        end

        def range=(range)
            if view.respond_to? 'range' and not range.nil? then
                @view.range = range
            end
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:FlyTo'
            super k

            #k.namespaces.namespace = XML::Namespaces.new(k, 'gx', 'http://www.google.com/kml/ext/2.2')
            Kamelopard.kml_array(k, [
                [ @duration, 'gx:duration' ],
                [ @mode, 'gx:flyToMode' ]
            ])
            @view.to_kml k unless @view.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's gx:AnimatedUpdate object. For now at least, this isn't very
    # intelligent; you've got to manually craft the <Change> tag(s) within the
    # object.
    class AnimatedUpdate < TourPrimitive
        # XXX For now, the user has to specify the change / create / delete elements in
        # the <Update> manually, rather than creating objects.
        attr_accessor :target, :delayedStart, :duration
        attr_reader :updates

        # The updates argument is an array of strings containing <Change> elements
        def initialize(updates, options = {})
         #duration = 0, target = '', delayedstart = nil)
            @updates = []
            super options
            @updates = updates unless updates.nil? or updates.size == 0
        end

        def target=(target)
            if target.kind_of? Object then
                @target = target.kml_id
            else
                @target = target
            end
        end

        def updates=(a)
            updates.each do |u| self.<<(u) end
        end

        # Adds another update string, presumably containing a <Change> element
        def <<(a)
            @updates << a
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:AnimatedUpdate'
            super(k)
            d = XML::Node.new 'gx:duration'
            d << @duration.to_s
            k << d
            if not @delayedStart.nil? then
                d = XML::Node.new 'gx:delayedStart'
                d << @delayedStart.to_s
                k << d
            end
            d = XML::Node.new 'Update'
            q = XML::Node.new 'targetHref'
            q << @target.to_s
            d << q
            @updates.each do |i|
                if i.is_a? XML::Node then
                    d << i
                else
                    parser = reader = XML::Parser.string(i)
                    doc = parser.parse
                    node = doc.child
                    n = node.copy true
                    d << n
                end
            end
            k << d
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:TourControl object
    class TourControl < TourPrimitive

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:TourControl'
            super(k)
            q = XML::Node.new 'gx:playMode'
            q << 'pause'
            k << q
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:Wait object
    class Wait < TourPrimitive
        attr_accessor :duration
        def initialize(duration = 0, options = {})
            super options
            @duration = duration
        end

        def self.parse(x)
            dur = nil
            id = x.attributes['id'] if x.attributes? 'id'
            w.find('//gx:duration').each do |d|
                dur = d.children[0].to_s.to_f
                return Wait.new(dur, :id => id)
            end
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:Wait'
            super k
            d = XML::Node.new 'gx:duration'
            d << @duration.to_s
            k << d
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:SoundCue object
    class SoundCue < TourPrimitive
        attr_accessor :href, :delayedStart
        def initialize(href, delayedStart = nil)
            super()
            @href = href
            @delayedStart = delayedStart
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:SoundCue'
            super k
            d = XML::Node.new 'href'
            d << @href.to_s
            k << d
            if not @delayedStart.nil? then
                d = XML::Node.new 'gx:delayedStart'
                d << @delayedStart.to_s
                k << d
            end
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:Tour object
    class Tour < Object
        attr_accessor :name, :description, :last_abs_view, :playlist, :icon

        def initialize(name = nil, description = nil, no_wait = false)
            super()
            @name = name
            @description = description
            @playlist = []
            DocumentHolder.instance.current_document.tours << self
            Wait.new(0.1, :comment => "This wait is automatic, and helps prevent animation glitches") unless no_wait
        end

        # Add another element to this Tour
        def <<(a)
            @playlist << a
            @last_abs_view = a.view if a.kind_of? FlyTo
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:Tour'
            super k
            Kamelopard.kml_array(k, [
                [ @name, 'name' ],
                [ @description, 'description' ],
            ])
            p = XML::Node.new 'gx:Playlist'
            @playlist.map do |a| a.to_kml p end
            k << p
            elem << k unless elem.nil?
            k
        end
    end

    # Abstract class corresponding to the KML Overlay object
    class Overlay < Feature
        attr_accessor :color, :drawOrder

        include Icon

        def initialize(options = {})
            super nil, options
            DocumentHolder.instance.current_document.folder << self
        end

        def to_kml(elem)
            super
            Kamelopard.kml_array(elem, [
                [ @color, 'color' ],
                [ @drawOrder, 'drawOrder' ],
            ])
            icon_to_kml(elem)
            elem
        end
    end

    # Corresponds to KML's ScreenOverlay object
    class ScreenOverlay < Overlay
        attr_accessor :overlayXY, :screenXY, :rotationXY, :size, :rotation, :balloonVisibility

        def to_kml(elem = nil)
            k = XML::Node.new 'ScreenOverlay'
            super k
            @overlayXY.to_kml('overlayXY', k)   unless @overlayXY.nil?
            @screenXY.to_kml('screenXY', k)     unless @screenXY.nil?
            @rotationXY.to_kml('rotationXY', k) unless @rotationXY.nil?
            @size.to_kml('size', k)             unless @size.nil?
            if ! @rotation.nil? then
                d = XML::Node.new 'rotation'
                d << @rotation.to_s
                k << d
            end
            if ! @balloonVisibility.nil? then
                 x = XML::Node.new 'gx:balloonVisibility'
                 x << ( @balloonVisibility ? 1 : 0 )
                 k << x
            end
            elem << k unless elem.nil?
            k
        end
    end

    # Supporting module for the PhotoOverlay class
    module ViewVolume
        attr_accessor :leftFov, :rightFov, :bottomFov, :topFov, :near

        def viewVolume_to_kml(elem = nil)
            p = XML::Node.new 'ViewVolume'
            {
                :near => @near,
                :leftFov => @leftFov,
                :rightFov => @rightFov,
                :topFov => @topFov,
                :bottomFov => @bottomFov
            }.each do |k, v|
                d = XML::Node.new k.to_s
                v = 0 if v.nil?
                d << v.to_s
                p << d
            end
            elem << p unless elem.nil?
            p
        end
    end

    # Supporting module for the PhotoOverlay class
    module ImagePyramid
        attr_accessor :tileSize, :maxWidth, :maxHeight, :gridOrigin

        def imagePyramid_to_kml(elem = nil)
            @tileSize = 256 if @tileSize.nil?
            p = XML::Node.new 'ImagePyramid'
            {
                :tileSize => @tileSize,
                :maxWidth => @maxWidth,
                :maxHeight => @maxHeight,
                :gridOrigin => @gridOrigin
            }.each do |k, v|
                d = XML::Node.new k.to_s
                v = 0 if v.nil?
                d << v.to_s
                p << d
            end
            elem << p unless elem.nil?
            p
        end
    end

    # Corresponds to KML's PhotoOverlay class
    class PhotoOverlay < Overlay
        attr_accessor :rotation, :point, :shape

        include ViewVolume
        include ImagePyramid

        def initialize(options = {})
            super
        end

        def point=(point)
            if point.respond_to?('point')
                @point = point.point
            else
                @point = point
            end
        end

        def to_kml(elem = nil)
            p = XML::Node.new 'PhotoOverlay'
            super p
            viewVolume_to_kml p
            imagePyramid_to_kml p
            p << @point.to_kml(nil, true)
            {
                :rotation => @rotation,
                :shape => @shape
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                p << d
            end
            elem << p unless elem.nil?
            p
        end
    end

    # Corresponds to KML's LatLonBox and LatLonAltBox
    class LatLonBox
        attr_reader :north, :south, :east, :west
        attr_accessor :rotation, :minAltitude, :maxAltitude, :altitudeMode

        def initialize(north, south, east, west, rotation = 0, minAltitude = nil, maxAltitude = nil, altitudeMode = :clampToGround)
            @north = Kamelopard.convert_coord north
            @south = Kamelopard.convert_coord south
            @east = Kamelopard.convert_coord east
            @west = Kamelopard.convert_coord west
            @minAltitude = minAltitude
            @maxAltitude = maxAltitude
            @altitudeMode = altitudeMode
            @rotation = rotation
        end

        def north=(a)
            @north = Kamelopard.convert_coord a
        end

        def south=(a)
            @south = Kamelopard.convert_coord a
        end

        def east=(a)
            @east = Kamelopard.convert_coord a
        end

        def west=(a)
            @west = Kamelopard.convert_coord a
        end

        def to_kml(elem = nil, alt = false)
            name = alt ? 'LatLonAltBox' : 'LatLonBox'
            k = XML::Node.new name
            [
                ['north', @north],
                ['south', @south],
                ['east', @east],
                ['west', @west],
                ['minAltitude', @minAltitude],
                ['maxAltitude', @maxAltitude]
            ].each do |a|
                if not a[1].nil? then
                    m = XML::Node.new a[0]
                    m << a[1].to_s
                    k << m
                end
            end
            if (not @minAltitude.nil? or not @maxAltitude.nil?) then
                Kamelopard.add_altitudeMode(@altitudeMode, k)
            end
            m = XML::Node.new 'rotation'
            m << @rotation.to_s
            k << m
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's gx:LatLonQuad object
    class LatLonQuad
        attr_accessor :lowerLeft, :lowerRight, :upperRight, :upperLeft
        def initialize(lowerLeft, lowerRight, upperRight, upperLeft)
            @lowerLeft = lowerLeft
            @lowerRight = lowerRight
            @upperRight = upperRight
            @upperLeft = upperLeft
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:LatLonQuad'
            d = XML::Node.new 'coordinates'
            d << "#{ @lowerLeft.longitude },#{ @lowerLeft.latitude } #{ @lowerRight.longitude },#{ @lowerRight.latitude } #{ @upperRight.longitude },#{ @upperRight.latitude } #{ @upperLeft.longitude },#{ @upperLeft.latitude }"
            k << d
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's GroundOverlay object
    class GroundOverlay < Overlay
        attr_accessor :altitude, :altitudeMode, :latlonbox, :latlonquad
        def initialize(icon, options = {})
            @altitude = 0
            @altitudeMode = :clampToGround
            @href = icon
            super options
        end

        def to_kml(elem = nil)
            raise "Either latlonbox or latlonquad must be non-nil" if @latlonbox.nil? and @latlonquad.nil?
            k = XML::Node.new 'GroundOverlay'
            super k
            d = XML::Node.new 'altitude'
            d << @altitude.to_s
            k << d
            Kamelopard.add_altitudeMode(@altitudeMode, k)
            @latlonbox.to_kml(k) unless @latlonbox.nil?
            @latlonquad.to_kml(k) unless @latlonquad.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to the LOD (Level of Detail) object
    class Lod
        attr_accessor :minpixels, :maxpixels, :minfade, :maxfade
        def initialize(minpixels, maxpixels, minfade, maxfade)
            @minpixels = minpixels
            @maxpixels = maxpixels
            @minfade = minfade
            @maxfade = maxfade
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Lod'
            m = XML::Node.new 'minLodPixels'
            m << @minpixels.to_s
            k << m
            m = XML::Node.new 'maxLodPixels'
            m << @maxpixels.to_s
            k << m
            m = XML::Node.new 'minFadeExtent'
            m << @minfade.to_s
            k << m
            m = XML::Node.new 'maxFadeExtent'
            m << @maxfade.to_s
            k << m
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to the KML Region object
    class Region < Object
        attr_accessor :latlonaltbox, :lod

        def initialize(options = {})
            super
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Region'
            super k
            @latlonaltbox.to_kml(k, true) unless @latlonaltbox.nil?
            @lod.to_kml(k) unless @lod.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Sub-object in the KML Model class
    class Orientation
        attr_accessor :heading, :tilt, :roll
        def initialize(heading, tilt, roll)
            @heading = heading
            # Although the KML reference by Google is clear on these ranges, Google Earth
            # supports values outside the ranges, and sometimes it's useful to use
            # them. So I'm turning off this error checking
            #raise "Heading should be between 0 and 360 inclusive; you gave #{ heading }" unless @heading <= 360 and @heading >= 0
            @tilt = tilt
            #raise "Tilt should be between 0 and 180 inclusive; you gave #{ tilt }" unless @tilt <= 180 and @tilt >= 0
            @roll = roll
            #raise "Roll should be between 0 and 180 inclusive; you gave #{ roll }" unless @roll <= 180 and @roll >= 0
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Orientation'
            {
                :heading => @heading,
                :tilt => @tilt,
                :roll => @roll
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            elem << x unless elem.nil?
            x
        end
    end

    # Sub-object in the KML Model class
    class Scale
        attr_accessor :x, :y, :z
        def initialize(x, y, z = 1)
            @x = x
            @y = y
            @z = z
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Scale'
            {
                :x => @x,
                :y => @y,
                :z => @z
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            elem << x unless elem.nil?
            x
        end
    end

    # Sub-object in the KML ResourceMap class
    class Alias
        attr_accessor :targetHref, :sourceHref
        def initialize(targetHref = nil, sourceHref = nil)
            @targetHref = targetHref
            @sourceHref = sourceHref
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Alias'
            {
                :targetHref => @targetHref,
                :sourceHref => @sourceHref,
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            elem << x unless elem.nil?
            x
        end
    end

    # Sub-object in the KML Model class
    class ResourceMap
        attr_accessor :aliases
        def initialize(aliases = [])
            @aliases = []
            if not aliases.nil? then
                if aliases.kind_of? Enumerable then
                    @aliases += aliases
                else
                    @aliases << aliases
                end
            end
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'ResourceMap'
            @aliases.each do |a| k << a.to_kml(k) end
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's Link object
    class Link < Object
        attr_accessor :href, :refreshMode, :refreshInterval, :viewRefreshMode, :viewBoundScale, :viewFormat, :httpQuery

        def initialize(href = '', options = {})
            super options
            @href = href unless href == ''
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Link'
            super x
            {
                :href => @href,
                :refreshMode => @refreshMode,
                :viewRefreshMode => @viewRefreshMode,
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            Kamelopard.kml_array(x, [
                [ @refreshInterval, 'refreshInterval' ],
                [ @viewBoundScale, 'viewBoundScale' ],
                [ @viewFormat, 'viewFormat' ],
                [ @httpQuery, 'httpQuery' ]
            ])
            elem << x unless elem.nil?
            x
        end
    end

    # Corresponds to the KML Model class
    class Model < Geometry
        attr_accessor :link, :location, :orientation, :scale, :resourceMap

        # location should be a Point, or some object that can behave like one,
        # including a Placemark. Model will get its Location and altitudeMode data
        # from this attribute
        def initialize(options = {})
         #link, location, orientation, scale, resourceMap)
            super
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Model'
            super x
            loc = XML::Node.new 'Location'
            {
                :longitude => @location.longitude,
                :latitude => @location.latitude,
                :altitude => @location.altitude,
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                loc << d
            end
            x << loc
            Kamelopard.add_altitudeMode(@location.altitudeMode, x)
            @link.to_kml x unless @link.nil?
            @orientation.to_kml x unless @orientation.nil?
            @scale.to_kml x unless @scale.nil?
            @resourceMap.to_kml x unless @resourceMap.nil?
            elem << x unless elem.nil?
            x
        end
    end

    # Corresponds to the KML Polygon class
    class Polygon < Geometry
        # NB!  No support for tessellate, because Google Earth doesn't support it, it seems
        attr_accessor :outer, :inner, :altitudeMode, :extrude

        def initialize(outer, options = {})
          #extrude = 0, altitudeMode = :clampToGround)
            @extrude = 0
            @altitudeMode = :clampToGround
            @inner = []
            @outer = outer
            super options
        end

        def inner=(a)
            if a.kind_of? Array then
                @inner = a
            else
                @inner = [ a ]
            end
        end

        def <<(a)
            @inner << a
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Polygon'
            super k
            e = XML::Node.new 'extrude'
            e << @extrude.to_s
            k << e
            Kamelopard.add_altitudeMode @altitudeMode, k
            e = XML::Node.new('outerBoundaryIs')
            e << @outer.to_kml
            k << e
            @inner.each do |i|
                e = XML::Node.new('innerBoundaryIs')
                e << i.to_kml
                k << e
            end
            elem << k unless elem.nil?
            k
        end
    end

    # Abstract class corresponding to KML's MultiGeometry object
    class MultiGeometry < Geometry
        attr_accessor :geometries

        def initialize(a = nil, options = {})
            @geometries = []
            @geometries << a unless a.nil?
            super options
        end

        def <<(a)
            @geometries << a
        end

        def to_kml(elem = nil)
            e = XML::Node.new 'MultiGeometry'
            @geometries.each do |g|
                g.to_kml e
            end
            elem << e unless elem.nil?
            e
        end
    end

    # Analogue of KML's NetworkLink class
    class NetworkLink < Feature
        attr_accessor :refreshVisibility, :flyToView, :link

        def initialize(href = '', options = {})
            super(( options[:name] || ''), options)
            @refreshMode ||= :onChange
            @viewRefreshMode ||= :never
            @link = Link.new(href, :refreshMode => @refreshMode, :viewRefreshMode => @viewRefreshMode)
            @refreshVisibility ||= 0
            @flyToView ||= 0
        end

        def refreshMode
            link.refreshMode
        end

        def viewRefreshMode
            link.viewRefreshMode
        end

        def href
            link.href
        end

        def refreshMode=(a)
            link.refreshMode = a
        end

        def viewRefreshMode=(a)
            link.viewRefreshMode = a
        end

        def href=(a)
            link.href = a
        end

        def to_kml(elem = nil)
            e = XML::Node.new 'NetworkLink'
            super e
            @link.to_kml e
            Kamelopard.kml_array(e, [
                [@flyToView, 'flyToView'],
                [@refreshVisibility, 'refreshVisibility']
            ])
            elem << e unless elem.nil?
            e
        end
    end

    # Corresponds to Google Earth's gx:Track extension to KML
    class Track < Geometry
        attr_accessor :altitudeMode, :when, :coord, :angles, :model
        def initialize(options = {})
            @when = []
            @coord = []
            @angles = []
            super
        end

        def to_kml(elem = nil)
            e = XML::Node.new 'gx:Track'
            [
                [ @coord, 'gx:coord' ],
                [ @when, 'when' ],
                [ @angles, 'gx:angles' ],
            ].each do |a|
                a[0].each do |g|
                    w = XML::Node.new a[1], g.to_s
                    e << w
                end
            end
            elem << e unless elem.nil?
            e
        end
    end

    # Viewsyncrelay action
    class VSRAction < Object
        attr_accessor :name, :tour_name, :verbose, :fail_count, :input,
            :action, :exit_action, :repeat, :constraints, :reset_constraints,
            :initially_disabled
        # XXX Consider adding some constraints, so that things like @name and @action don't go nil
        # XXX Also ensure constraints and reset_constraints are hashes,
        #   containing reasonable values, and reasonable keys ('latitude' vs.
        #   :latitude, for instance)

        def initialize(name, options = {})
            @name = name
            @constraints = {}
            @repeat = 'DEFAULT'
            @input = 'ALL'
            super(options)

            DocumentHolder.instance.current_document.vsr_actions << self
        end

        def to_hash
            a = {}
            a['name']               = @name               unless @name.nil?
            a['id']                 = @id                 unless @id.nil?
            a['input']              = @input              unless @input.nil?
            a['tour_name']          = @tour_name          unless @tour_name.nil?
            a['verbose']            = @verbose            unless @verbose.nil?
            a['fail_count']         = @fail_count         unless @fail_count.nil?
            a['action']             = @action             unless @action.nil?
            a['exit_action']        = @exit_action        unless @exit_action.nil?
            a['repeat']             = @repeat             unless @repeat.nil?
            a['initially_disabled'] = @initially_disabled unless @initially_disabled.nil?
            a['constraints']        = @constraints        unless @constraints.nil?
            a['reset_constraints']  = @reset_constraints  unless @reset_constraints.nil?
            a
        end
    end
end
# End of Kamelopard module
