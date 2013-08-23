module Kamelopard
module Regionate
    require 'ai4r'

    def self.find_cluster_center(cluster)
        v = []
        (1..(cluster.data_items.first.size)).each do |i|
            v << []
        end
        cluster.data_items.each do |data_item|
            data_item.each_with_index do |val, idx|
                v[idx] << val
            end
        end

        # Average each array
        v.collect { |elem|
            elem.inject(:+).to_f / elem.size
        }
    end

    def self.store_placemark(pl, h)
        g = pl.geometry
        h[g.longitude] = {} unless h.has_key? g.longitude
        h[g.longitude][g.latitude] = [] unless h[g.longitude].has_key? g.latitude
        h[g.longitude][g.latitude] << pl
    end

    # Regionate a bunch of placemarks. Add placemarks representing the centers
    # of the discovered clusters to a folder if one is provided.
    # Options:
    #   :folder => The folder to add placemarks for each region to. Defaults to
    #               nil, in which case no placemarks will be added
    #   :minlod => minLod value for each region, defaults to 12000
    #   :maxlod => minLod value for each region, defaults to -1
    def self.regionate(placemarks, count, options = {})
        include Ai4r::Data
        include Ai4r::Clusterers

        options[:minlod] = 12000 unless options.has_key? :minlod and not options[:minlod].nil?
        options[:maxlod] = -1    unless options.has_key? :maxlod and not options[:maxlod].nil?
        data = DataSet.new
        data.set_data_labels ['longitude', 'latitude', 'altitude']
        placemarks_hash = {}

        placemarks.each do |g|
            k = [ g.longitude.to_f, g.latitude.to_f, g.altitude.to_f ]
            data << k
            store_placemark(g, placemarks_hash)
        end
        clusterer = Diana.new.build(data, count)

        centers = []
        pmarks = []
        regions = []

        clusterer.clusters.each do |c|
            Kamelopard.log(:debug, 'regionate', "Here's a cluster: #{c.data_items.inspect}")

            doms = c.build_domains
            r = Kamelopard::Region.new(
                :latlonaltbox => Kamelopard::LatLonBox.new(
                    doms[1][1],
                    doms[1][0],
                    doms[0][1],
                    doms[0][0],
                    0
                ),
                :lod => Kamelopard::Lod.new(options[:minlod], options[:maxlod], 0, 0)
            )
            regions << r

            # Find placemarks in this cluster, and add region
            c.data_items.each do |d|
                Kamelopard.log(:debug, 'regionate', "Here's a (set of) placemark(s) in the cluster, for data item #{d}")
                placemarks_hash[d[0]][d[1]].each do |pl|
                    Kamelopard.log(:debug, 'regionate', "Found placemark #{pl.name} in the cluster")
                    pl.region = r
                end
            end

            center = find_cluster_center c
            centers << center
            pl = placemark center.to_s, :geometry => point(center[0], center[1], center[2])
            pl.region = Kamelopard::Region.new(
                :latlonaltbox => Kamelopard::LatLonBox.new(
                    doms[1][1],
                    doms[1][0],
                    doms[0][1],
                    doms[0][0],
                    0
                ),
                :lod => Kamelopard::Lod.new(-1, options[:minlod], 0, 0)
            )
            options[:folder] << pl unless options[:folder].nil?
            pmarks << pl
        end

        [ centers, pmarks ]
    end
end
end
