module Kamelopard
module Regionate
    #require 'ai4r'
    require 'bundler/setup'
    require 'hierclust'

    class Hierclust::Point
        attr_accessor :placemark
        def <=>(a)
            raise "Something called this!"
        end

        def distance_to(b)
            if self.is_a? Hierclust::Point then
                pt1 = point(self.x, self.y)
            else
                pt1 = self.placemark.geometry
            end
            if b.is_a? Hierclust::Point then
                pt2 = point(b.x, b.y)
            else
                pt2 = b.placemark.geometry
            end
            great_circle_distance(pt1, pt2)
        end
    end

    # Regionate a bunch of placemarks. Add placemarks representing the centers
    # of the discovered clusters to a folder if one is provided.
    # Options:
    #   :folder => The folder to add placemarks for each region to. Defaults to
    #               nil, in which case no placemarks will be added
    #   :minlod => minLod value for each region, defaults to 12000
    #   :maxlod => minLod value for each region, defaults to -1 #   :dist   => minimum distance in degrees of lat/long between cluster centers
    #def self.regionate(placemarks, count, options = {})
    def self.regionate(placemarks, dist, options = {})
        #include Ai4r::Data
        #include Ai4r::Clusterers

        options[:minlod] = 12000 unless options.has_key? :minlod and not options[:minlod].nil?
        options[:maxlod] = -1    unless options.has_key? :maxlod and not options[:maxlod].nil?
        hierpoints = []

        placemarks.each do |g|
            h = Hierclust::Point.new(g.longitude.to_f, g.latitude.to_f)
            h.placemark = g
            hierpoints << h
        end
        clusterer = Hierclust::Clusterer.new(hierpoints, dist)

        centers = []
        pmarks = []
        regions = []

        clusterer.clusters.each do |c|
            Kamelopard.log(:debug, 'regionate', "Here's a cluster: #{c.points}")

            r = Kamelopard::Region.new(
                 # Do something based on ... dist, perhaps, when radius is 0
                :latlonaltbox => Kamelopard::LatLonBox.new(
                    # n, s, e, w
                    c.y + c.radius,
                    c.y - c.radius,
                    c.x + c.radius,
                    c.x - c.radius,
                    0
                ),
                :lod => Kamelopard::Lod.new(options[:minlod], options[:maxlod], 0, 0)
            #    -                :lod => Kamelopard::Lod.new(-1, options[:minlod], 0, 0)
            )
            regions << r

            # Find placemarks in this cluster, and add region
            c.points.each do |pt|
                Kamelopard.log(:debug, 'regionate', "Found placemark #{pt.placemark.name} in the cluster")
                pt.placemark.region = r
            end

            pl = placemark "#{c.size}-element cluster at #{c.y}, #{c.x}", :geometry => point(c.x, c.y, 0)
            c_r = Kamelopard::Region.new(
                :latlonaltbox => Kamelopard::LatLonBox.new(
                    # n, s, e, w
                    c.y + c.radius,
                    c.y - c.radius,
                    c.x + c.radius,
                    c.x - c.radius,
                    0
                ),
                :lod => Kamelopard::Lod.new(-1, options[:minlod], 0, 0)
            )
            pl.region = c_r
            options[:folder] << pl unless options[:folder].nil?
            pmarks << pl
        end

        [ clusterer.clusters, centers, pmarks ]
    end
end
end
